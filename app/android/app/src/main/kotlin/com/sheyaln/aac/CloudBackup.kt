package com.sheyaln.aac

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Copies of the board in a folder the caregiver picked, in their own account.
 *
 * The folder is chosen once through the system document picker, so it can be
 * their Google Drive, their OneDrive, or the tablet's own storage — whichever
 * providers that device has. What comes back is a permission scoped to that one
 * folder, held across reboots, and every copy afterwards is automatic.
 *
 * **This app holds no Google credential and never asks for one.** The rejected
 * alternative was Drive's `appDataFolder` through the Drive REST API, which is
 * the closer match to the iOS side's hidden container: it needs an OAuth client
 * tied to the upload key and Google's verification of the `drive.appdata`
 * sensitive scope. Both are infrastructure on the developer's side of the line,
 * for a feature whose whole claim is that there is no developer side.
 *
 * Android's own Auto Backup was rejected for the reason the iCloud device
 * backup was: silent, capped at 25 MB, impossible to list or date, and it comes
 * back only on a reinstall. A backup a caregiver cannot verify is the failure
 * this feature exists against, not a cheaper version of the fix.
 *
 * Every call runs off the main thread. A copy of a board is megabytes over a
 * content provider that may be a network away, and a blocked main thread here
 * is a nonspeaking person holding a frozen board.
 */
