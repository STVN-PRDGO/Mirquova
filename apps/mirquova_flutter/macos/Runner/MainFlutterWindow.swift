import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appChannel: FlutterMethodChannel?

  static func isReleasePage(_ value: String) -> Bool {
    let pattern = #"\Ahttps://github\.com/STVN-PRDGO/Mirquova/releases/tag/[A-Za-z0-9][A-Za-z0-9._+\-]{0,127}\z"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  static func updateDirectory() throws -> URL {
    let root = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true).appendingPathComponent("mirquova-updates", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
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
      case "getUpdateDirectory":
        do {
          let root = try MainFlutterWindow.updateDirectory()
          result(root.path)
        } catch {
          result(FlutterError(code: "storage_unavailable", message: "Update storage is unavailable.", details: nil))
        }
      case "openUpdatePackage":
        do {
          let root = try MainFlutterWindow.updateDirectory().resolvingSymlinksInPath()
          guard let path = call.arguments as? String else { throw CocoaError(.fileReadInvalidFileName) }
          let file = URL(fileURLWithPath: path).standardizedFileURL
          let resolved = file.resolvingSymlinksInPath()
          let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
          guard file == resolved,
                values.isRegularFile == true, values.isSymbolicLink != true,
                resolved.deletingLastPathComponent().deletingLastPathComponent() == root,
                resolved.deletingLastPathComponent().lastPathComponent.hasPrefix("download-"),
                resolved.lastPathComponent == "Mirquova-preview-macos-arm64.zip" else {
            throw CocoaError(.fileReadInvalidFileName)
          }
          if NSWorkspace.shared.open(resolved) { result(nil) }
          else { result(FlutterError(code: "package_unavailable", message: "The downloaded package could not be opened.", details: nil)) }
        } catch {
          result(FlutterError(code: "invalid_package", message: "Only a downloaded Mirquova update can be opened.", details: nil))
        }
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
