package main

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Limiter is a per-address token bucket, held in memory and nowhere else.
//
// **The addresses are never written down.** They live in this map, they are
// dropped when they go quiet, and they die with the instance. An address is
// the one identifying thing this service handles, and rate limiting is the
// only reason it handles it at all — so it exists for exactly as long as that
// takes and no longer.
//
// In process on purpose. A shared store would be another thing to run and
// another place an address is written; what actually caps abuse here is the
// instance ceiling in the deployment, and this stops one client from filling
// what that allows.
type Limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket

	// Burst is how many a caller may send at once, Every is how fast the
	// allowance comes back.
	Burst int
	Every time.Duration

	// Idle is how long an unused bucket is kept before being forgotten.
	Idle time.Duration

	now func() time.Time
}

type bucket struct {
	tokens float64
	seen   time.Time
}

func NewLimiter(burst int, every, idle time.Duration) *Limiter {
	return &Limiter{
		buckets: map[string]*bucket{},
		Burst:   burst,
		Every:   every,
		Idle:    idle,
		now:     time.Now,
	}
}

// Allow reports whether this address may send one now, and spends a token if
// so.
func (l *Limiter) Allow(address string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.forgetIdle(now)

	b, ok := l.buckets[address]
	if !ok {
		b = &bucket{tokens: float64(l.Burst), seen: now}
		l.buckets[address] = b
	}

	b.tokens += now.Sub(b.seen).Seconds() / l.Every.Seconds()
	if b.tokens > float64(l.Burst) {
		b.tokens = float64(l.Burst)
	}
	b.seen = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// forgetIdle drops what has gone quiet. Called on every request rather than on
// a timer: the work is proportional to how many addresses are in flight, which
// at this volume is a handful, and a background goroutine would be a second
// thing to reason about for no gain.
func (l *Limiter) forgetIdle(now time.Time) {
	for address, b := range l.buckets {
		if now.Sub(b.seen) > l.Idle {
			delete(l.buckets, address)
		}
	}
}

// ClientAddress is who to rate limit, given a request behind a proxy.
//
// **The last entry of X-Forwarded-For, not the first.** A proxy appends the
// address it saw, so the rightmost entry is the one our proxy wrote and every
// entry to its left was supplied by the caller. Reading the leftmost — which
// is the common mistake — lets anybody set their own identity and walk around
// the limit by changing it on every request.
//
// Falls back to the connection's own address where there is no header, which
// is what happens running this locally.
func ClientAddress(r *http.Request) string {
	forwarded := r.Header.Get("X-Forwarded-For")
	if forwarded != "" {
		parts := strings.Split(forwarded, ",")
		last := strings.TrimSpace(parts[len(parts)-1])
		if last != "" {
			return last
		}
	}

	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
