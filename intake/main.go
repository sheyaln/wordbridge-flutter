// The wordbridge report intake.
//
// One endpoint. It takes the report a caregiver read and pressed send on
// (REQUIREMENTS.md §4.52), writes it to object storage, and sends an email
// saying one arrived.
//
// What it does not do is as much the point as what it does. It does not track,
// does not set a cookie, does not redirect, and writes no address anywhere: an
// address exists in memory for as long as rate limiting needs it and dies with
// the instance. The app on the other end never sends anything on its own, so
// every request here is a person who decided to make it.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	if err := run(log); err != nil {
		log.Error("stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	token := os.Getenv("INTAKE_TOKEN")
	if token == "" {
		return errors.New("INTAKE_TOKEN is not set, and an intake with no token would take anything from anybody")
	}

	store, err := storeFromEnv()
	if err != nil {
		return err
	}

	handler := &Handler{
		Token:    token,
		Store:    store,
		Notifier: notifierFromEnv(log),
		Limiter:  NewLimiter(10, time.Minute, time.Hour),
		Log:      log,
	}

	mux := http.NewServeMux()
	mux.Handle("POST /v1/reports", handler)
	// Answers without touching storage or mail, so a health check cannot be
	// the thing that wakes a bucket up.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	server := &http.Server{
		Addr:              ":" + port(),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// A container that is being replaced finishes what it is holding. Somebody
	// is waiting at a screen for the request in flight.
	stopping := make(chan os.Signal, 1)
	signal.Notify(stopping, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-stopping
		log.Info("draining")
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()

	log.Info("listening", "addr", server.Addr)
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func port() string {
	if p := os.Getenv("PORT"); p != "" {
		return p
	}
	return "8080"
}

func storeFromEnv() (Store, error) {
	required := map[string]string{
		"S3_ENDPOINT":   os.Getenv("S3_ENDPOINT"),
		"S3_BUCKET":     os.Getenv("S3_BUCKET"),
		"S3_ACCESS_KEY": os.Getenv("S3_ACCESS_KEY"),
		"S3_SECRET_KEY": os.Getenv("S3_SECRET_KEY"),
	}
	for name, value := range required {
		if value == "" {
			return nil, fmt.Errorf("%s is not set, and a report that is not stored is a report that was lost", name)
		}
	}

	region := os.Getenv("S3_REGION")
	if region == "" {
		region = "fr-par"
	}

	return NewObjectStore(
		required["S3_ENDPOINT"],
		region,
		required["S3_BUCKET"],
		required["S3_ACCESS_KEY"],
		required["S3_SECRET_KEY"],
	)
}

// notifierFromEnv returns a mailer, or one that does nothing.
//
// A deployment with no mail settings is a valid deployment: reports are taken
// and stored, and somebody reads the bucket. Refusing to start over a missing
// mail password would trade every report for a setting.
func notifierFromEnv(log *slog.Logger) Notifier {
	host := os.Getenv("SMTP_HOST")
	to := os.Getenv("MAIL_TO")
	from := os.Getenv("MAIL_FROM")

	if host == "" || to == "" || from == "" {
		log.Warn("no mail settings, so reports will be stored and not announced")
		return NoNotifier{}
	}

	smtpPort := os.Getenv("SMTP_PORT")
	if smtpPort == "" {
		smtpPort = "587"
	}

	return &SMTPNotifier{
		Host: host,
		Port: smtpPort,
		User: os.Getenv("SMTP_USER"),
		Pass: os.Getenv("SMTP_PASS"),
		From: from,
		To:   splitList(to),
	}
}

func splitList(value string) []string {
	var out []string
	for _, part := range strings.Split(value, ",") {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
