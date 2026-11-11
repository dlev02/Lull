import AppKit

// One executable, two roles. Started with a command (`lull on`), it forwards the
// command to the running app and exits. Started by Launch Services, it is the app.
let commandArguments = Array(CommandLine.arguments.dropFirst())
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

if CommandClient.shouldHandle(invokedName: invokedName, arguments: commandArguments) {
  exit(CommandClient.run(arguments: commandArguments))
}

// A second copy would stack a second set of overlays; hand over to the first.
if let existing = CommandSocket.connect() {
  close(existing)
  exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
