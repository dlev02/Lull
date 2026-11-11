import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = LullSettings()
  private(set) lazy var engine = FocusEngine(settings: settings)
  private(set) lazy var router = CommandRouter(engine: engine, settings: settings)
  private lazy var server = CommandServer { [weak self] arguments in
    self?.router.run(arguments) ?? ["ok": false, "error": "Lull is shutting down"]
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let info = Bundle.main.infoDictionary ?? [:]
    Log.info(.app, "Lull \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
    router.quitAction = { NSApp.terminate(nil) }
    engine.start()
    server.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    server.stop()
  }

  /// `lull://toggle`, `lull://mode/deep`, `lull://blur/60`: the path is the command.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "lull" {
      let arguments = ([url.host()] + url.pathComponents.filter { $0 != "/" }).compactMap { $0 }
      Log.info(.control, "link: \(url.absoluteString)")
      _ = router.run(arguments)
    }
  }
}
