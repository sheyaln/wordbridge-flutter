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

  /// Whether somebody may choose it.
  ///
  /// A speaker the model carries is a fact about the model; a voice offered to
  /// a person is a judgement about whether it is good enough to speak with. The
  /// two part company, so they are separate fields — the table below stays a
  /// true account of what `sid` addresses, and this says which of them a
  /// caregiver is shown.
  bool offered,
});

/// The eleven, in speaker-id order.
///
/// The names are the model's own, tidied for reading: `af_bella` is an
/// American female voice and is shown as "Bella". `af` has no name of its own
/// in the release, so it is named for what it is.
///
/// **The four British speakers are not offered (§4.80.)** They are audibly
/// worse than the American seven — enough that a person given one would be
/// judged on the voice rather than on what they said, which is the failure
/// this whole feature exists to avoid. Held here rather than deleted because
/// `sid` is an index into the model's own speaker table and this list is that
/// table; removing rows would make the remaining ids a puzzle.
///
/// **There is a plausible cause and it is untested.** Kokoro phonemises
/// through espeak-ng, and sherpa's `lang` on the Kokoro config is left empty,
/// which means every voice is fed `en-us` phonemes. A British speaker
/// embedding driven by American phonemes is exactly the mismatch that would
/// produce this. Setting `lang` per voice is a small change and nobody has
/// listened to the result; until somebody has, these stay off rather than
/// shipping on a guess about how a person will sound.
const kokoroVoices = <NeuralVoice>[
  (
    id: 'af',
    name: 'Default',
    accent: 'American',
    sid: 0,
    gender: 'female',
    offered: true,
  ),
  (
    id: 'af_bella',
    name: 'Bella',
    accent: 'American',
    sid: 1,
    gender: 'female',
    offered: true,
  ),
  (
    id: 'af_nicole',
    name: 'Nicole',
    accent: 'American, softer',
    sid: 2,
    gender: 'female',
    offered: true,
  ),
  (
    id: 'af_sarah',
    name: 'Sarah',
    accent: 'American',
    sid: 3,
    gender: 'female',
    offered: true,
  ),
  (
    id: 'af_sky',
    name: 'Sky',
    accent: 'American',
    sid: 4,
    gender: 'female',
    offered: true,
  ),
  (
    id: 'am_adam',
    name: 'Adam',
    accent: 'American',
    sid: 5,
    gender: 'male',
    offered: true,
  ),
  (
    id: 'am_michael',
    name: 'Michael',
    accent: 'American',
    sid: 6,
    gender: 'male',
    offered: true,
  ),
  (
    id: 'bf_emma',
    name: 'Emma',
    accent: 'British',
    sid: 7,
    gender: 'female',
    offered: false,
  ),
  (
    id: 'bf_isabella',
    name: 'Isabella',
    accent: 'British',
    sid: 8,
    gender: 'female',
    offered: false,
  ),
  (
    id: 'bm_george',
    name: 'George',
    accent: 'British',
    sid: 9,
    gender: 'male',
    offered: false,
  ),
  (
    id: 'bm_lewis',
    name: 'Lewis',
    accent: 'British',
    sid: 10,
    gender: 'male',
    offered: false,
  ),
];

/// The ones a caregiver is shown, in the order they are shown.
///
/// Derived rather than written out again, so a voice can be withdrawn or
/// restored by changing one field and nothing can disagree about which list is
/// the menu.
final offeredNeuralVoices = [
  for (final voice in kokoroVoices)
    if (voice.offered) voice,
];

/// The voice a profile gets before anybody chooses one.
const defaultNeuralVoiceId = 'af_bella';

/// The voice with this id, or the default where it is not one that is offered.
///
/// Never null. A stored id that a model update stopped carrying must not leave
/// a profile with no voice at all, and the default is a voice.
///
/// **An id that is no longer offered resolves to the default too.** A profile
/// set to a voice that has since been withdrawn is a person still speaking in
/// it, with no row on the picker to change it from — so it is moved, and the
/// pack rebakes in the voice they can actually be given.
NeuralVoice neuralVoiceById(String? id) {
  for (final voice in offeredNeuralVoices) {
    if (voice.id == id) return voice;
  }
  for (final voice in offeredNeuralVoices) {
    if (voice.id == defaultNeuralVoiceId) return voice;
  }
  return offeredNeuralVoices.first;
}
