import Foundation
import UIKit
import UniformTypeIdentifiers

/// Copies of the board in a folder the caregiver picked, in their own account.
///
/// The system picker in folder mode reaches every File Provider extension
/// installed on the device — iCloud Drive, Google Drive, Dropbox, OneDrive, the
/// tablet's own storage. What comes back is one folder and a bookmark to it,
/// and nothing else on the device is readable through it. It is the same act an
/// Android tablet has had from the start, and it is here so that a family whose
/// files live in Drive do not have to keep a second copy in iCloud to be backed
/// up.
///
/// **This app holds no Google credential and never asks for one.** The rejected
/// alternative was Drive's REST API with OAuth: it needs a client tied to the
/// signing key and Google's verification of a sensitive scope, both of which are
/// infrastructure on the developer's side of the line — for a feature whose
/// whole claim is that there is no developer side. The picker needs no
/// entitlement, no key and no account of ours, which is also why this place
/// works on a build where the iCloud container is not provisioned.
///
/// The bookmark is kept even while copies are going to the container instead, so
/// that switching back to a folder somebody already chose does not put a picker
/// in their face again.
final class CloudFolder: NSObject, CloudStore {
  private static let bookmarkKey = "org.wordbridge.cloud_backup.folder"
  private static let labelKey = "org.wordbridge.cloud_backup.folderName"

  /// The picker this is waiting on, or nil. Only one can be open at a time.
  private var pending: (() -> Void)?

  /// What the folder was called when it was picked.
  ///
  /// Remembered rather than derived on demand, so that a folder which has since
  /// gone can still be named in the sentence about its going. "Wordbridge can
  /// no longer reach the backup folder in Google Drive" is something a caregiver
  /// can act on; the same sentence with a blank in it is not.
  var label: String? { UserDefaults.standard.string(forKey: Self.labelKey) }

  var reachable: Bool { (try? folder()) != nil }

  /// The picked folder, resolved from its bookmark.
  ///
  /// `folder` and `gone` are kept apart because they are different events with
  /// different fixes: nobody has chosen one yet, against one that was chosen
  /// and has since been uninstalled, revoked or deleted.
  private func folder() throws -> URL {
    guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
      throw CloudRefusal(code: "folder", detail: "No folder chosen.")
    }

    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
    else {
      throw CloudRefusal(code: "gone", detail: "The bookmark would not resolve.")
    }

