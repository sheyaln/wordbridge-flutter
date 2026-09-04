package com.sheyaln.aac

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  private var cloudBackup: CloudBackup? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    ClipAudio(flutterEngine.dartExecutor.binaryMessenger)
    DeviceFacts(flutterEngine.dartExecutor.binaryMessenger)
    cloudBackup = CloudBackup(this, flutterEngine.dartExecutor.binaryMessenger)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    // The folder picker's answer. Offered here first because the plugin owns
    // the request code and needs the result to complete a call that is still
    // waiting on the Dart side.
    if (cloudBackup?.onActivityResult(requestCode, resultCode, data) == true) return
    super.onActivityResult(requestCode, resultCode, data)
  }
}
