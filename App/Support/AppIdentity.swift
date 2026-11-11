import AppKit

/// The name and icon of an app, looked up from its bundle identifier.
struct AppIdentity: Identifiable {
  var bundleID: String
  var name: String
  var icon: NSImage

  var id: String { bundleID }

  private static var cache: [String: AppIdentity] = [:]

  static func lookup(_ bundleID: String) -> AppIdentity {
    if let cached = cache[bundleID] {
      return cached
    }
    var identity = AppIdentity(
      bundleID: bundleID,
      name: bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID,
      icon: NSWorkspace.shared.icon(for: .application)
    )
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      identity.name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
      identity.icon = NSWorkspace.shared.icon(forFile: url.path)
      cache[bundleID] = identity
    }
    return identity
  }

  /// Apps with a Dock presence that are running now, for the "add" menus.
  static var running: [AppIdentity] {
    NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { $0.bundleIdentifier }
      .map(lookup)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Lets the person choose apps from the Applications folder.
  static func choose(allowsMultiple: Bool, message: String) -> [String] {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = allowsMultiple
    panel.canChooseDirectories = false
    panel.message = message
    panel.prompt = "Choose"
    panel.level = .modalPanel
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK else { return [] }
    return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
  }
}
