import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/speech/neural/audio_clip.dart';
import 'package:wordbridge/features/speech/neural/synthesis_budget.dart';

/// Samples with [speech] of real signal in the middle and silence either side.
Float32List padded({
  required int leading,
  required int speech,
  required int trailing,
}) {
  final out = Float32List(leading + speech + trailing);
  for (var i = 0; i < speech; i++) {
    out[leading + i] = 0.5;
  }
  return out;
}

void main() {
  group('trimming what the model pads', () {
    // Measured over the whole shipped vocabulary: 999 s of audio becomes 701 s
    // once the padding is off, so 30% of the bytes are silence. `I` comes back
    // 660 ms long. Trimming is also what makes a tap speak rather than pause.
    test('leading and trailing silence come off', () {
      final trimmed = trimSilence(
        padded(leading: 4800, speech: 4800, trailing: 4800),
        24000,
      );
      expect(trimmed.length, lessThan(4800 + 4800 + 4800));
      expect(trimmed.length, greaterThanOrEqualTo(4800));
    });

    test('a margin is kept, so an onset is not bitten off', () {
      // A plosive starts with a near-silent closure. Cutting to the first
      // sample over the floor removes it.
      final trimmed = trimSilence(
        padded(leading: 4800, speech: 2400, trailing: 4800),
        24000,
      );
      // 20 ms either side at 24 kHz is 480 samples.
      expect(trimmed.length, 2400 + 480 + 480);
    });

    test('a clip that is silent throughout is left whole', () {
      // Something that produced no speech is a fault worth hearing as it is
      // rather than as an empty buffer.
      final silence = Float32List(2400);
      expect(trimSilence(silence, 24000).length, 2400);
    });

    test('speech that starts at the first sample is not cut', () {
      final trimmed = trimSilence(
        padded(leading: 0, speech: 2400, trailing: 2400),
        24000,
      );
      expect(trimmed.length, 2400 + 480);
    });
  });

  group('what gets stored', () {
    test('float samples become signed 16-bit little-endian', () {
      final pcm = toPcm16(Float32List.fromList([0, 1.0, -1.0]));
      expect(pcm.lengthInBytes, 6);
      final view = ByteData.sublistView(pcm);
      expect(view.getInt16(0, Endian.little), 0);
      expect(view.getInt16(2, Endian.little), 32767);
      expect(view.getInt16(4, Endian.little), -32767);
    });

    test('gain above one does not clip to fuzz', () {
      // Loudness above the device's own maximum is the thing platform speech
      // could never be asked for. A hard clip would make it distorted rather
      // than louder, and this is somebody's only voice.
      final loud = toPcm16(Float32List.fromList([0.8]), gain: 3.0);
      final value = ByteData.sublistView(loud).getInt16(0, Endian.little);
      expect(value, greaterThan((0.8 * 32767).round()));
      expect(value, lessThanOrEqualTo(32767));
    });

  });

  group('the timeout budget', () {
    test('both terms count', () {
      const budget = SynthesisBudget(
        base: Duration(milliseconds: 1000),
        perWord: Duration(milliseconds: 500),
      );
      expect(budget.forText('yes'), const Duration(milliseconds: 1500));
      expect(
        budget.forText('I want to go outside'),
        const Duration(milliseconds: 3500),
      );
    });

    test('the shipped default is about twice what the device measured', () {
      // A timeout that fires in ordinary use is a random voice generator, not
      // a safety net.
      expect(
        SynthesisBudget.shipped.base.inMilliseconds,
        greaterThan(SynthesisBudget.fitted.base.inMilliseconds * 1.8),
      );
      expect(
        SynthesisBudget.shipped.perWord.inMilliseconds,
        greaterThan(SynthesisBudget.fitted.perWord.inMilliseconds * 1.8),
      );
    });

    test('the shipped default clears the floor device by a real margin', () {
      // A five-word sentence measured 2100 ms on the iPad mini 5. The budget
      // has to be comfortably past that or the fallback is the normal case.
      final allowed = SynthesisBudget.shipped.forText('one two three four five');
      expect(allowed.inMilliseconds, greaterThan(2100));
    });

    test('a fit recovers a line it was given points from', () {
      // 747 ms + 262 ms/word, doubled: the fit is over measured points, so it
      // has to come back with the measured line and the margin on top.
      final fitted = SynthesisBudget.fit(
        shortWords: 1,
        shortTook: const Duration(milliseconds: 1009),
        longWords: 9,
        longTook: const Duration(milliseconds: 3105),
      );
      expect(fitted.base.inMilliseconds, closeTo(1494, 20));
      expect(fitted.perWord.inMilliseconds, closeTo(524, 10));
    });

    test('a measurement that comes out backwards is refused', () {
      // A device under load produces points that fit a negative slope, and a
      // budget derived from one of those is not a budget.
      expect(
        SynthesisBudget.fit(
          shortWords: 1,
          shortTook: const Duration(milliseconds: 3000),
          longWords: 9,
          longTook: const Duration(milliseconds: 500),
        ),
        SynthesisBudget.shipped,
      );
    });

    test('a measurement is clamped into something survivable', () {
      final wild = SynthesisBudget.fit(
        shortWords: 1,
        shortTook: const Duration(seconds: 30),
        longWords: 9,
        longTook: const Duration(seconds: 90),
      );
      expect(wild.base, lessThanOrEqualTo(SynthesisBudget.maxBase));
      expect(wild.perWord, lessThanOrEqualTo(SynthesisBudget.maxPerWord));
    });

    test('an empty utterance is not charged for a word', () {
      expect(SynthesisBudget.wordsIn('   '), 0);
      expect(SynthesisBudget.wordsIn('two words'), 2);
      expect(SynthesisBudget.wordsIn('  spaced   out  '), 2);
    });
  });
}
