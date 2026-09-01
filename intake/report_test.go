package main

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

// A report from the app, as reportPayload builds it.
const realReport = `{
  "schema": 1,
  "kind": "bug",
  "app": {"version": "0.1.0", "build": "1"},
  "device": {"platform": "ios", "os": "Version 18.5", "model": "iPad11,1", "locale": "en_GB"},
  "board": {"rows": 7, "cols": 12, "level": 2, "engine": "neural"},
  "note": "the finder does not find cook"
}`

func TestParseReportTakesWhatTheAppSends(t *testing.T) {
	r, err := ParseReport([]byte(realReport))
	if err != nil {
		t.Fatalf("refused a real report: %v", err)
	}

	if r.Kind != "bug" {
		t.Errorf("kind = %q", r.Kind)
	}
	if r.Note != "the finder does not find cook" {
		t.Errorf("note = %q", r.Note)
	}
	if r.Device.Model != "iPad11,1" {
		t.Errorf("model = %q", r.Device.Model)
	}
	if r.Board.Rows != 7 || r.Board.Cols != 12 {
		t.Errorf("board = %dx%d", r.Board.Rows, r.Board.Cols)
	}
}

// The reason the server does not unmarshal into an exhaustive struct. The app
// owns the wire format and will add to it; a field this build has never heard
// of has to survive being passed through, or every app release needs a server
// release with it.
func TestParseReportKeepsFieldsItDoesNotKnow(t *testing.T) {
	body := `{"schema":1,"kind":"idea","note":"x","somethingNew":{"deep":[1,2]}}`

	r, err := ParseReport([]byte(body))
	if err != nil {
		t.Fatalf("refused: %v", err)
	}

	var stored map[string]json.RawMessage
	if err := json.Unmarshal(r.Raw, &stored); err != nil {
		t.Fatalf("what would be stored is not JSON: %v", err)
	}
	if _, ok := stored["somethingNew"]; !ok {
		t.Error("an unknown field was dropped on the way to storage")
	}
}

func TestParseReportNotesWhatCameWithIt(t *testing.T) {
	// Only whether they are there. The trace itself goes to the bucket and the
	// measurements are numbers; what the notification needs is a yes or no.
	with, err := ParseReport([]byte(`{"schema":1,"kind":"crash","note":"","detail":"Bad state","voice":{"voice_id":"af_heart"}}`))
	if err != nil {
		t.Fatalf("refused: %v", err)
	}
	if !with.HasDetail || !with.HasVoice {
		t.Errorf("detail=%v voice=%v, both should be true", with.HasDetail, with.HasVoice)
	}

	without, err := ParseReport([]byte(realReport))
	if err != nil {
		t.Fatalf("refused: %v", err)
	}
	if without.HasDetail || without.HasVoice {
		t.Errorf("detail=%v voice=%v, both should be false", without.HasDetail, without.HasVoice)
	}
}

func TestParseReportRefusals(t *testing.T) {
	cases := []struct {
		name string
		body string
		says string
	}{
		{"not JSON", `nonsense`, "not a JSON object"},
		{"an array, not an object", `[1,2,3]`, "not a JSON object"},
		{"a schema from the future", `{"schema":99,"kind":"bug"}`, "schema 99"},
		{"no schema at all", `{"kind":"bug"}`, "schema 0"},
		{"a kind nobody defined", `{"schema":1,"kind":"complaint"}`, "not crash, bug or idea"},
		{"no kind", `{"schema":1}`, "not crash, bug or idea"},
		{"fields of the wrong type", `{"schema":1,"kind":"bug","board":{"rows":"seven"}}`, "shape expected"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := ParseReport([]byte(c.body))
			if err == nil {
				t.Fatal("accepted")
			}
			if !errors.Is(err, ErrBadRequest) {
				t.Errorf("not marked as the caller's fault: %v", err)
			}
			if !strings.Contains(err.Error(), c.says) {
				t.Errorf("said %q, wanted something containing %q", err, c.says)
			}
		})
	}
}

func TestParseReportRefusesAnOversizeBody(t *testing.T) {
	// The same limit the app enforces before it sends, so a report refused
	// here is one a caregiver was already told about on the screen.
	body := `{"schema":1,"kind":"bug","note":"` + strings.Repeat("x", MaxBody) + `"}`

	if _, err := ParseReport([]byte(body)); err == nil {
		t.Fatal("accepted a body over the limit")
	} else if !strings.Contains(err.Error(), "over the") {
		t.Errorf("said %q", err)
	}
}

// An empty note is not a refusal. Somebody who pressed send on an empty note
// has still told us something by pressing send, and refusing it would lose a
// crash report whose whole value is the trace attached to it.
func TestParseReportAcceptsAnEmptyNote(t *testing.T) {
	if _, err := ParseReport([]byte(`{"schema":1,"kind":"crash","note":""}`)); err != nil {
		t.Errorf("refused an empty note: %v", err)
	}
}
