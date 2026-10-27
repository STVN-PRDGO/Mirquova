import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MirquovaApp") else { return }
    let channel = FlutterMethodChannel(name: "dev.mirquova/app", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getBuildInfo":
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
          result(FlutterError(code: "version_unavailable", message: "The installed application version could not be read.", details: nil))
          return
        }
        result(["version": version, "buildNumber": build])
      case "openReleasePage":
        let pattern = #"\Ahttps://github\.com/STVN-PRDGO/Mirquova/releases/tag/[A-Za-z0-9][A-Za-z0-9._+\-]{0,127}\z"#
        guard let value = call.arguments as? String,
              value.range(of: pattern, options: .regularExpression) != nil,
              let url = URL(string: value) else {
          result(FlutterError(code: "invalid_release_url", message: "Only Mirquova GitHub release pages can be opened.", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened { result(nil) }
          else { result(FlutterError(code: "browser_unavailable", message: "This release page could not be opened.", details: nil)) }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
    appChannel = channel
  }
}
