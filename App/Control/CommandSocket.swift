import Foundation

/// The Unix socket the running app listens on and the `lull` command talks to.
/// One request per connection: a JSON array of arguments in, a JSON object out.
enum CommandSocket {
  static var path: String {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Lull", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("lull.sock").path
  }

  static func address(for path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count < capacity else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      for (index, byte) in bytes.enumerated() {
        buffer[index] = byte
      }
    }
    return address
  }

  /// Opens a connection to the running app, or returns nil if nothing is listening.
  static func connect() -> Int32? {
    guard var address = address(for: path) else { return nil }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return nil }
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      close(descriptor)
      return nil
    }
    return descriptor
  }

  static func setTimeout(_ seconds: Int, on descriptor: Int32) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  /// Reads until the other side sends a newline or closes.
  static func readLine(from descriptor: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 4_000_000 {
      let count = read(descriptor, &buffer, buffer.count)
      guard count > 0 else { break }
      data.append(contentsOf: buffer[0..<count])
      if buffer[0..<count].contains(0x0A) { break }
    }
    return data
  }

  static func write(_ data: Data, to descriptor: Int32) {
    var remaining = data + Data([0x0A])
    while !remaining.isEmpty {
      let count = remaining.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
      guard count > 0 else { break }
      remaining.removeFirst(count)
    }
  }
}

/// Listens inside the running app. Connections are handled on the main queue, where
/// the engine lives; nothing runs between requests.
final class CommandServer {
  private var descriptor: Int32 = -1
  private var source: DispatchSourceRead?
  private let handler: ([String]) -> [String: Any]

  init(handler: @escaping ([String]) -> [String: Any]) {
    self.handler = handler
  }

  func start() {
    let path = CommandSocket.path
    unlink(path)
    guard var address = CommandSocket.address(for: path) else {
      Log.error(.control, "socket path is too long: \(path)")
      return
    }
    descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard descriptor >= 0, bound == 0, listen(descriptor, 8) == 0 else {
      Log.error(.control, "could not listen on \(path): errno \(errno)")
      return
    }
    chmod(path, 0o600)
    let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.acceptConnection() }
    }
    source.resume()
    self.source = source
    Log.info(.control, "listening on \(path)")
  }

  func stop() {
    source?.cancel()
    source = nil
    if descriptor >= 0 {
      close(descriptor)
      descriptor = -1
    }
    unlink(CommandSocket.path)
  }

  private func acceptConnection() {
    let connection = accept(descriptor, nil, nil)
    guard connection >= 0 else { return }
    defer { close(connection) }
    CommandSocket.setTimeout(2, on: connection)
    let request = CommandSocket.readLine(from: connection)
    let arguments = (try? JSONSerialization.jsonObject(with: request)) as? [String]
    let reply: [String: Any] = arguments.map(handler) ?? ["ok": false, "error": "malformed request"]
    let data = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
    CommandSocket.write(data, to: connection)
  }
}
