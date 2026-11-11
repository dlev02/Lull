import Foundation
import ServiceManagement

/// Start at login, through the system's own login-items list.
enum LoginItem {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Development builds run from a build folder that changes with every build, so
  /// only an installed copy registers itself.
  static var isInstalledCopy: Bool {
    Bundle.main.bundlePath.hasPrefix("/Applications/")
      || Bundle.main.bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
  }

  @discardableResult
  static func set(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      Log.info(.app, "start at login \(enabled ? "on" : "off")")
    } catch {
      Log.error(.app, "start at login could not be turned \(enabled ? "on" : "off"): \(error.localizedDescription)")
    }
    return isEnabled
  }

  /// Lull starts at login unless the person has turned that off. Runs once.
  static func enableByDefault(defaults: UserDefaults = .standard) {
    let key = "didSetLoginItemDefault"
    guard isInstalledCopy, !defaults.bool(forKey: key) else { return }
    defaults.set(true, forKey: key)
    set(true)
  }
}
