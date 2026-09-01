package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// Handler takes reports and does the three things in order: store, notify,
// answer.
type Handler struct {
	Token    string
	Store    Store
	Notifier Notifier
	Limiter  *Limiter
	Log      *slog.Logger

	// How long storage and mail get before being given up on. A caregiver is
	// waiting at a screen, and a request that hangs is worse than one that
	// fails: the failure keeps their report and tells them to try again.
	Timeout time.Duration

	now func() time.Time
}

func (h *Handler) clock() time.Time {
	if h.now != nil {
		return h.now()
	}
	return time.Now()
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "post a report", http.StatusMethodNotAllowed)
		return
	}

	// Cheapest checks first, so a flood costs as little as possible: address
	// before credentials, credentials before reading a body.
	if h.Limiter != nil && !h.Limiter.Allow(ClientAddress(r)) {
		http.Error(w, "too many", http.StatusTooManyRequests)
		return
	}

	if !h.authorised(r) {
		// No detail. A report screen is not a place to learn about tokens, and
		// the app turns any 401 into "update the app".
		http.Error(w, "no", http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxBody+1))
	if err != nil {
		// Includes a body that ran past the cap, whatever Content-Length
		// claimed. Never trust the declared length.
		http.Error(w, "too long", http.StatusRequestEntityTooLarge)
		return
	}
	if len(body) > MaxBody {
		http.Error(w, "too long", http.StatusRequestEntityTooLarge)
		return
	}

	report, err := ParseReport(body)
	if err != nil {
		if errors.Is(err, ErrBadRequest) {
			h.Log.Info("refused a report", "why", err)
			http.Error(w, "not a report this build takes", http.StatusBadRequest)
			return
		}
		http.Error(w, "not a report this build takes", http.StatusBadRequest)
		return
	}

	reference, err := NewReference()
	if err != nil {
		h.Log.Error("could not make a reference", "err", err)
		http.Error(w, "try again", http.StatusServiceUnavailable)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), h.timeout())
	defer cancel()

	key := StorageKey(h.clock(), report.Kind, reference)

	// **Stored before it is acknowledged.** The app tells a caregiver "sent"
	// on a 202, so a 202 has to mean the report is somewhere durable. A report
	// the app still holds can be sent again; one it believes it delivered is
	// gone.
	if err := h.Store.Put(ctx, key, report.Raw); err != nil {
		h.Log.Error("could not store a report", "key", key, "err", err)
		http.Error(w, "try again", http.StatusServiceUnavailable)
		return
	}

	// Mail is best effort, and deliberately after the point of no return. A
	// report that is stored and not emailed still exists; failing here would
	// tell a caregiver it did not arrive when it did.
	subject, text := notification(report, reference, key)
	if err := h.Notifier.Notify(ctx, subject, text); err != nil {
		h.Log.Error("stored but could not notify", "key", key, "err", err)
	}

	h.Log.Info("took a report", "kind", report.Kind, "reference", reference, "key", key)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{"reference": reference})
}

func (h *Handler) timeout() time.Duration {
	if h.Timeout > 0 {
		return h.Timeout
	}
	return 10 * time.Second
}

// authorised checks the bearer token in constant time.
//
// The token is compiled into the app and is extractable from the binary, so it
// is not a security control — it is there so the endpoint is not trivially
// discoverable, and so it can be rotated. Constant time anyway: it costs one
// function call and the alternative is a timing oracle for the one secret
// here.
func (h *Handler) authorised(r *http.Request) bool {
	header := r.Header.Get("Authorization")
	presented, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(presented), []byte(h.Token)) == 1
}
