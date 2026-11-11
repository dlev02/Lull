import AppKit

// One executable, two roles. Started with a command (`lull on`), it forwards the
// command to the running app and exits. Started by Launch Services, it is the app.
let commandArguments = Array(CommandLine.arguments.dropFirst())
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

if CommandClient.shouldHandle(invokedName: invokedName, arguments: commandArguments) {
  exit(CommandClient.run(arguments: commandArguments))
}

let application = NSApplication.shared

// A second copy would stack a second set of overlays. If one is already running,
// pass it any link this copy was opened with, then step aside.
let runningCopies = NSRunningApplication
  .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
  .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !runningCopies.isEmpty {
  let forwarder = LinkForwarder()
  application.delegate = forwarder
  application.setActivationPolicy(.prohibited)
  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
  application.run()
}

let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()

/// Stands in as the delegate of a second copy just long enough to hand its links on.
final class LinkForwarder: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "lull" {
      _ = CommandClient.send(["link", url.absoluteString])
    }
    exit(0)
  }
}
