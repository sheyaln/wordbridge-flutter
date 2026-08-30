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
/// A held `AVAudioEngine` rather than an `AVAudioPlayer` per clip. Measured on
/// the floor device: building a player from data and preparing it costs about
/// 117 ms before any sound, on every tap, which is the kind of number the
/// cache exists to avoid. A running engine with a player node scheduled into
/// it starts in single-digit milliseconds because everything expensive has
/// already happened.
///
/// Newest wins, matching every other speech path in the app: a user tapping
/// quickly wants the word under their finger, not a queue of the ones they
/// have moved on from.
class ClipAudio: NSObject {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var running = false

  /// Completes when the clip finishes, is replaced, or is stopped. Held so a
  /// superseded clip's caller is answered rather than left waiting for audio
  /// that will never arrive.
  private var pending: FlutterResult?

  /// Which clip is the current one. A buffer's completion handler fires on an
  /// audio thread after the node has been stopped, so it has to be able to
  /// tell "I finished" from "something newer replaced me".
  private var generation: Int = 0

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
        let pcm = arguments["pcm"] as? FlutterStandardTypedData,
        let sampleRate = arguments["sampleRate"] as? Int,
        let volume = arguments["volume"] as? Double
      else {
        result(FlutterError(code: "arguments", message: "play needs pcm bytes", details: nil))
        return
      }
      play(pcm.data, sampleRate: Double(sampleRate), volume: Float(volume), result: result)

    case "stop":
      finish(answering: true)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Brings the engine up once, at the format the model produces.
  ///
  /// The session itself is already configured for playback with the ringer
  /// switch ignored — flutter_tts does that at startup, and an AAC device that
  /// goes silent because somebody flicked a switch is a user who cannot speak.
  private func start(sampleRate: Double) throws {
    let format = AVAudioFormat(
      standardFormatWithSampleRate: sampleRate, channels: 1)!
    if running, engine.isRunning,
      node.outputFormat(forBus: 0).sampleRate == sampleRate {
      return
    }
    if running {
      engine.stop()
      engine.disconnectNodeOutput(node)
    } else {
      engine.attach(node)
    }
    engine.connect(node, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    running = true
  }

  private func play(
    _ pcm: Data, sampleRate: Double, volume: Float, result: @escaping FlutterResult
  ) {
    finish(answering: true)

    let frames = pcm.count / 2
    guard frames > 0 else {
      result(nil)
      return
    }

    do {
      try start(sampleRate: sampleRate)
    } catch {
      result(FlutterError(code: "play", message: "\(error)", details: nil))
      return
    }

    let format = AVAudioFormat(
      standardFormatWithSampleRate: sampleRate, channels: 1)!
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else {
      result(nil)
      return
    }
    buffer.frameLength = AVAudioFrameCount(frames)

    // Signed 16-bit little-endian to the float format the engine mixes in.
    pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      let out = buffer.floatChannelData![0]
      for i in 0..<frames {
        out[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
      }
    }

    generation += 1
    let mine = generation
    pending = result
    node.volume = volume

    node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, self.generation == mine else { return }
        self.answer()
      }
    }
    node.play()
  }

  /// Stops whatever is playing and answers whoever was waiting on it.
  private func finish(answering: Bool) {
    generation += 1
    if running {
      node.stop()
    }
    if answering { answer() }
  }

  private func answer() {
    guard let pending = pending else { return }
    self.pending = nil
    pending(nil)
  }
}
