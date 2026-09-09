import 'dart:async';

import '../../../db/database.dart';
import '../../profiles/profile_settings.dart';
import '../speech_engine.dart';
import 'bake_vocabulary.dart';
import 'neural_engine.dart';
import 'voice_model.dart';

/// Picks the bake up where the last session left it, without being asked.
///
/// §4.62. A bake was started by a button on a settings screen and by nothing
/// else, so a caregiver who switched the voice on, watched it work for a
/// minute and closed the app came back to a board that fell back on every word
/// it had not reached — with no reason on screen to think anything was wrong.
///
/// **The cheap question is asked first.** The pack is an open index, so
/// [NeuralSpeechEngine.needsBaking] answers "is there anything left" without
/// touching the model. Only where there is does this load 833 MB, which is
/// what keeps a fully baked profile as cheap to open as it is today.
Future<void> resumeBaking(
  SpeechEngine speech,
  ProfileSettings settings,
  WordbridgeDatabase db,
  String vocabularyId,
) async {
  if (speech is! NeuralSpeechEngine || !settings.neuralVoice) return;

  try {
    final words = await bakeVocabulary(db, vocabularyId);
    if (!speech.needsBaking(words)) return;

    // Before the bake, because it is the bake this governs: unmeasured, the
    // budget is the floor device's number, and every word on this tablet waits
    // three times longer than it needs to before the device voice takes over.
    if (!settings.synthesisBudgetMeasured) {
      final measured = await speech.measureBudget();
      if (measured != null) {
        await settings.setSynthesisBudget(measured);
        speech.budget = measured;
      }
    }

    final job = await speech.bakeJob();
    if (job == null) return;
    unawaited(job.start(words));
  } catch (_) {
    // A bake that will not start is a board speaking in the device voice,
    // which is §4.4 and is a product. A session that will not start is not.
  }
}

/// Starts the synthesis the moment a download already under way finishes.
///
/// **The gap this closes (§4.79).** Choosing the neural voice starts the
/// download, and the first thing anybody does next is go back to the board to
/// hear it. The settings screen is where the download was being watched, so
/// closing it left nothing listening: the model landed, the pack stayed empty,
/// and the board went on speaking in the device voice until the app was next
/// launched. Somebody who never closes the app never gets the voice.
///
/// Attaches to a download rather than starting one. A session must not put
/// hundreds of megabytes on a household's connection because a setting says
/// the voice is on — that is a decision somebody makes on the row that says
/// how big it is.
///
/// Returns null when there is nothing to wait for, so a caller can hold the
/// subscription without checking first.
StreamSubscription<ModelProgress>? bakeWhenInstalled(
  SpeechEngine speech,
  ProfileSettings settings,
  WordbridgeDatabase db,
  String vocabularyId,
) {
  if (speech is! NeuralSpeechEngine || !settings.neuralVoice) return null;

  final running = speech.models.runningInstall;
  if (running == null) return null;

  return running.listen((progress) {
    if (progress.phase != ModelPhase.installed) return;
    unawaited(resumeBaking(speech, settings, db, vocabularyId));
  });
}
