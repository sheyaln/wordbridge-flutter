package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type recordingStore struct {
	keys []string
	body [][]byte
	err  error
}

func (s *recordingStore) Put(_ context.Context, key string, body []byte) error {
	if s.err != nil {
		return s.err
	}
	s.keys = append(s.keys, key)
	s.body = append(s.body, body)
	return nil
}

type recordingNotifier struct {
	subjects []string
	bodies   []string
	err      error
}

func (n *recordingNotifier) Notify(_ context.Context, subject, body string) error {
	n.subjects = append(n.subjects, subject)
	n.bodies = append(n.bodies, body)
	return n.err
}

func quiet() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func newHandler(store Store, notifier Notifier) *Handler {
	return &Handler{
		Token:    "secret",
		Store:    store,
		Notifier: notifier,
		Limiter:  NewLimiter(100, time.Second, time.Hour),
		Log:      quiet(),
		now:      func() time.Time { return time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC) },
	}
}

func post(h *Handler, body string, headers map[string]string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodPost, "/v1/reports", strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer secret")
	r.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		r.Header.Set(k, v)
	}

	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestAcceptedReportIsStoredAndAnswered(t *testing.T) {
	store := &recordingStore{}
	notifier := &recordingNotifier{}
	w := post(newHandler(store, notifier), realReport, nil)

	if w.Code != http.StatusAccepted {
		t.Fatalf("status %d, body %q", w.Code, w.Body.String())
	}

	var answer struct {
		Reference string `json:"reference"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &answer); err != nil {
		t.Fatalf("answer is not JSON: %v", err)
	}
	if !strings.HasPrefix(answer.Reference, "WB-") {
		t.Errorf("reference %q, which the app shows to a caregiver", answer.Reference)
	}

	if len(store.keys) != 1 {
		t.Fatalf("stored %d reports", len(store.keys))
	}
	if want := "2026/09/01/bug/" + answer.Reference + ".json"; store.keys[0] != want {
		t.Errorf("key %q, wanted %q", store.keys[0], want)
	}
}

// The whole reason store comes before notify. The app tells a caregiver "sent"
// on a 202, so a 202 has to mean the report is somewhere durable.
func TestStorageFailureIsNeverAnsweredAsSent(t *testing.T) {
	store := &recordingStore{err: errors.New("bucket is gone")}
	notifier := &recordingNotifier{}
	w := post(newHandler(store, notifier), realReport, nil)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status %d, wanted 503 so the app keeps the report", w.Code)
	}
	if strings.Contains(w.Body.String(), "reference") {
		t.Error("gave a reference for a report that was never stored")
	}
	if len(notifier.subjects) != 0 {
		t.Error("emailed about a report that was never stored")
	}
}

// And the reason notify comes after. A report that is stored and not emailed
// still exists; failing here would tell a caregiver it did not arrive when it
// did.
func TestMailFailureDoesNotFailTheReport(t *testing.T) {
	store := &recordingStore{}
	notifier := &recordingNotifier{err: errors.New("relay refused")}
	w := post(newHandler(store, notifier), realReport, nil)

	if w.Code != http.StatusAccepted {
		t.Fatalf("status %d, wanted 202: the report is stored", w.Code)
	}
	if len(store.keys) != 1 {
		t.Error("the report was not stored")
	}
}

func TestStoresExactlyWhatArrived(t *testing.T) {
	// Byte for byte. A server that re-encodes what it stores is a server that
	// can drop a field it did not model.
	body := `{"schema":1,"kind":"idea","note":"x","future":{"a":1}}`
	store := &recordingStore{}
	post(newHandler(store, &recordingNotifier{}), body, nil)

	if got := string(store.body[0]); got != body {
		t.Errorf("stored %q, wanted the bytes that arrived", got)
	}
}

func TestAuthorisation(t *testing.T) {
	cases := []struct {
		name   string
		header string
		want   int
	}{
		{"the right token", "Bearer secret", http.StatusAccepted},
		{"the wrong token", "Bearer wrong", http.StatusUnauthorized},
		{"no scheme", "secret", http.StatusUnauthorized},
		{"the wrong scheme", "Basic secret", http.StatusUnauthorized},
		{"nothing at all", "", http.StatusUnauthorized},
		{"a prefix of the token", "Bearer sec", http.StatusUnauthorized},
		{"the token with something after it", "Bearer secretmore", http.StatusUnauthorized},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			h := newHandler(&recordingStore{}, &recordingNotifier{})
			r := httptest.NewRequest(http.MethodPost, "/v1/reports", strings.NewReader(realReport))
			if c.header != "" {
				r.Header.Set("Authorization", c.header)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)

			if w.Code != c.want {
				t.Errorf("status %d, wanted %d", w.Code, c.want)
			}
		})
	}
}

func TestRejectionSaysNothingAboutTokens(t *testing.T) {
	// The app turns any 401 into "update the app". Nothing here should teach
	// somebody probing the endpoint what it wants.
	h := newHandler(&recordingStore{}, &recordingNotifier{})
	r := httptest.NewRequest(http.MethodPost, "/v1/reports", strings.NewReader(realReport))
	r.Header.Set("Authorization", "Bearer wrong")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if strings.Contains(strings.ToLower(w.Body.String()), "token") {
		t.Errorf("body %q names the thing that was wrong", w.Body.String())
	}
}

func TestBadReportIsFourHundred(t *testing.T) {
	// Not 503. The two mean opposite things to the app: one says do not try
	// this again, the other says try later.
	store := &recordingStore{}
	w := post(newHandler(store, &recordingNotifier{}), `{"schema":99,"kind":"bug"}`, nil)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status %d", w.Code)
	}
	if len(store.keys) != 0 {
		t.Error("stored a report it had refused")
	}
}

func TestOversizeBodyIsRefusedWhateverContentLengthClaims(t *testing.T) {
	// The cap is enforced on what is read, not on what the caller declared.
	big := `{"schema":1,"kind":"bug","note":"` + strings.Repeat("x", MaxBody) + `"}`

	h := newHandler(&recordingStore{}, &recordingNotifier{})
	r := httptest.NewRequest(http.MethodPost, "/v1/reports", strings.NewReader(big))
	r.Header.Set("Authorization", "Bearer secret")
	r.ContentLength = 12 // a lie
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("status %d, wanted 413", w.Code)
	}
}

func TestOnlyPost(t *testing.T) {
	h := newHandler(&recordingStore{}, &recordingNotifier{})
	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodDelete} {
		r := httptest.NewRequest(method, "/v1/reports", nil)
		r.Header.Set("Authorization", "Bearer secret")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)

		if w.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s got %d", method, w.Code)
		}
	}
}

func TestRateLimitedBeforeAnythingIsRead(t *testing.T) {
	// Cheapest checks first, so a flood costs as little as possible. A limited
	// request must not reach storage.
	store := &recordingStore{}
	h := newHandler(store, &recordingNotifier{})
	h.Limiter = NewLimiter(2, time.Hour, time.Hour)

	for i := 0; i < 2; i++ {
		if w := post(h, realReport, nil); w.Code != http.StatusAccepted {
			t.Fatalf("request %d got %d", i, w.Code)
		}
	}

	w := post(h, realReport, nil)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("third request got %d, wanted 429", w.Code)
	}
	if len(store.keys) != 2 {
		t.Errorf("stored %d, so a limited request still reached the bucket", len(store.keys))
	}
}

func TestTheLimitIsPerAddress(t *testing.T) {
	// One noisy client must not stop everybody else reporting.
	h := newHandler(&recordingStore{}, &recordingNotifier{})
	h.Limiter = NewLimiter(1, time.Hour, time.Hour)

	if w := post(h, realReport, map[string]string{"X-Forwarded-For": "203.0.113.1"}); w.Code != http.StatusAccepted {
		t.Fatalf("first client got %d", w.Code)
	}
	if w := post(h, realReport, map[string]string{"X-Forwarded-For": "203.0.113.1"}); w.Code != http.StatusTooManyRequests {
		t.Fatalf("first client's second got %d", w.Code)
	}
	if w := post(h, realReport, map[string]string{"X-Forwarded-For": "203.0.113.2"}); w.Code != http.StatusAccepted {
		t.Errorf("a different client got %d", w.Code)
	}
}

func TestNotificationCarriesTheNoteAndNotTheTrace(t *testing.T) {
	notifier := &recordingNotifier{}
	body := `{"schema":1,"kind":"crash","note":"it stopped talking",
	          "app":{"version":"0.1.0","build":"1"},
	          "device":{"platform":"ios","os":"18.5","model":"iPad11,1","locale":"en_GB"},
	          "board":{"rows":7,"cols":12,"level":2,"engine":"neural"},
	          "detail":"Bad state: a very long stack trace indeed"}`

	post(newHandler(&recordingStore{}, notifier), body, nil)

	mail := notifier.bodies[0]
	if !strings.Contains(mail, "it stopped talking") {
		t.Error("the note is the reason to open the mail and it is not in it")
	}
	if strings.Contains(mail, "a very long stack trace") {
		t.Error("the trace is in the mail; it belongs in the bucket")
	}
	if !strings.Contains(mail, "iPad11,1") {
		t.Error("no model, so a timing or a crash cannot be placed")
	}
	if !strings.Contains(notifier.subjects[0], "crash") {
		t.Errorf("subject %q does not say what kind it is", notifier.subjects[0])
	}
}

func TestNotificationSaysWhatCameWithTheReport(t *testing.T) {
	notifier := &recordingNotifier{}
	post(newHandler(&recordingStore{}, notifier),
		`{"schema":1,"kind":"bug","note":"x","voice":{"voice_id":"af_heart"}}`, nil)

	if !strings.Contains(notifier.bodies[0], "voice measurements") {
		t.Error("nothing said the voice numbers are there to look at")
	}
}

// counting wraps a body and reports how much of it was actually consumed.
type counting struct {
	r    io.Reader
	read int
}

func (c *counting) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.read += n
	return n, err
}

func TestAnEnormousBodyIsNotBufferedBeforeItIsRefused(t *testing.T) {
	// Checking the length after reading is not enough: without a cap on the
	// read itself, anybody can stream gigabytes at a container with a fixed
	// memory limit and the refusal arrives after the damage. The refusal has
	// to happen while reading.
	flood := &counting{r: io.LimitReader(neverEnding{}, 8<<20)}

	h := newHandler(&recordingStore{}, &recordingNotifier{})
	r := httptest.NewRequest(http.MethodPost, "/v1/reports", flood)
	r.Header.Set("Authorization", "Bearer secret")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status %d, wanted 413", w.Code)
	}
	if flood.read > MaxBody*2 {
		t.Errorf("read %d bytes of an 8 MB body before refusing it", flood.read)
	}
}

type neverEnding struct{}

func (neverEnding) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'x'
	}
	return len(p), nil
}
