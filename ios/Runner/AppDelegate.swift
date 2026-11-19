import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BlossomProfileStore")
    let channel = FlutterMethodChannel(
      name: "blossom/profile_store",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: Any],
            let email = arguments["email"] as? String,
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        result(FlutterError(code: "invalid_email", message: "An email is required for the local profile key.", details: nil))
        return
      }
      let key = "blossom.profile.\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
      let trackingKey = "blossom.tracking.\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
      switch call.method {
      case "loadProfile":
        result(UserDefaults.standard.string(forKey: key))
      case "saveProfile":
        guard let profile = arguments["profile"] as? String else {
          result(FlutterError(code: "invalid_profile", message: "A profile is required.", details: nil))
          return
        }
        UserDefaults.standard.set(profile, forKey: key)
        result(nil)
      case "loadTrackingData":
        result(UserDefaults.standard.string(forKey: trackingKey))
      case "saveTrackingData":
        guard let data = arguments["data"] as? String else {
          result(FlutterError(code: "invalid_tracking_data", message: "Tracking data is required.", details: nil))
          return
        }
        UserDefaults.standard.set(data, forKey: trackingKey)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let readerRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "BlossomReaderStore")
    let readerChannel = FlutterMethodChannel(
      name: "blossom/reader_store",
      binaryMessenger: readerRegistrar.messenger()
    )
    readerChannel.setMethodCallHandler { call, result in
      let defaults = UserDefaults.standard
      switch call.method {
      case "loadReader":
        guard let id = defaults.string(forKey: "blossom.reader.id") else {
          result(nil)
          return
        }
        result(["id": id, "name": defaults.string(forKey: "blossom.reader.name") ?? "Kyvra reader"])
      case "saveReader":
        guard let arguments = call.arguments as? [String: Any],
              let id = arguments["id"] as? String,
              let name = arguments["name"] as? String,
              !id.isEmpty, !name.isEmpty else {
          result(FlutterError(code: "invalid_reader", message: "A reader ID and name are required.", details: nil))
          return
        }
        defaults.set(id, forKey: "blossom.reader.id")
        defaults.set(name, forKey: "blossom.reader.name")
        result(nil)
      case "forgetReader":
        defaults.removeObject(forKey: "blossom.reader.id")
        defaults.removeObject(forKey: "blossom.reader.name")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
