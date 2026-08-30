package org.wordbridge.wordbridge

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Plays a buffer this app synthesised, now.
 *
 * The neural voice produces samples rather than calling a platform
 * synthesiser, so something has to play them, and it has to start immediately:
 * every tap on the board comes through here.
 *
 * Newest wins, matching every other speech path in the app.
 */
class ClipAudio(messenger: io.flutter.plugin.common.BinaryMessenger) {
  private val channel = MethodChannel(messenger, "org.wordbridge/clip_audio")
  private val main = Handler(Looper.getMainLooper())

  private var track: AudioTrack? = null

  /** Answered when the clip finishes, is replaced, or is stopped. */
  private var pending: MethodChannel.Result? = null

  init {
    channel.setMethodCallHandler { call, result -> handle(call, result) }
  }

  private fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "play" -> {
        val pcm = call.argument<ByteArray>("pcm")
        val sampleRate = call.argument<Int>("sampleRate") ?: 24000
        val volume = call.argument<Double>("volume") ?: 1.0
        if (pcm == null) {
          result.error("arguments", "play needs pcm bytes", null)
          return
        }
        play(pcm, sampleRate, volume.toFloat(), result)
      }
      "stop" -> {
        finish()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun play(
    pcm: ByteArray,
    sampleRate: Int,
    volume: Float,
    result: MethodChannel.Result,
  ) {
    finish()

    if (pcm.isEmpty()) {
      result.success(null)
      return
    }

    val attributes =
      AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    val format =
      AudioFormat.Builder()
        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
        .setSampleRate(sampleRate)
        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
        .build()

    val playing =
      AudioTrack(
        attributes,
        format,
        maxOf(pcm.size, AudioTrack.getMinBufferSize(
          sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)),
        AudioTrack.MODE_STREAM,
        AudioManager.AUDIO_SESSION_ID_GENERATE,
      )
    playing.setVolume(volume)
    track = playing
    pending = result
    playing.play()

    thread(name = "wordbridge-clip") {
      try {
        playing.write(pcm, 0, pcm.size)
        // Blocks until what was written has actually been heard, which is what
        // makes waiting on this the same promise as waiting on platform TTS.
        playing.write(ByteArray(0), 0, 0)
      } catch (_: IllegalStateException) {
        // Stopped from under us. The caller is answered below either way.
      }
      main.post { if (track === playing) finish() }
    }
  }

  private fun finish() {
    track?.let {
      try {
        it.pause()
        it.flush()
        it.stop()
      } catch (_: IllegalStateException) {
      }
      it.release()
    }
    track = null
    pending?.success(null)
    pending = null
  }
}
