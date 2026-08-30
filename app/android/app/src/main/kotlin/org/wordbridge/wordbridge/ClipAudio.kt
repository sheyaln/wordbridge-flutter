package org.wordbridge.wordbridge

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
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
        val wav = call.argument<ByteArray>("wav")
        val volume = call.argument<Double>("volume") ?: 1.0
        if (wav == null) {
          result.error("arguments", "play needs wav bytes", null)
          return
        }
        play(wav, volume.toFloat(), result)
      }
      "stop" -> {
        finish()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun play(wav: ByteArray, volume: Float, result: MethodChannel.Result) {
    finish()

    // The Dart side sends a WAV so both platforms take the same bytes; the
    // header is 44 bytes and AudioTrack wants the samples on their own.
    val header = 44
    if (wav.size <= header) {
      result.success(null)
      return
    }
    val sampleRate =
      ByteBuffer.wrap(wav, 24, 4).order(ByteOrder.LITTLE_ENDIAN).int

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

    val samples = wav.size - header
    val playing =
      AudioTrack(
        attributes,
        format,
        maxOf(samples, AudioTrack.getMinBufferSize(
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
        playing.write(wav, header, samples)
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
