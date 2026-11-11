import AppKit

/// Tucks the Dock or menu bar away while Lull is focusing, and puts them back as they
/// were afterwards. macOS only allows this through System Events, so the first use
/// asks for the Automation permission; nothing is asked while the option is off.
final class AutoHider {
  private enum Key {
    static let isDirty = "autoHide.dirty"
    static let originalDock = "autoHide.originalDock"
    static let originalMenuBar = "autoHide.originalMenuBar"
  }

  private let settings: LullSettings
  private let defaults: UserDefaults
  /// AppleScript runs off the main thread; a permission prompt can take a while.
  private let queue = DispatchQueue(label: "io.github.dlev02.lull.autohide")
  private var pendingRestore: DispatchWorkItem?
  private var isApplied = false

  init(settings: LullSettings, defaults: UserDefaults = .standard) {
    self.settings = settings
    self.defaults = defaults
  }

  /// Call whenever Lull goes active or inactive, or the option changes.
  func update(isActive: Bool) {
    pendingRestore?.cancel()
    pendingRestore = nil
    if isActive, settings.autoHide != .off {
      apply(settings.autoHide)
    } else if isApplied {
      // Brief stand-downs (a click on the desktop, a Space change) shouldn't make the
      // Dock bounce in and out, so wait a moment before restoring.
      let item = DispatchWorkItem { [weak self] in self?.restoreNow() }
      pendingRestore = item
      DispatchQueue.main.asyncAfter(deadline: .now() + (settings.autoHide == .off ? 0 : 1.2), execute: item)
    }
  }

  /// If Lull quit unexpectedly with things hidden, put them back at the next launch.
  func recoverIfNeeded() {
    guard defaults.bool(forKey: Key.isDirty) else { return }
    Log.info(.app, "auto-hide: restoring after an unclean exit")
    isApplied = true
    restoreNow()
  }

  func restoreNow() {
    pendingRestore?.cancel()
    pendingRestore = nil
    guard isApplied else { return }
    isApplied = false
    let dock = defaults.bool(forKey: Key.originalDock)
    let menuBar = defaults.bool(forKey: Key.originalMenuBar)
    defaults.set(false, forKey: Key.isDirty)
    queue.async {
      AutoHider.run("tell application \"System Events\" to set autohide of dock preferences to \(dock)")
      AutoHider.run("tell application \"System Events\" to set autohide menu bar of dock preferences to \(menuBar)")
    }
  }

  private func apply(_ option: AutoHide) {
    let isFirst = !isApplied
    isApplied = true
    let hidesDock = option.hidesDock
    let hidesMenuBar = option.hidesMenuBar
    let knownDock = defaults.bool(forKey: Key.originalDock)
    let knownMenuBar = defaults.bool(forKey: Key.originalMenuBar)
    queue.async { [weak self] in
      let dockWasHidden: Bool
      let menuBarWasHidden: Bool
      if isFirst {
        // Remember how things were before changing anything.
        guard let dock = AutoHider.run("tell application \"System Events\" to return autohide of dock preferences"),
              let menuBar = AutoHider.run("tell application \"System Events\" to return autohide menu bar of dock preferences") else {
          DispatchQueue.main.async {
            MainActor.assumeIsolated { self?.refused() }
          }
          return
        }
        dockWasHidden = dock == "true"
        menuBarWasHidden = menuBar == "true"
        DispatchQueue.main.async {
          MainActor.assumeIsolated { self?.remember(dock: dockWasHidden, menuBar: menuBarWasHidden) }
        }
      } else {
        dockWasHidden = knownDock
        menuBarWasHidden = knownMenuBar
      }
      AutoHider.run("tell application \"System Events\" to set autohide of dock preferences to \(hidesDock || dockWasHidden)")
      AutoHider.run("tell application \"System Events\" to set autohide menu bar of dock preferences to \(hidesMenuBar || menuBarWasHidden)")
    }
  }

  private func remember(dock: Bool, menuBar: Bool) {
    defaults.set(dock, forKey: Key.originalDock)
    defaults.set(menuBar, forKey: Key.originalMenuBar)
    defaults.set(true, forKey: Key.isDirty)
  }

  private func refused() {
    isApplied = false
    Log.warning(.app, "auto-hide: System Events refused; allow Lull under Privacy & Security > Automation")
  }

  @discardableResult
  private nonisolated static func run(_ source: String) -> String? {
    var failure: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&failure)
    guard failure == nil else { return nil }
    return result?.stringValue ?? ""
  }
}
