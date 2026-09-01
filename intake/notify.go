package main

import (
	"context"
	"fmt"
	"net/smtp"
	"strings"
)

// Notifier tells somebody a report arrived.
//
// Best effort by contract. A report that is stored and not emailed is a report
// that exists; failing the request over it would tell a caregiver their report
// did not arrive when it did, and that is the one lie this service must not
// tell.
type Notifier interface {
	Notify(ctx context.Context, subject, body string) error
}

// SMTPNotifier sends through any SMTP relay.
//
// SMTP rather than a provider's own HTTP API, because it is the one interface
// every transactional mail service offers. Scaleway TEM, SES, SendGrid and a
// mail server somebody runs themselves are all the same four settings, which
// keeps the provider decision reversible.
type SMTPNotifier struct {
	Host string
	Port string
	User string
	Pass string
	From string
	To   []string
}

func (n *SMTPNotifier) Notify(ctx context.Context, subject, body string) error {
	addr := n.Host + ":" + n.Port
	auth := smtp.PlainAuth("", n.User, n.Pass, n.Host)

	message := []byte(
		"From: " + n.From + "\r\n" +
			"To: " + strings.Join(n.To, ", ") + "\r\n" +
			"Subject: " + subject + "\r\n" +
			"Content-Type: text/plain; charset=UTF-8\r\n" +
			"\r\n" + body,
	)

	return smtp.SendMail(addr, auth, n.From, n.To, message)
}

// NoNotifier is what runs when no mail settings were given.
//
// A deployment without them is a valid one — reports are still taken and still
// stored, and somebody reads the bucket. Silently doing nothing is right here;
// refusing to start would trade every report for a missing setting.
type NoNotifier struct{}

func (NoNotifier) Notify(context.Context, string, string) error { return nil }

// notification is what lands in the mailbox.
//
// The note in full, because that is the part a person wrote and the reason to
// open the mail at all. **Not the stack trace**: it is long, it is already in
// the bucket, and a mailbox is a worse place for it than object storage with a
// lifecycle rule on it.
func notification(r *Report, reference, key string) (subject, body string) {
	subject = fmt.Sprintf("wordbridge %s · %s", r.Kind, reference)

	var b strings.Builder
	fmt.Fprintf(&b, "%s\n\n", strings.TrimSpace(r.Note))
	fmt.Fprintf(&b, "kind      %s\n", r.Kind)
	fmt.Fprintf(&b, "reference %s\n", reference)
	fmt.Fprintf(&b, "app       %s (%s)\n", r.App.Version, r.App.Build)
	fmt.Fprintf(&b, "device    %s %s", r.Device.Platform, r.Device.OS)
	if r.Device.Model != "" {
		fmt.Fprintf(&b, " · %s", r.Device.Model)
	}
	fmt.Fprintf(&b, " · %s\n", r.Device.Locale)
	fmt.Fprintf(&b, "board     %dx%d, level %d, %s voice\n",
		r.Board.Rows, r.Board.Cols, r.Board.Level, r.Board.Engine)

	if r.HasDetail {
		b.WriteString("\nA scrubbed stack trace came with this. It is in the object, not here.\n")
	}
	if r.HasVoice {
		b.WriteString("Neural voice measurements came with this.\n")
	}

	fmt.Fprintf(&b, "\n%s\n", key)
	return subject, b.String()
}