    // Rewritten in place rather than refused. A provider that updated, or a
    // folder somebody moved, produces a stale bookmark that still resolves —
    // throwing it away there would send somebody back to the picker for a
    // folder that is perfectly fine.
    if stale, url.startAccessingSecurityScopedResource() {
      defer { url.stopAccessingSecurityScopedResource() }
      if let fresh = try? url.bookmarkData() {
        UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
      }
    }
    return url
  }

  /// Runs `body` with the folder open.
  ///
  /// Every read and write has to sit inside the security scope. Outside it the
  /// URL is a path this app has no permission for, and the failure is a bare
  /// "no such file" that says nothing about why.
  private func inside<T>(_ body: (URL) throws -> T) throws -> T {
    let url = try folder()
    guard url.startAccessingSecurityScopedResource() else {
      throw CloudRefusal(code: "gone", detail: "The folder would not open.")
    }
    defer { url.stopAccessingSecurityScopedResource() }
    return try body(url)
  }

  /// What the folder holds. The Dart side decides which of them are snapshots.
  func list() throws -> [[String: Any]] {
    try inside { folder in
      let keys: [URLResourceKey] = [.nameKey, .totalFileSizeKey, .fileSizeKey]
      var found: [[String: Any]] = []
      var coordinationError: NSError?

      NSFileCoordinator().coordinate(
        readingItemAt: folder, options: [], error: &coordinationError
      ) { readable in
        let entries =
          (try? FileManager.default.contentsOfDirectory(
            at: readable,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])) ?? []

        found = entries.compactMap { url in
          let values = try? url.resourceValues(forKeys: Set(keys))
          guard let bytes = values?.fileSize ?? values?.totalFileSize else { return nil }
          return ["id": url.lastPathComponent, "name": url.lastPathComponent, "bytes": bytes]
        }
      }

      if let error = coordinationError {
        throw CloudRefusal(code: "offline", detail: "\(error)")
      }
      return found
    }
  }

  func upload(path: String, name: String) throws -> [String: Any] {
    let source = URL(fileURLWithPath: path)

    return try inside { folder in
      let destination = folder.appendingPathComponent(name)
      var thrown: Error?
      var coordinationError: NSError?

      NSFileCoordinator().coordinate(
        writingItemAt: destination, options: .forReplacing, error: &coordinationError
      ) { target in
        do {
          // Replaced rather than added beside. A provider handed a name it
          // already has will happily file a second "wordbridge-… (1).db", and
          // two files claiming one instant is a list of dates a caregiver
          // cannot choose between.
          if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
          }
          try FileManager.default.copyItem(at: source, to: target)
        } catch let error as NSError where error.code == NSFileWriteOutOfSpaceError {
          thrown = CloudRefusal(code: "space", detail: "No room in the folder.")
        } catch {
          // Half a database is worse than none: it would be listed, offered and
          // believed. The Dart side opens what it fetches back as well, but a
          // file a failed write left behind should not survive the failure that
          // made it.
          try? FileManager.default.removeItem(at: target)
          thrown = error
        }
      }

      if let refusal = thrown as? CloudRefusal { throw refusal }
      if let error = thrown ?? coordinationError {
        throw CloudRefusal(code: "offline", detail: "\(error)")
      }

      let bytes =
        (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        ?? (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int)
        ?? 0

      // The name the provider actually filed it under. Some rename on create,
      // and a snapshot's date lives in its name — so the caller is told what it
      // really ended up being called rather than what it asked for.
      let filed =
        (try? destination.resourceValues(forKeys: [.nameKey]).name) ?? name

      return ["id": filed, "name": filed, "bytes": bytes]
    }
  }

  /// Fetches one back, bringing it down from the provider first.
  ///
  /// A file the device has never opened is a placeholder until something asks
  /// for it, and copying a placeholder produces something that looks like a
  /// backup and is not one. The coordinated read is what waits for the real
  /// bytes; the Dart side opens whatever arrives anyway.
  func download(id: String, to path: String) throws {
    try inside { folder in
      let source = folder.appendingPathComponent(id)
      guard FileManager.default.fileExists(atPath: source.path) else {
        throw CloudRefusal(code: "missing", detail: "No such backup in the folder.")
      }

      let destination = URL(fileURLWithPath: path)
      try? FileManager.default.startDownloadingUbiquitousItem(at: source)

      var thrown: Error?
      var coordinationError: NSError?

      NSFileCoordinator().coordinate(
        readingItemAt: source, options: [], error: &coordinationError
      ) { readable in
        do {
          if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
          }
          try FileManager.default.copyItem(at: readable, to: destination)
        } catch {
          try? FileManager.default.removeItem(at: destination)
          thrown = error
        }
      }

      if let error = thrown ?? coordinationError {
        throw CloudRefusal(code: "offline", detail: "\(error)")
      }
    }
  }

  func delete(id: String) throws {
    try inside { folder in
      let target = folder.appendingPathComponent(id)
      guard FileManager.default.fileExists(atPath: target.path) else { return }

      var thrown: Error?
      var coordinationError: NSError?

      NSFileCoordinator().coordinate(
        writingItemAt: target, options: .forDeleting, error: &coordinationError
      ) { url in
        do { try FileManager.default.removeItem(at: url) } catch { thrown = error }
      }

      if let error = thrown ?? coordinationError {
        throw CloudRefusal(code: "offline", detail: "\(error)")
      }
    }
  }

  /// Puts the system folder picker in front of whoever is holding the tablet.
  ///
  /// Folder mode rather than file mode, so that one grant covers every copy
  /// this app will ever write: the pick happens once and nothing after it
  /// interrupts anybody. `asCopy` is off because a copy of a folder is not the
  /// folder, and what is wanted is somewhere to keep writing to.
  ///
  /// A dismissed picker is not an error. Somebody who changed their mind has
  /// not hit a failure, and the Dart side leaves the answer where it was with a
  /// line saying no folder has been chosen.
  func pick(_ done: @escaping () -> Void) {
    guard pending == nil, let host = Self.topmost() else {
      done()
      return
    }
    pending = done

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    host.present(picker, animated: true)
  }

  /// What to call the folder in front of a caregiver.
  ///
  /// The provider's own name where the path gives one: since iOS 16 a File
  /// Provider extension's files sit under `Library/CloudStorage/<provider>-…`,
  /// and iCloud Drive's under `Mobile Documents`. Not spaced out or looked up
  /// in a table of brand names — a table would rot, and inventing a space turns
  /// OneDrive into two words. What matters is that a caregiver reads a place
  /// they recognize rather than the name of a folder they chose months ago.
  ///
  /// Falls back to the folder's own name, which is at least something they
  /// typed.
  private static func name(of url: URL) -> String {
    let parts = url.pathComponents

    if let at = parts.firstIndex(of: "CloudStorage"), at + 1 < parts.count {
      let account = parts[at + 1]
      return String(account.split(separator: "-").first ?? Substring(account))
    }
    if parts.contains("Mobile Documents") || parts.contains("com~apple~CloudDocs") {
      return "iCloud Drive"
    }

    let named = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
    return named.flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
  }

  private static func topmost() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first

    var top =
      scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
      ?? scene?.windows.first?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
  }

  private func finish() {
    let done = pending
    pending = nil
    done?()
  }
}

extension CloudFolder: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    defer { finish() }
    guard let url = urls.first else { return }

    // The bookmark is taken inside the scope the picker just granted. Taken
    // outside it, it resolves to a URL this app may not open, and the failure
    // does not show up until the first unattended copy weeks later.
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }

    guard let data = try? url.bookmarkData() else { return }
    UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    UserDefaults.standard.set(Self.name(of: url), forKey: Self.labelKey)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish()
  }
}
