package main

import (
	"encoding/json"
	"errors"
	"fmt"
)

// MaxBody is the largest report accepted, matching reportSizeLimit in the app
// so that a report the app would refuse to send is also one this would refuse
// to take. A caregiver meets the refusal on the screen either way.
const MaxBody = 64 * 1024

// Schema versions this build understands.
//
// An unknown one is refused rather than guessed at, and the app turns that
// refusal into "update the app". Guessing would mean silently filing a report
// whose shape we do not know, which is worse than not taking it.
var knownSchemas = map[int]bool{1: true}

var validKinds = map[string]bool{"crash": true, "bug": true, "idea": true}

// Report is only the part of the document this service reasons about.
//
// Deliberately not the whole payload. The app owns the wire format and will
// add fields to it; a server that unmarshalled into an exhaustive struct would
// have to be redeployed in step with the app, which is the coupling the schema
// number exists to avoid. Everything is kept verbatim in Raw and written to
// storage as it arrived.
type Report struct {
	Schema int    `json:"schema"`
	Kind   string `json:"kind"`
	Note   string `json:"note"`

	App struct {
		Version string `json:"version"`
		Build   string `json:"build"`
	} `json:"app"`

	Device struct {
		Platform string `json:"platform"`
		OS       string `json:"os"`
		Model    string `json:"model"`
		Locale   string `json:"locale"`
	} `json:"device"`

	Board struct {
		Rows   int    `json:"rows"`
		Cols   int    `json:"cols"`
		Level  int    `json:"level"`
		Engine string `json:"engine"`
	} `json:"board"`

	HasDetail bool `json:"-"`
	HasVoice  bool `json:"-"`

	// Raw is exactly the bytes that arrived. What gets stored, so a field this
	// build does not know about is not lost by passing through it.
	Raw json.RawMessage `json:"-"`
}

// ErrBadRequest marks a body this service will not take. Distinguished from a
// storage failure because the two mean opposite things to the app: one says
// "do not try this again", the other says "try again later".
var ErrBadRequest = errors.New("bad request")

func badRequest(format string, args ...any) error {
	return fmt.Errorf("%w: "+format, append([]any{ErrBadRequest}, args...)...)
}

// ParseReport validates a body far enough to know it is a report, and no
// further.
//
// The line it draws: refuse what cannot be filed, accept what can. A note that
// is empty is not this function's business — a caregiver who pressed send on
// an empty note has still told us something by pressing send.
func ParseReport(body []byte) (*Report, error) {
	if len(body) > MaxBody {
		return nil, badRequest("body is %d bytes, over the %d limit", len(body), MaxBody)
	}

	var probe map[string]json.RawMessage
	if err := json.Unmarshal(body, &probe); err != nil {
		return nil, badRequest("not a JSON object: %v", err)
	}

	var r Report
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, badRequest("fields are not the shape expected: %v", err)
	}

	if !knownSchemas[r.Schema] {
		return nil, badRequest("schema %d is not one this build knows", r.Schema)
	}
	if !validKinds[r.Kind] {
		return nil, badRequest("kind %q is not crash, bug or idea", r.Kind)
	}

	_, r.HasDetail = probe["detail"]
	_, r.HasVoice = probe["voice"]
	r.Raw = append(json.RawMessage(nil), body...)

	return &r, nil
}
