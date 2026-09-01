import Flutter
import UIKit

/// The hardware identifier, and nothing else.
///
/// `iPad11,1` names a product line millions of people own, which is what makes
/// it safe to put in a report and useful in one: a neural voice timing means
/// nothing without knowing what it was measured on. Nothing here reads a
/// serial, a vendor id, or a device name — a device name is very often the
/// owner's own name.
public class DeviceFacts: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.wordbridge/device_facts",
      binaryMessenger: registrar.messenger())
    let instance = DeviceFacts()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "model":
      result(DeviceFacts.machine())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func machine() -> String {
    var system = utsname()
    uname(&system)

    // Copied out before it is pointed at. Taking a pointer to `system.machine`
    // while `system` is still the thing being read is an overlapping access,
    // and Xcode refuses to build it.
    let identifier = system.machine
    return withUnsafePointer(to: identifier) { pointer in
      pointer.withMemoryRebound(
        to: CChar.self,
        capacity: MemoryLayout.size(ofValue: identifier)
      ) {
        String(cString: $0)
      }
    }
  }
}