class CloudBackup(private val activity: Activity, messenger: BinaryMessenger) {
  private val channel = MethodChannel(messenger, "org.wordbridge/cloud_backup")
  private val work = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())

  /** The picker this is waiting on, or null. Only one can be open at a time. */
  private var pending: MethodChannel.Result? = null

  init {
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        // Answered here rather than on the worker: it opens a picker in front
        // of whoever is holding the tablet, so it belongs on the thread that
        // owns the screen.
        "connect" -> connect(call, result)
        else ->
          work.execute {
            try {
              val value =
                when (call.method) {
                  "place" -> where()
                  "list" -> list()
                  "upload" ->
                    upload(call.argument<String>("path")!!, call.argument<String>("name")!!)
                  "download" -> {
                    download(call.argument<String>("id")!!, call.argument<String>("path")!!)
                    null
                  }
                  "delete" -> {
                    delete(call.argument<String>("id")!!)
                    null
                  }
                  else -> {
                    main.post { result.notImplemented() }
                    return@execute
                  }
                }
              main.post { result.success(value) }
            } catch (e: Refusal) {
              main.post { result.error(e.code, e.detail, null) }
            } catch (e: Exception) {
              main.post { result.error("failed", e.toString(), null) }
            }
          }
      }
    }
  }

  /**
   * A reason the Dart side turns into a sentence.
   *
   * The strings here never reach a caregiver — `refusalFor` in
   * cloud_destination.dart owns the wording, so that a message written by a
   * content provider cannot become the app's own copy.
   */
  private class Refusal(val code: String, val detail: String) : Exception(detail)

  private fun preferences() =
    activity.getSharedPreferences("org.wordbridge.cloud_backup", Context.MODE_PRIVATE)

  /**
   * The chosen folder, or null where there is not one this app may still write
   * to.
   *
   * The permission is checked rather than assumed. A caregiver can revoke it
   * from system settings, and a stored URI that no longer grants anything would
   * otherwise fail on every copy with an error nobody can act on.
   */
  private fun folder(): Uri? {
    val stored = preferences().getString(TREE, null) ?: return null
    val tree = Uri.parse(stored)

    val held =
      activity.contentResolver.persistedUriPermissions.any {
        it.uri == tree && it.isWritePermission
      }
    return if (held) tree else null
  }

  private fun tree(): Uri = folder() ?: throw Refusal("folder", "No folder chosen.")

  /**
   * Where copies go, and whether one would arrive.
   *
   * There is one place on this tablet, so the answer never changes. It is sent
   * anyway because the Dart side asks both platforms the same question — an
   * iPad has two answers, and the shape of the reply is not the place to
   * encode which platform this is.
   *
   * No name is offered. `cloudLabel` already knows what a folder chosen on
   * Android is usually called, and a display name pulled from a content
   * provider would be the provider's copy rather than the app's.
   */
  private fun where(): Map<String, Any> =
    mapOf("place" to "folder", "reachable" to (folder() != null))

  /**
   * Sets up whatever is needed, opening the picker only where one is due.
   *
   * A folder already held is not asked for again. `pick` overrides that, which
   * is how somebody moves to a different provider and the only way back from a
   * folder whose permission the system has dropped.
   */
  private fun connect(call: MethodCall, result: MethodChannel.Result) {
    val pick = call.argument<Boolean>("pick") ?: false
    if (!pick && folder() != null) {
      result.success(where())
      return
    }
    choose(result)
  }

  private fun choose(result: MethodChannel.Result) {
    if (pending != null) {
      result.error("failed", "A folder is already being chosen.", null)
      return
    }
    pending = result

    val intent =
      Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        .addFlags(
          Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
    activity.startActivityForResult(intent, REQUEST)
  }

  /**
   * The picker's answer. Returns whether it was this plugin's.
   *
   * A dismissed picker answers with the state as it stands rather than
   * failing. Somebody who changed their mind has not hit an error, and the Dart
   * side leaves the switch on with a line saying no folder has been chosen
   * yet.
   */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST) return false

    val result = pending ?: return true
    pending = null

    val tree = data?.data
    if (resultCode != Activity.RESULT_OK || tree == null) {
      result.success(where())
      return true
    }

    // Persisted, or the grant dies with this process and the next automatic
    // copy is a picker in somebody's face.
    activity.contentResolver.takePersistableUriPermission(
      tree,
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    )
    preferences().edit().putString(TREE, tree.toString()).apply()

    result.success(where())
    return true
  }

  /** What the folder holds. The Dart side decides which of them are snapshots. */
  private fun list(): List<Map<String, Any>> {
    val tree = tree()
    val children =
      DocumentsContract.buildChildDocumentsUriUsingTree(
        tree,
        DocumentsContract.getTreeDocumentId(tree)
      )

    val found = mutableListOf<Map<String, Any>>()
    activity.contentResolver
      .query(
        children,
        arrayOf(
          DocumentsContract.Document.COLUMN_DOCUMENT_ID,
          DocumentsContract.Document.COLUMN_DISPLAY_NAME,
          DocumentsContract.Document.COLUMN_SIZE
        ),
        null,
        null,
        null
      )
      ?.use { cursor ->
        while (cursor.moveToNext()) {
          found.add(
            mapOf(
              "id" to cursor.getString(0),
              "name" to cursor.getString(1),
              "bytes" to cursor.getLong(2).toInt()
            )
          )
        }
      }
    return found
  }

  private fun documentUri(id: String): Uri =
    DocumentsContract.buildDocumentUriUsingTree(tree(), id)

  private fun upload(path: String, name: String): Map<String, Any> {
    val tree = tree()
    val parent =
      DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    // Replaced rather than added beside. Providers happily create a second
    // "wordbridge-….db (1)", and two files claiming one instant is a list of
    // dates a caregiver cannot choose between.
    list().firstOrNull { it["name"] == name }?.let { delete(it["id"] as String) }

    val created =
      DocumentsContract.createDocument(
        activity.contentResolver,
        parent,
        "application/octet-stream",
        name
      )
        ?: throw Refusal("failed", "The folder would not take a new file.")

    val source = java.io.File(path)
    try {
      activity.contentResolver.openOutputStream(created, "wt").use { out ->
        if (out == null) throw Refusal("failed", "The folder would not open for writing.")
        source.inputStream().use { it.copyTo(out) }
      }
    } catch (e: Exception) {
      // Any failure, not only an IO one. Half a database is worse than none:
      // it would be listed, offered and believed. The Dart side checks the
      // length it gets back on the way in as well, but a file that a failed
      // write left behind should not survive the failure that made it.
      DocumentsContract.deleteDocument(activity.contentResolver, created)
      if (e is Refusal) throw e
      throw Refusal(if (outOfSpace(e)) "space" else "offline", e.toString())
    }

    // The name the provider actually used. Some rename on create, and a
    // snapshot's date lives in its name — so the caller is told what it really
    // ended up being called rather than what it asked for.
    val id = DocumentsContract.getDocumentId(created)
    val written = list().firstOrNull { it["id"] == id }

    return mapOf(
      "id" to id,
      "name" to (written?.get("name") ?: name),
      "bytes" to ((written?.get("bytes") as? Int) ?: source.length().toInt())
    )
  }

  private fun download(id: String, path: String) {
    val destination = java.io.File(path)
    try {
      activity.contentResolver.openInputStream(documentUri(id)).use { input ->
        if (input == null) throw Refusal("missing", "No such backup in the folder.")
        destination.outputStream().use { input.copyTo(it) }
      }
    } catch (e: java.io.FileNotFoundException) {
      throw Refusal("missing", e.toString())
    } catch (e: java.io.IOException) {
      destination.delete()
      throw Refusal("offline", e.toString())
    }
  }

  private fun delete(id: String) {
    DocumentsContract.deleteDocument(activity.contentResolver, documentUri(id))
  }

  private fun outOfSpace(e: Exception): Boolean =
    e.message?.contains("space", ignoreCase = true) == true

  private companion object {
    const val TREE = "tree"
    const val REQUEST = 0x8AC4
  }
}
