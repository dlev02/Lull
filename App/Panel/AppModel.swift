import AppKit
import Observation

/// What the panel's views read and act on.
@Observable
final class AppModel {
  let settings: LullSettings
  let engine: FocusEngine
  let hotKeys: HotKeys
  let updates: UpdateController

  var isIntroVisible: Bool
  var launchesAtLogin = LoginItem.isEnabled
  var isCommandInstalled = CommandLineTool.isInstalled
  /// The shortcut being re-recorded, if any. The panel's key handler fills it in.
  var recordingAction: ShortcutAction?
  /// A card for the panel to scroll to: top, focus, gestures, shortcuts, finish,
  /// ignored, about or footer.
  var scrollTarget: String?
  /// Closes the panel; set by the panel's controller.
  @ObservationIgnored var closePanel: (() -> Void)?

  init(settings: LullSettings, engine: FocusEngine, hotKeys: HotKeys, updates: UpdateController) {
    self.settings = settings
    self.engine = engine
    self.hotKeys = hotKeys
    self.updates = updates
    isIntroVisible = !settings.hasSeenIntro
  }

  /// Re-reads state that can change outside the app, each time the panel opens.
  func refresh() {
    launchesAtLogin = LoginItem.isEnabled
    isCommandInstalled = CommandLineTool.isInstalled
  }

  func dismissIntro() {
    settings.hasSeenIntro = true
    isIntroVisible = false
  }

  func setLaunchesAtLogin(_ enabled: Bool) {
    launchesAtLogin = LoginItem.set(enabled)
  }

  func installCommand() {
    isCommandInstalled = CommandLineTool.install()
  }

  // MARK: - Shortcuts

  func beginRecording(_ action: ShortcutAction) {
    hotKeys.suspend()
    recordingAction = action
  }

  /// Saves the recorded shortcut, or leaves things as they were when given nil.
  func finishRecording(_ shortcut: Shortcut?) {
    if let shortcut, let action = recordingAction {
      hotKeys.set(shortcut, for: action)
    } else {
      hotKeys.resume()
    }
    recordingAction = nil
  }

  // MARK: - Apps

  func toggleIgnore(_ bundleID: String) {
    if let index = settings.ignoredBundleIDs.firstIndex(of: bundleID) {
      settings.ignoredBundleIDs.remove(at: index)
    } else {
      settings.ignoredBundleIDs.append(bundleID)
    }
  }

  func chooseIgnoredApps() {
    let chosen = AppIdentity.choose(allowsMultiple: true, message: "Choose apps Lull should ignore")
    for bundleID in chosen where !settings.ignoredBundleIDs.contains(bundleID) {
      settings.ignoredBundleIDs.append(bundleID)
    }
  }

  func chooseGroup() {
    let chosen = AppIdentity.choose(allowsMultiple: true, message: "Choose two or more apps to keep in focus together")
    var members: [String] = []
    for bundleID in chosen where !members.contains(bundleID) {
      members.append(bundleID)
    }
    guard members.count >= 2 else { return }
    settings.groups.append(members)
  }

  // MARK: - Housekeeping

  func resetAll() {
    let alert = NSAlert()
    alert.messageText = "Reset all settings?"
    alert.informativeText = "Every slider, shortcut, group and ignored app goes back to how Lull started."
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    settings.resetAll()
    hotKeys.resetAll()
    isIntroVisible = true
    Log.info(.app, "all settings reset")
  }

  func openIssue() {
    let displays = NSScreen.screens
      .map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.backingScaleFactor))x" }
      .joined(separator: ", ")
    let stageManager = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    NSWorkspace.shared.open(AppInfo.issueURL(displays: displays, stageManager: stageManager, blurBackend: engine.blurBackend))
  }
}
