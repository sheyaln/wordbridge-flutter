import AVFoundation
import Flutter

/// Plays a buffer this app synthesised, now.
///
/// The neural voice produces samples rather than calling into a platform
/// synthesiser, so something has to play them. `audioplayers` cannot: its
/// darwin side answers `setSourceBytes is not currently implemented on iOS`,
/// which leaves writing a file between a tap and a word — the cost §4.4
/// rejected this whole route for.
///
/// Newest wins, matching every other speech path in the app: a user tapping
/// quickly wants the word under their finger, not a queue of the ones they
/// have moved on from.
class ClipAudio: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?

  /// Completes when the clip finishes, is replaced, or is stopped. Held so a
  /// superseded clip's caller is answered rather than left waiting for audio
  /// that will never arrive.
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.wordbridge/clip_audio",
      binaryMessenger: registrar.messenger())
    let instance = ClipAudio()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      guard let arguments = call.arguments as? [String: Any],
        let wav = arguments["wav"] as? FlutterStandardTypedData,
        let volume = arguments["volume"] as? Double
      else {
        result(FlutterError(code: "arguments", message: "play needs wav bytes", details: nil))
        return
      }
      play(wav.data, volume: Float(volume), result: result)

    case "stop":
      finish()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func play(_ wav: Data, volume: Float, result: @escaping FlutterResult) {
    finish()
    do {
      // The session is already configured for playback with the ringer switch
      // ignored — flutter_tts does it at startup, and an AAC device that goes
      // silent because somebody flicked a switch is a user who cannot speak.
      let player = try AVAudioPlayer(data: wav)
      player.delegate = self
      player.volume = volume
      player.prepareToPlay()
      self.player = player
      self.pending = result
      if !player.play() {
        finish()
        result(nil)
      }
    } catch {
      result(FlutterError(code: "play", message: "\(error)", details: nil))
    }
  }

  /// Ends whatever is playing and answers whoever was waiting on it.
  private func finish() {
    player?.stop()
    player = nil
    if let pending = pending {
      self.pending = nil
      pending(nil)
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard player === self.player else { return }
    self.player = nil
    if let pending = pending {
      self.pending = nil
      pending(nil)
    }
  }
}
