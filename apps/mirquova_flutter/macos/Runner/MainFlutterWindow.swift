import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appChannel: FlutterMethodChannel?

  static func isReleasePage(_ value: String) -> Bool {
    let pattern = #"\Ahttps://github\.com/STVN-PRDGO/Mirquova/releases/tag/[A-Za-z0-9][A-Za-z0-9._+\-]{0,127}\z"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "dev.mirquova/app",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getBuildInfo":
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty,
              let buildNumber = info["CFBundleVersion"] as? String,
              !buildNumber.isEmpty else {
          result(FlutterError(
            code: "version_unavailable",
            message: "The installed application version could not be read.",
            details: nil
          ))
          return
        }
        result(["version": version, "buildNumber": buildNumber])
      case "openReleasePage":
        guard let value = call.arguments as? String,
              MainFlutterWindow.isReleasePage(value),
              let url = URL(string: value) else {
          result(FlutterError(
            code: "invalid_release_url",
            message: "Only Mirquova GitHub release pages can be opened.",
            details: nil
          ))
          return
        }
        if NSWorkspace.shared.open(url) {
          result(nil)
        } else {
          result(FlutterError(
            code: "browser_unavailable",
            message: "This release page could not be opened.",
            details: nil
          ))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appChannel = channel

    super.awakeFromNib()
  }
}
