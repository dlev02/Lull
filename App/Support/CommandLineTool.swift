import AppKit

/// Puts a `lull` command on the PATH by linking to this app's own executable.
enum CommandLineTool {
  static let linkPath = "/usr/local/bin/lull"

  private static var executablePath: String {
    Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? ""
  }

  /// True when `lull` on the PATH already runs this copy of the app.
  static var isInstalled: Bool {
    guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else { return false }
    return URL(fileURLWithPath: destination).resolvingSymlinksInPath().path == executablePath
  }

  /// Creates the link, asking for an administrator password only if the folder
  /// isn't writable.
  @discardableResult
  static func install() -> Bool {
    let manager = FileManager.default
    let folder = (linkPath as NSString).deletingLastPathComponent
    do {
      try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
      try? manager.removeItem(atPath: linkPath)
      try manager.createSymbolicLink(atPath: linkPath, withDestinationPath: executablePath)
    } catch {
      let quoted = executablePath.replacingOccurrences(of: "'", with: "'\\''")
      let script = "do shell script \"mkdir -p \(folder) && ln -sf '\(quoted)' \(linkPath)\" with administrator privileges"
      var failure: NSDictionary?
      NSAppleScript(source: script)?.executeAndReturnError(&failure)
      if let failure {
        Log.warning(.app, "could not install the lull command: \(failure[NSAppleScript.errorMessage] ?? "unknown")")
      }
    }
    Log.info(.app, "lull command installed: \(isInstalled)")
    return isInstalled
  }
}
