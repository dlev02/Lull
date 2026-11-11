import Foundation
import os

/// The one logging helper for Lull. Lines go to the unified log and to a bounded
/// in-memory buffer that `lull log` and `lull diagnostics` read back.
final class Log {
  enum Category: String {
    case app, engine, windows, overlay, control, gesture, update
  }

  enum Level: String {
    case debug, info, warning, error

    var osType: OSLogType {
      switch self {
      case .debug: .debug
      case .info: .info
      case .warning: .default
      case .error: .error
      }
    }
  }

  static let shared = Log()
  static let subsystem = "io.github.dlev02.lull"

  private let capacity = 600
  private var lines: [String] = []
  private var loggers: [Category: Logger] = [:]
  private let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  func write(_ level: Level, _ category: Category, _ message: String) {
    let logger = loggers[category] ?? {
      let created = Logger(subsystem: Log.subsystem, category: category.rawValue)
      loggers[category] = created
      return created
    }()
    logger.log(level: level.osType, "\(message, privacy: .public)")

    lines.append("\(clock.string(from: Date())) \(level.rawValue) [\(category.rawValue)] \(message)")
    if lines.count > capacity {
      lines.removeFirst(lines.count - capacity)
    }
  }

  func recent(_ count: Int) -> [String] {
    Array(lines.suffix(max(0, count)))
  }

  static func debug(_ category: Category, _ message: String) { shared.write(.debug, category, message) }
  static func info(_ category: Category, _ message: String) { shared.write(.info, category, message) }
  static func warning(_ category: Category, _ message: String) { shared.write(.warning, category, message) }
  static func error(_ category: Category, _ message: String) { shared.write(.error, category, message) }
}
