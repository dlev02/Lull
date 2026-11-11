import Foundation

/// The `lull` command. It is the app's own executable started with arguments (or
/// through a symlink named `lull`): it forwards them to the running app, prints the
/// JSON reply and exits without ever starting the app's interface.
enum CommandClient {
  static func shouldHandle(invokedName: String, arguments: [String]) -> Bool {
    if invokedName == "lull" { return true }
    // Launch Services and Xcode pass only dash-prefixed arguments.
    guard let first = arguments.first else { return false }
    return !first.hasPrefix("-")
  }

  static func run(arguments: [String]) -> Int32 {
    let command = arguments.first?.lowercased()
    if command == nil || command == "help" || command == "--help" || command == "-h" {
      print(CommandRouter.usage)
      return 0
    }

    var descriptor = CommandSocket.connect()
    if descriptor == nil, command != "quit" {
      launchApp()
      for _ in 0..<50 where descriptor == nil {
        usleep(100_000)
        descriptor = CommandSocket.connect()
      }
    }
    guard let descriptor else {
      print(command == "quit" ? "{\"ok\":true,\"quitting\":false}" : "{\"ok\":false,\"error\":\"Lull is not running\"}")
      return command == "quit" ? 0 : 1
    }
    defer { close(descriptor) }
    CommandSocket.setTimeout(5, on: descriptor)

    guard let request = try? JSONSerialization.data(withJSONObject: arguments) else { return 1 }
    CommandSocket.write(request, to: descriptor)
    let reply = CommandSocket.readLine(from: descriptor)
    guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
      print("{\"ok\":false,\"error\":\"no reply from Lull\"}")
      return 1
    }
    if let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
       let text = String(data: pretty, encoding: .utf8) {
      print(text)
    }
    return (object["ok"] as? Bool) == true ? 0 : 1
  }

  /// Sends one command to the running app without printing, for a second copy that
  /// is handing a link on. Returns false if nothing is listening.
  static func send(_ arguments: [String]) -> Bool {
    guard let descriptor = CommandSocket.connect() else { return false }
    defer { close(descriptor) }
    CommandSocket.setTimeout(3, on: descriptor)
    guard let request = try? JSONSerialization.data(withJSONObject: arguments) else { return false }
    CommandSocket.write(request, to: descriptor)
    return !CommandSocket.readLine(from: descriptor).isEmpty
  }

  /// Starts the app this executable belongs to, in the background.
  private static func launchApp() {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard bundle.pathExtension == "app" else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", bundle.path]
    try? process.run()
    process.waitUntilExit()
  }
}
