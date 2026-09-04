import Flutter
import UIKit

/// A reason the Dart side turns into a sentence.
///
/// The strings never reach a caregiver — see `refusalFor` in
/// cloud_destination.dart, which owns the wording so that a platform message
/// cannot become app copy.
struct CloudRefusal: Error {
  let code: String
  let detail: String
}

/// One of the places on this device that copies can go.
///
/// The raw values cross the channel and are matched by name on the Dart side.
enum CloudPlace: String {
  case account
  case folder
}

/// Somewhere copies of the board can be kept, on this device's terms.
///
/// Two of these exist and neither is a variation on the other: one is a folder
/// the operating system hands over on the strength of an entitlement, the other
/// is a folder a caregiver named in a provider we hold no credential for.
protocol CloudStore {
  /// What to call it in front of a caregiver, or nil to let the Dart side name
  /// it from the platform alone.
  var label: String? { get }

  /// Whether a copy written now would arrive.
  var reachable: Bool { get }

  func list() throws -> [[String: Any]]
  func upload(path: String, name: String) throws -> [String: Any]
  func download(id: String, to path: String) throws
  func delete(id: String) throws
}

/// Copies of the board in the family's own storage, and nowhere else.
///
/// Two places, chosen per device. **The app's own iCloud container** is the
/// default: not the automatic iCloud device backup that sweeps up an app's
/// local documents folder, which cannot be triggered, listed, dated or
/// verified and restores only onto a wiped device. That one is the mechanism
/// behind *"we lost months of custom button and phrase building because we
/// thought the iCloud backup would protect us"*, and a backups screen built on
/// it could only ever say "probably". **A folder somebody picked** is the
/// other — see `CloudFolder` — and it exists because a family who keep
/// everything in Google Drive should not have to keep a second copy in iCloud
/// to be backed up.
///
/// Nothing here talks to a server of ours. Both places are the device's own:
/// the entitlement names this app's container, the picker hands back one folder
/// and nothing else, and no credential of ours exists anywhere in this file.
///
/// Every call runs off the main thread except the picker, which has to be on
/// the thread that owns the screen. iCloud coordination blocks, and a blocked
/// main thread on this app is a nonspeaking person staring at a frozen board.
public class CloudBackup: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.wordbridge/cloud_backup",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CloudBackup(), channel: channel)
  }

  /// Where copies go on this device.
  ///
  /// In UserDefaults rather than passed down on every call, because the answer
  /// outlives the process that gave it. The folder's bookmark is kept beside it
  /// either way, so somebody who tries iCloud for a week and goes back to their
  /// Drive folder is not asked to find it again.
  private static let placeKey = "org.wordbridge.cloud_backup.place"

  private let queue = DispatchQueue(label: "org.wordbridge.cloud-backup")
  private let container = CloudContainer()
  private let folder = CloudFolder()

  private var place: CloudPlace {
    get {
      CloudPlace(rawValue: UserDefaults.standard.string(forKey: Self.placeKey) ?? "")
        ?? .account
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.placeKey) }
  }

  private var store: CloudStore { place == .folder ? folder : container }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    // Handled apart from the rest because it can end in a picker, and a picker
    // has to be presented from the thread that owns the screen and answers
    // whenever whoever is holding the tablet gets around to it.
    if call.method == "connect" {
      connect(arguments, result)
      return
    }

    queue.async {
      do {
        let value: Any?
        switch call.method {
        case "place":
          value = self.whereItGoes()
        case "list":
          value = try self.store.list()
        case "upload":
          value = try self.store.upload(
            path: arguments["path"] as? String ?? "",
            name: arguments["name"] as? String ?? "")
        case "download":
          try self.store.download(
            id: arguments["id"] as? String ?? "",
            to: arguments["path"] as? String ?? "")
          value = nil
        case "delete":
          try self.store.delete(id: arguments["id"] as? String ?? "")
          value = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(value) }
      } catch let failure as CloudRefusal {
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

  /// Where copies go, what it is called, and whether one would arrive.
  ///
  /// All three in one reply, so that a sentence written after a place changes
  /// cannot still name the place copies were going to when the app started.
  private func whereItGoes() -> [String: Any] {
    let store = self.store
    var reply: [String: Any] = ["place": place.rawValue, "reachable": store.reachable]
    if let label = store.label { reply["label"] = label }
    return reply
  }

  /// Sets up whatever the place needs, opening a picker only where one is due.
  ///
  /// A folder already held is not asked for again: switching back to it would
  /// otherwise put a picker in the face of somebody whose folder is fine.
  /// `pick` overrides that, which is both "use a different one" and the only
  /// way back from a folder the tablet has lost.
  ///
  /// The move is written down only once there is somewhere for it to land. A
  /// place set before the picker would leave a dismissed picker pointing the
  /// tablet at a folder that does not exist — a working backup switched off by
  /// somebody who only changed their mind.
  private func connect(_ arguments: [String: Any], _ result: @escaping FlutterResult) {
    queue.async {
      let asked = (arguments["place"] as? String).flatMap(CloudPlace.init(rawValue:))
      let going = asked ?? self.place
      let pick = arguments["pick"] as? Bool ?? false

      guard going == .folder, pick || !self.folder.reachable else {
        self.place = going
        self.answer(result)
        return
      }

      DispatchQueue.main.async {
        self.folder.pick {
          self.queue.async {
            if self.folder.reachable { self.place = .folder }
            self.answer(result)
          }
        }
      }
    }
  }

  private func answer(_ result: @escaping FlutterResult) {
    let reply = whereItGoes()
    DispatchQueue.main.async { result(reply) }
  }
}

/// The app's own folder inside the iCloud account signed in on this device.
///
/// Under `Documents` rather than the container root so the files are visible in
/// the Files app: a family moving to a tablet that is not signed in to the same
/// account has to be able to carry the file across by hand. It needs the
/// matching `NSUbiquitousContainers` key in Info.plist and the iCloud container
/// entitlement — which is the one practical difference from `CloudFolder`, and
/// the reason a build without the entitlement still has somewhere to put a
/// copy.
final class CloudContainer: CloudStore {
  /// How long a fetch of one snapshot may wait for iCloud to materialize it.
  ///
  /// Bounded because the caller is a caregiver watching a spinner on the day
  /// their tablet stopped working. A refusal they can retry beats a wait with
  /// no end, and the local backups are still there either way.
  private static let downloadTimeout: TimeInterval = 120

  /// Named by the Dart side, which knows the platform's word for it before
  /// anything has been signed in to.
  var label: String? { nil }

  var reachable: Bool { (try? documents()) != nil }

  /// The container's Documents folder, created if this is the first copy.
  ///
  /// Throws `signIn` rather than returning nil for the ordinary case: an iPad
  /// signed out of iCloud, which is a thing a caregiver can fix and the most
  /// common reason copies stop arriving.
  private func documents() throws -> URL {
    guard FileManager.default.ubiquityIdentityToken != nil,
      let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
    else {
      throw CloudRefusal(code: "signIn", detail: "No iCloud account on this device.")
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
  func list() throws -> [[String: Any]] {
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

  func upload(path: String, name: String) throws -> [String: Any] {
    let source = URL(fileURLWithPath: path)
    let destination = try documents().appendingPathComponent(name)

    try coordinate(writing: destination) { target in
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      do {
        try FileManager.default.copyItem(at: source, to: target)
      } catch let error as NSError where error.code == NSFileWriteOutOfSpaceError {
        throw CloudRefusal(code: "space", detail: "No room in iCloud.")
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
  func download(id: String, to path: String) throws {
    let source = try documents().appendingPathComponent(id)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw CloudRefusal(code: "missing", detail: "No such backup in iCloud.")
    }

    try FileManager.default.startDownloadingUbiquitousItem(at: source)

    let deadline = Date().addingTimeInterval(CloudContainer.downloadTimeout)
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
      throw CloudRefusal(code: "offline", detail: "\(error)")
    }
  }

  func delete(id: String) throws {
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

    if let refusal = thrown as? CloudRefusal { throw refusal }
    if let error = thrown ?? coordinationError {
      throw CloudRefusal(code: "offline", detail: "\(error)")
    }
  }
}
