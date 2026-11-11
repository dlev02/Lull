import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = LullSettings()
  private(set) lazy var engine = FocusEngine(settings: settings)
  private(set) lazy var router = CommandRouter(engine: engine, settings: settings)
  private lazy var server = CommandServer { [weak self] arguments in
    self?.router.run(arguments) ?? ["ok": false, "error": "Lull is shutting down"]
  }
  private lazy var hotKeys = HotKeys { [weak self] action in
    self?.perform(action)
  }
  private lazy var autoHider = AutoHider(settings: settings)
  private let updates = UpdateController()
  private lazy var model = AppModel(settings: settings, engine: engine, hotKeys: hotKeys, updates: updates)
  private lazy var panel = PanelController(model: model)
  private lazy var statusItem = StatusItemController(model: model, panel: panel) {
    NSApp.terminate(nil)
  }
  private lazy var gestures = PointerGestures(settings: settings) { [weak self] gesture in
    guard let self else { return }
    switch gesture {
    case .toggle: self.engine.toggle()
    case .peekBegan: self.engine.isPeeking = true
    case .peekEnded: self.engine.isPeeking = false
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Log.info(.app, "Lull \(AppInfo.version) (\(AppInfo.build)) on \(ProcessInfo.processInfo.operatingSystemVersionString)")

    // Every setting change, from any control surface, lands here.
    settings.onChange = { [weak self] in
      guard let self else { return }
      self.engine.settingsChanged()
      self.statusItem.update()
      self.gestures.update()
      self.autoHider.update(isActive: self.engine.isActive)
    }
    router.quitAction = { NSApp.terminate(nil) }
    router.panelAction = { [weak self] verb in
      guard let self else { return false }
      switch verb {
      case "show": self.panel.show(on: self.panelScreen)
      case "hide": self.panel.hide()
      case "toggle": self.panel.toggle(on: self.panelScreen)
      case "top", "focus", "gestures", "shortcuts", "finish", "ignored", "about", "footer":
        // Opens the panel at one card.
        self.panel.show(on: self.panelScreen)
        self.model.scrollTarget = verb
      default: return false
      }
      return true
    }
    router.loginItemAction = { [weak self] wanted in
      if let wanted {
        self?.model.setLaunchesAtLogin(wanted)
      }
      return LoginItem.isEnabled
    }

    engine.start()
    hotKeys.start()
    gestures.update()
    autoHider.recoverIfNeeded()
    engine.onActiveChange = { [weak self] isActive in
      self?.autoHider.update(isActive: isActive)
    }
    statusItem.update()
    server.start()
    LoginItem.enableByDefault()
    updates.start()

    if !settings.hasSeenIntro {
      // First launch: open the panel so the intro is the first thing seen.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self else { return }
        self.panel.show(on: self.panelScreen)
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    autoHider.restoreNow()
    server.stop()
  }

  /// Opening the app again (from Finder or Spotlight) shows the panel, which is the
  /// way back in when the menu bar icon is hidden.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    panel.show(on: panelScreen)
    return false
  }

  /// `lull://toggle`, `lull://mode/deep`, `lull://blur/60`: the path is the command.
  func application(_ application: NSApplication, open urls: [URL]) {
    // Any web page can open a link, so links can't do what would be a nuisance or
    // reach outside the app: those stay with the command line and the panel.
    let notFromLinks: Set<String> = ["reset", "quit", "login", "auto-hide", "tune"]
    for url in urls where url.scheme == "lull" {
      let arguments = ([url.host()] + url.pathComponents.filter { $0 != "/" }).compactMap { $0 }
      guard let command = arguments.first?.lowercased(), !notFromLinks.contains(command) else {
        Log.warning(.control, "link refused: \(url.absoluteString)")
        continue
      }
      Log.info(.control, "link: \(url.absoluteString)")
      _ = router.run(arguments)
    }
  }

  private var panelScreen: NSScreen? {
    statusItem.screen ?? NSScreen.main
  }

  private func perform(_ action: ShortcutAction) {
    switch action {
    case .toggle: engine.toggle()
    case .switchMode: engine.switchMode()
    case .ignoreApp: engine.toggleIgnoreFrontApp()
    case .toggleControls: panel.toggle(on: panelScreen)
    }
  }
}
