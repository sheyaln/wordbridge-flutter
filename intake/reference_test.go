package main

import (
	"strings"
	"testing"
	"time"
)

func TestReferenceShape(t *testing.T) {
	r, err := NewReference()
	if err != nil {
		t.Fatal(err)
	}

	if !strings.HasPrefix(r, "WB-") {
		t.Errorf("%q has no prefix, so it does not look like a reference", r)
	}
	if len(r) != 3+referenceLength {
		t.Errorf("%q is %d characters", r, len(r))
	}
}

// A reference exists to be read off a tablet and typed into an email. Every
// character in it has to survive that, which is why the alphabet has no I, L,
// O or U in it.
func TestReferenceAvoidsCharactersPeopleMisread(t *testing.T) {
	for i := 0; i < 200; i++ {
		r, err := NewReference()
		if err != nil {
			t.Fatal(err)
		}
		if strings.ContainsAny(strings.TrimPrefix(r, "WB-"), "ILOU") {
			t.Fatalf("%q contains a character that gets misread", r)
		}
	}
}

func TestReferencesDiffer(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 500; i++ {
		r, err := NewReference()
		if err != nil {
			t.Fatal(err)
		}
		if seen[r] {
			t.Fatalf("%q came up twice in 500", r)
		}
		seen[r] = true
	}
}

func TestStorageKeyIsBrowsableAndFindable(t *testing.T) {
	// Dated first so a listing can be read by hand and a lifecycle rule can
	// expire a month; the reference last so the string a caregiver quotes is
	// the string that finds the file.
	at := time.Date(2026, 9, 1, 23, 30, 0, 0, time.UTC)

	if got, want := StorageKey(at, "crash", "WB-7QK2"), "2026/09/01/crash/WB-7QK2.json"; got != want {
		t.Errorf("got %q, wanted %q", got, want)
	}
}

func TestStorageKeyIsInUTC(t *testing.T) {
	// Otherwise the same report files under two different days depending on
	// where the container happened to be scheduled.
	somewhere := time.FixedZone("UTC+13", 13*60*60)
	at := time.Date(2026, 9, 2, 5, 0, 0, 0, somewhere) // 2026-09-01 16:00 UTC

	if got := StorageKey(at, "bug", "WB-1"); !strings.HasPrefix(got, "2026/09/01/") {
		t.Errorf("got %q, which used the local date", got)
	}
}
