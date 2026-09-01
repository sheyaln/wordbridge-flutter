package org.wordbridge.wordbridge

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The hardware identifier, and nothing else.
 *
 * A model class names a product line many people own, which is what makes it
 * safe to put in a report and useful in one: a neural voice timing means
 * nothing without knowing what it was measured on.
 *
 * Nothing here reads a serial, an advertising id, or anything a user typed.
 */
class DeviceFacts(messenger: BinaryMessenger) {
  private val channel = MethodChannel(messenger, "org.wordbridge/device_facts")

  init {
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
        else -> result.notImplemented()
      }
    }
  }
}
