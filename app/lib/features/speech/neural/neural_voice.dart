/// The voices the downloaded model can speak in.
///
/// Kokoro v0.19 declares `n_speakers=11` in its own metadata and sherpa
/// validates the voices file against that number rather than against its size,
/// so this list is eleven entries long and cannot be lengthened by editing it.
/// The order is the speaker id: `sid` 0 is the first row here.
///
/// Deliberately not an emotion list. Gate 3 measured Kokoro's prosody space
/// and found one axis, and that axis is pitch, so a `sad` or `stern` entry
/// would be the speed dial wearing a name it has not earned — ADR-0005, and
/// §5 non-negotiable 9. These are voices. Choosing one is choosing who the
/// person sounds like, which is the whole of what this model honestly offers.
typedef NeuralVoice = ({
  /// What the model calls it, and what the cache is keyed on. Never shown.
  String id,

  /// What the caregiver reads.
  String name,

  /// The accent, in the words somebody choosing a voice would use.
  String accent,

  /// Speaker id passed to `generate`. The index into this list.
  int sid,

  /// As the model's own card labels it, or null where it does not say.
  ///
  /// Same shape as the platform's voice list, so the picker can group these
  /// the way it already groups those.
  String? gender,
});

/// The eleven, in speaker-id order.
///
/// The names are the model's own, tidied for reading: `af_bella` is an
/// American female voice and is shown as "Bella". `af` has no name of its own
/// in the release, so it is named for what it is.
const kokoroVoices = <NeuralVoice>[
  (
    id: 'af',
    name: 'Default',
    accent: 'American',
    sid: 0,
    gender: 'female',
  ),
  (
    id: 'af_bella',
    name: 'Bella',
    accent: 'American',
    sid: 1,
    gender: 'female',
  ),
  (
    id: 'af_nicole',
    name: 'Nicole',
    accent: 'American, softer',
    sid: 2,
    gender: 'female',
  ),
  (
    id: 'af_sarah',
    name: 'Sarah',
    accent: 'American',
    sid: 3,
    gender: 'female',
  ),
  (id: 'af_sky', name: 'Sky', accent: 'American', sid: 4, gender: 'female'),
  (id: 'am_adam', name: 'Adam', accent: 'American', sid: 5, gender: 'male'),
  (
    id: 'am_michael',
    name: 'Michael',
    accent: 'American',
    sid: 6,
    gender: 'male',
  ),
  (id: 'bf_emma', name: 'Emma', accent: 'British', sid: 7, gender: 'female'),
  (
    id: 'bf_isabella',
    name: 'Isabella',
    accent: 'British',
    sid: 8,
    gender: 'female',
  ),
  (
    id: 'bm_george',
    name: 'George',
    accent: 'British',
    sid: 9,
    gender: 'male',
  ),
  (id: 'bm_lewis', name: 'Lewis', accent: 'British', sid: 10, gender: 'male'),
];

/// The voice a profile gets before anybody chooses one.
const defaultNeuralVoiceId = 'af_bella';

/// The voice with this id, or the default where it is not one of the eleven.
///
/// Never null. A stored id that a model update stopped carrying must not leave
/// a profile with no voice at all, and the default is a voice.
NeuralVoice neuralVoiceById(String? id) {
  for (final voice in kokoroVoices) {
    if (voice.id == id) return voice;
  }
  for (final voice in kokoroVoices) {
    if (voice.id == defaultNeuralVoiceId) return voice;
  }
  return kokoroVoices.first;
}
