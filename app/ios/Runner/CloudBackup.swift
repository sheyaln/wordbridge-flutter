import Flutter
import UIKit

/// Copies of the board in the family's own iCloud, and nowhere else.
///
/// The app's own ubiquity container, under `Documents`. Not the automatic
/// iCloud device backup that sweeps up an app's local documents folder: that
/// one cannot be triggered, listed, dated or verified, and it restores only
/// onto a wiped device. It is the mechanism behind *"we lost months of custom
/// button and phrase building because we thought the iCloud backup would
/// protect us"*, and a backups screen built on it could only ever say "probably".
///
/// Nothing here talks to a server of ours. The destination is the iCloud
/// account already signed in on the device, the entitlement names this app's
/// own container, and no credential of ours exists anywhere in this file.
///
/// Under `Documents` rather than the container root so the files are visible in
/// the Files app: a family moving to a tablet that is not signed in to the same
/// account has to be able to carry the file across by hand. It needs the
/// matching `NSUbiquitousContainers` key in Info.plist.
///
/// Every call runs off the main thread. iCloud coordination blocks, and a
/// blocked main thread on this app is a nonspeaking person staring at a frozen
/// board.
public class CloudBackup: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.wordbridge/cloud_backup",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CloudBackup(), channel: channel)
  }

  /// How long a fetch of one snapshot may wait for iCloud to materialize it.
  ///
  /// Bounded because the caller is a caregiver watching a spinner on the day
  /// their tablet stopped working. A refusal they can retry beats a wait with
  /// no end, and the local backups are still there either way.
  private static let downloadTimeout: TimeInterval = 120

  private let queue = DispatchQueue(label: "org.wordbridge.cloud-backup")

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    queue.async {
      do {
        let value: Any?
        switch call.method {
        // `connect` has nothing to ask for. The account is the device's, and
        // the container comes with it — the Android side is where somebody has
        // to name a folder.
        case "reachable", "connect":
          value = (try? self.documents()) != nil
        case "list":
          value = try self.list()
        case "upload":
          value = try self.upload(
            path: arguments["path"] as? String ?? "",
            name: arguments["name"] as? String ?? "")
        case "download":
          try self.download(
            id: arguments["id"] as? String ?? "",
            to: arguments["path"] as? String ?? "")
          value = nil
        case "delete":
          try self.delete(id: arguments["id"] as? String ?? "")
          value = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(value) }
      } catch let failure as Refusal {
        DispatchQueue.main.async {
          result(FlutterError(code: failure.code, message: failure.detail, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "failed", message: "\(error)", details: nil))
        }
      }
    }
  }

  /// A reason the Dart side turns into a sentence. The strings never reach a
  /// caregiver — see `refusalFor` in cloud_destination.dart, which owns the
  /// wording so that a platform message cannot become app copy.
  private struct Refusal: Error {
    let code: String
    let detail: String
  }

  /// The container's Documents folder, created if this is the first copy.
  ///
  /// Throws `signIn` rather than returning nil for the ordinary case: an iPad
  /// signed out of iCloud, which is a thing a caregiver can fix and the most
  /// common reason copies stop arriving.
  private func documents() throws -> URL {
    guard FileManager.default.ubiquityIdentityToken != nil,
      let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
    else {
      throw Refusal(code: "signIn", detail: "No iCloud account on this device.")
    }

    let documents = container.appendingPathComponent("Documents", isDirectory: true)
    if !FileManager.default.fileExists(atPath: documents.path) {
      try FileManager.default.createDirectory(
        at: documents, withIntermediateDirectories: true)
    }
    return documents
  }

  /// What the container holds. Names and sizes only; the Dart side decides
  /// which of them are snapshots.
  ///
  /// `fileSize` first, `totalFileSize` only as a fallback. The second can
  /// include metadata and is a displayable number rather than a byte count;
  /// nothing decides whether a restore is whole from it — see `_wholeDatabase`
  /// in cloud_backup.dart, which opens the file instead — but a caregiver
  /// choosing between dates is shown it, and 0 KB is a list nobody would
  /// trust.
  private func list() throws -> [[String: Any]] {
    let documents = try documents()
    let keys: [URLResourceKey] = [.nameKey, .totalFileSizeKey, .fileSizeKey]

    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: documents,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles])) ?? []

    return entries.compactMap { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      guard let bytes = values?.fileSize ?? values?.totalFileSize else { return nil }
      return ["id": url.lastPathComponent, "name": url.lastPathComponent, "bytes": bytes]
    }
  }

  private func upload(path: String, name: String) throws -> [String: Any] {
    let source = URL(fileURLWithPath: path)
    let destination = try documents().appendingPathComponent(name)

    try coordinate(writing: destination) { target in
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      do {
        try FileManager.default.copyItem(at: source, to: target)
      } catch let error as NSError where error.code == NSFileWriteOutOfSpaceError {
        throw Refusal(code: "space", detail: "No room in iCloud.")
      }
    }

    let bytes =
      (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize)
      ?? (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int)
      ?? 0

    return ["id": name, "name": name, "bytes": bytes]
  }

  /// Fetches one back, waiting for iCloud to bring it down first.
  ///
  /// A snapshot the device has never opened is a placeholder until something
  /// asks for it, and copying a placeholder produces a file that looks like a
  /// backup and is not one. So the download is started, waited for, and only
  /// then read — and the Dart side opens what it gets anyway, because a wait
  /// that timed out and a file that arrived whole are otherwise
  /// indistinguishable from there.
  private func download(id: String, to path: String) throws {
    let source = try documents().appendingPathComponent(id)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw Refusal(code: "missing", detail: "No such backup in iCloud.")
    }

    try FileManager.default.startDownloadingUbiquitousItem(at: source)

    let deadline = Date().addingTimeInterval(CloudBackup.downloadTimeout)
    while Date() < deadline {
      let status = try? source.resourceValues(
        forKeys: [.ubiquitousItemDownloadingStatusKey]
      ).ubiquitousItemDownloadingStatus

      if status == .current || status == nil { break }
      Thread.sleep(forTimeInterval: 0.25)
    }

    let destination = URL(fileURLWithPath: path)
    var readError: Error?
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
        readError = error
      }
    }

    if let error = coordinationError ?? readError {
      throw Refusal(code: "offline", detail: "\(error)")
    }
  }

  private func delete(id: String) throws {
    let target = try documents().appendingPathComponent(id)
    guard FileManager.default.fileExists(atPath: target.path) else { return }

    try coordinate(writing: target) { url in
      try FileManager.default.removeItem(at: url)
    }
  }

  private func coordinate(writing url: URL, _ body: (URL) throws -> Void) throws {
    var thrown: Error?
    var coordinationError: NSError?

    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) { writable in
      do { try body(writable) } catch { thrown = error }
    }

    if let refusal = thrown as? Refusal { throw refusal }
    if let error = thrown ?? coordinationError {
      throw Refusal(code: "offline", detail: "\(error)")
    }
  }
}
