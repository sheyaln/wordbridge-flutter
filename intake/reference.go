package main

import (
	"crypto/rand"
	"math/big"
	"strings"
)

// Alphabet for a reference. Crockford base32 without the letters that get
// misread when somebody copies one off a screen into an email: no I, L, O or
// U. A reference exists to be repeated by a human, so it is built out of
// characters a human can repeat.
const referenceAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const referenceLength = 6

// NewReference returns the string a caregiver can quote back.
//
// Not a UUID: a caregiver reading one off a tablet and typing it into an email
// will not manage thirty six characters, and a reference nobody can repeat is
// the same as no reference. Six of this alphabet is a billion possibilities,
// which is enough for a service expecting single digits a week — collisions
// are not being defended against here, guessing is.
func NewReference() (string, error) {
	var out strings.Builder
	out.WriteString("WB-")

	max := big.NewInt(int64(len(referenceAlphabet)))
	for i := 0; i < referenceLength; i++ {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		out.WriteByte(referenceAlphabet[n.Int64()])
	}
	return out.String(), nil
}
