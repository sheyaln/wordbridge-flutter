package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestBurstThenRefusal(t *testing.T) {
	l := NewLimiter(3, time.Minute, time.Hour)

	for i := 0; i < 3; i++ {
		if !l.Allow("a") {
			t.Fatalf("refused request %d of the burst", i)
		}
	}
	if l.Allow("a") {
		t.Error("allowed a fourth")
	}
}

func TestTheAllowanceComesBack(t *testing.T) {
	now := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	l := NewLimiter(1, time.Minute, time.Hour)
	l.now = func() time.Time { return now }

	if !l.Allow("a") {
		t.Fatal("refused the first")
	}
	if l.Allow("a") {
		t.Fatal("allowed a second immediately")
	}

	now = now.Add(time.Minute)
	if !l.Allow("a") {
		t.Error("a minute later it was still refused")
	}
}

func TestTheAllowanceDoesNotStockpile(t *testing.T) {
	// An hour of silence must not buy sixty at once, which is what a counter
	// without a ceiling would allow.
	now := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	l := NewLimiter(3, time.Minute, 24*time.Hour)
	l.now = func() time.Time { return now }

	l.Allow("a")
	now = now.Add(time.Hour)

	for i := 0; i < 3; i++ {
		if !l.Allow("a") {
			t.Fatalf("refused %d of the burst", i)
		}
	}
	if l.Allow("a") {
		t.Error("an hour of quiet bought more than the burst")
	}
}

func TestAddressesAreForgotten(t *testing.T) {
	// The addresses are the one identifying thing here. They live as long as
	// rate limiting needs them and no longer.
	now := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	l := NewLimiter(1, time.Minute, time.Hour)
	l.now = func() time.Time { return now }

	l.Allow("203.0.113.9")
	if len(l.buckets) != 1 {
		t.Fatalf("holding %d addresses", len(l.buckets))
	}

	now = now.Add(2 * time.Hour)
	l.Allow("198.51.100.4")

	if _, still := l.buckets["203.0.113.9"]; still {
		t.Error("an address that has gone quiet is still being held")
	}
}

// The common mistake, and the one that makes the whole limiter pointless: a
// proxy appends what it saw, so the rightmost entry is ours and everything to
// its left was supplied by the caller. Reading the leftmost lets anybody set
// their own identity and change it every request.
func TestClientAddressTakesTheEntryOurProxyWrote(t *testing.T) {
	cases := []struct {
		name      string
		forwarded string
		remote    string
		want      string
	}{
		{"one proxy", "203.0.113.7", "10.0.0.1:1234", "203.0.113.7"},
		{"a spoofed prefix", "1.2.3.4, 203.0.113.7", "10.0.0.1:1234", "203.0.113.7"},
		{"spacing", "1.2.3.4,   203.0.113.7  ", "10.0.0.1:1234", "203.0.113.7"},
		{"no header", "", "203.0.113.7:9999", "203.0.113.7"},
		{"an empty header", "", "203.0.113.7:9999", "203.0.113.7"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodPost, "/v1/reports", nil)
			r.RemoteAddr = c.remote
			if c.forwarded != "" {
				r.Header.Set("X-Forwarded-For", c.forwarded)
			}

			if got := ClientAddress(r); got != c.want {
				t.Errorf("got %q, wanted %q", got, c.want)
			}
		})
	}
}

func TestOneClientCannotSpendAnotheresAllowance(t *testing.T) {
	l := NewLimiter(1, time.Hour, time.Hour)

	if !l.Allow("a") {
		t.Fatal("refused a")
	}
	if !l.Allow("b") {
		t.Error("b was refused because a had spent its own allowance")
	}
}
