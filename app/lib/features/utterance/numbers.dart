/// Saying a number that has no key of its own (§4.74).
///
/// The numbers board stops at ten, and the comment beside those keys says why:
/// ten keys is one row and one movement wide, and a row that scans in one
/// sweep is worth more than a row that holds more numbers. That is a good
/// argument about **keys** and it was silently taken as an argument about
/// **numbers** — so a person could not say their age past ten, a date, a price,
/// a bus number or a room number.
///
/// Two presses already make the digits of any number somebody wants. What was
/// missing is the app agreeing that `1` then `2` is twelve.
library;

/// Whether this is a numeral key's label — digits and nothing else.
///
/// The label, not the spoken word: the keys are labelled `1`..`10` and speak
/// `one`..`ten`, and joining works on what is written rather than on what is
/// said, because `1` and `2` concatenate and `one` and `two` do not.
bool isNumeral(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  for (final unit in trimmed.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return true;
}

/// How many digits may be joined into one number.
///
/// Four covers a year, a house number, a price in pence and every age anybody
/// has. Past that the joining is more likely to be somebody pressing keys than
/// somebody saying a number, and a five digit run should come apart into
/// separate numbers rather than becoming one nobody meant.
const maxJoinedDigits = 4;

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

/// A number as the words a voice says, for 0 to 9999.
///
/// Spoken rather than read out digit by digit, because "twelve" is the point.
/// A board that answered `1` `2` with "one two" is the behavior this exists to
/// offer as a choice, not the behavior to fall back to.
String numberInWords(int value) {
  if (value < 0 || value > 9999) return '$value';
  if (value < 20) return _ones[value];

  if (value < 100) {
    final tens = _tens[value ~/ 10];
    final ones = value % 10;
    return ones == 0 ? tens : '$tens ${_ones[ones]}';
  }

  if (value < 1000) {
    final hundreds = '${_ones[value ~/ 100]} hundred';
    final rest = value % 100;
    return rest == 0 ? hundreds : '$hundreds ${numberInWords(rest)}';
  }

  final thousands = '${numberInWords(value ~/ 1000)} thousand';
  final rest = value % 1000;
  return rest == 0 ? thousands : '$thousands ${numberInWords(rest)}';
}
