import AppKit

/// The single command layer. The `lull` command, `lull://` links, shortcuts and
/// gestures all end up here, so every control has a scriptable equivalent.
final class CommandRouter {
  struct Failure: Error {
    var message: String
  }

  typealias Reply = [String: Any]

  let engine: FocusEngine
  let settings: LullSettings
  /// Set by the app once the panel exists.
  var panelAction: ((String) -> Bool)?
  var loginItemAction: ((Bool?) -> Bool)?
  var quitAction: (() -> Void)?

  static let usage = """
  usage: lull <command> [value]

    on | off | toggle             turn focus on or off
    status                        current state as JSON
    mode [ambient|deep|toggle]    switch strength
    blur|tint|grain <0-100>       set a slider
    tint-color <#RRGGBB>          set the tint colour
    transition <0-100>            fade speed
    monochrome [on|off|toggle]
    app-wide [on|off|toggle]      keep every window of the front app sharp
    screens [global|per-screen]
    stage-blur [on|off|toggle]    cover Stage Manager's strip
    reveal [fade|focus|pointer]   how the blur arrives
    auto-hide [off|dock|menu-bar|both]
    corner-peek [on|off|toggle]   peek while the pointer is in a corner
    ignore [list|add|remove|toggle] [app]
    group [list|add|remove] [app app… | index]
    peek [on|off]                 show everything until turned off
    shake [on|off|toggle]
    sensitivity <0-100>
    panel [show|hide|toggle|<card>]  cards: top focus gestures shortcuts finish ignored about footer
    login [on|off]
    windows                       the window order Lull sees
    diagnostics | log [lines]
    reset                         restore every setting
    quit

  Apps are named by bundle identifier or by name, such as "Mail".
  """

  init(engine: FocusEngine, settings: LullSettings) {
    self.engine = engine
    self.settings = settings
  }

  /// Runs one command and returns a JSON-ready reply. Never throws: failures come
  /// back as `{"ok": false, "error": …}`.
  func run(_ arguments: [String]) -> Reply {
    do {
      var reply = try execute(arguments)
      reply["ok"] = true
      return reply
    } catch let failure as Failure {
      Log.warning(.control, "command \(arguments.joined(separator: " ")) failed: \(failure.message)")
      return ["ok": false, "error": failure.message]
    } catch {
      return ["ok": false, "error": "\(error)"]
    }
  }

  private func execute(_ arguments: [String]) throws -> Reply {
    guard let command = arguments.first?.lowercased() else {
      return ["usage": CommandRouter.usage]
    }
    let values = Array(arguments.dropFirst())
    let value = values.first
    Log.debug(.control, "command: \(arguments.joined(separator: " "))")

    switch command {
    case "on": settings.isEnabled = true
    case "off": settings.isEnabled = false
    case "toggle": engine.toggle()
    case "status": break
    case "help", "--help", "-h": return ["usage": CommandRouter.usage]

    case "mode":
      switch value?.lowercased() {
      case nil, "toggle": engine.switchMode()
      case let name?:
        guard let mode = FocusMode(rawValue: name) else { throw Failure(message: "mode is ambient or deep") }
        settings.mode = mode
      }
    case "blur": settings.blur = try unit(value, "blur")
    case "tint": settings.tint = try unit(value, "tint")
    case "grain": settings.grain = try unit(value, "grain")
    case "transition": settings.transition = try unit(value, "transition")
    case "sensitivity": settings.shakeSensitivity = try unit(value, "sensitivity")
    case "tint-color":
      guard let value, let color = NSColor(hex: value) else { throw Failure(message: "tint-color takes #RRGGBB") }
      settings.tintColor = color.hexString

    case "monochrome": settings.isMonochrome = try flag(value, current: settings.isMonochrome)
    case "app-wide": settings.isAppWideFocus = try flag(value, current: settings.isAppWideFocus)
    case "stage-blur": settings.blursStageManager = try flag(value, current: settings.blursStageManager)
    case "shake": settings.isShakeEnabled = try flag(value, current: settings.isShakeEnabled)
    case "peek": engine.isPeeking = try flag(value, current: engine.isPeeking)
    case "screens":
      if let value {
        guard let mode = ScreenMode(rawValue: value.lowercased()) else {
          throw Failure(message: "screens is global or per-screen")
        }
        settings.screenMode = mode
      }

    case "corner-peek": settings.peeksAtCorners = try flag(value, current: settings.peeksAtCorners)
    case "reveal":
      if let value {
        guard let effect = RevealEffect(rawValue: value.lowercased()) else {
          throw Failure(message: "reveal is fade, focus or pointer")
        }
        settings.revealEffect = effect
      }
    case "auto-hide":
      if let value {
        guard let choice = AutoHide(rawValue: value.lowercased()) else {
          throw Failure(message: "auto-hide is off, dock, menu-bar or both")
        }
        settings.autoHide = choice
      }

    case "ignore": try ignore(values)
    case "group": try group(values)

    case "panel":
      guard let panelAction, panelAction(value?.lowercased() ?? "toggle") else {
        throw Failure(message: "panel takes show, hide, toggle or a card: top, focus, gestures, shortcuts, finish, ignored, about, footer")
      }
    case "login":
      guard let loginItemAction else { throw Failure(message: "login item is unavailable") }
      let wanted: Bool? = try value.map { try flag($0, current: false) }
      return ["login": loginItemAction(wanted)]

    case "tune":
      // Undocumented: `lull tune scale 0.125`, `lull tune reset`.
      if value == "reset" {
        engine.tuning = [:]
      } else if let value, values.count == 2, let number = Double(values[1]) {
        engine.tuning[value] = number
      }
      return ["tuning": engine.tuning]
    case "windows": return windows()
    case "diagnostics": return diagnostics()
    case "log":
      let count = value.flatMap(Int.init) ?? 60
      return ["log": Log.shared.recent(count)]
    case "reset": settings.resetAll()
    case "quit":
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [quitAction] in quitAction?() }
      return ["quitting": true]

    default:
      throw Failure(message: "unknown command \"\(command)\". Run `lull help`.")
    }
    return status()
  }

  // MARK: - Replies

  func status() -> Reply {
    var reply: Reply = [
      "enabled": settings.isEnabled,
      "active": engine.isActive,
      "mode": settings.mode.rawValue,
      "blur": percent(settings.blur),
      "tint": percent(settings.tint),
      "tintColor": settings.tintColor,
      "grain": percent(settings.grain),
      "transition": percent(settings.transition),
      "monochrome": settings.isMonochrome,
      "appWide": settings.isAppWideFocus,
      "screens": settings.screenMode.rawValue,
      "stageBlur": settings.blursStageManager,
      "shake": settings.isShakeEnabled,
      "sensitivity": percent(settings.shakeSensitivity),
      "peeking": engine.isPeeking,
      "reveal": settings.revealEffect.rawValue,
      "autoHide": settings.autoHide.rawValue,
      "cornerPeek": settings.peeksAtCorners,
      "ignored": settings.ignoredBundleIDs,
      "groups": settings.groups,
    ]
    if let reason = engine.standDown {
      reply["standDown"] = reason.rawValue
    }
    if let name = engine.frontAppName {
      reply["frontApp"] = name
    }
    if let bundleID = engine.frontBundleID {
      reply["frontBundleID"] = bundleID
    }
    if let windowID = engine.focusedWindowID {
      reply["focusedWindow"] = Int(windowID)
    }
    return reply
  }

  private func windows() -> Reply {
    let snapshot = WindowSnapshot.capture()
    let candidateIDs = Set(snapshot.candidates.map(\.id))
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let rows: [Reply] = snapshot.ordered.map { window in
      [
        "id": Int(window.id),
        "owner": window.pid == ownPID ? "Lull overlay" : window.owner,
        "pid": Int(window.pid),
        "frame": [Int(window.bounds.minX), Int(window.bounds.minY), Int(window.bounds.width), Int(window.bounds.height)],
        "candidate": candidateIDs.contains(window.id),
        "focused": window.id == engine.focusedWindowID,
      ]
    }
    return ["windows": rows, "stripRects": snapshot.stripRects.count]
  }

  func diagnostics() -> Reply {
    let info = Bundle.main.infoDictionary ?? [:]
    let screens: [Reply] = NSScreen.screens.map { screen in
      [
        "name": screen.localizedName,
        "size": [Int(screen.frame.width), Int(screen.frame.height)],
        "scale": screen.backingScaleFactor,
      ]
    }
    let stageManager = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    return [
      "version": info["CFBundleShortVersionString"] as? String ?? "?",
      "build": info["CFBundleVersion"] as? String ?? "?",
      "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      "displays": screens,
      "stageManager": stageManager,
      "blurBackend": engine.blurBackend,
      "overlays": engine.overlayCount,
      "evaluations": engine.evaluationCount,
      "accessibility": AXIsProcessTrusted(),
      "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
      "status": status(),
      "log": Log.shared.recent(80),
    ]
  }

  // MARK: - Ignored apps and groups

  private func ignore(_ values: [String]) throws {
    switch values.first?.lowercased() {
    case nil, "list": return
    case "toggle" where values.count == 1: engine.toggleIgnoreFrontApp()
    case "add", "remove", "toggle":
      let bundleID = try bundleID(for: values.dropFirst().joined(separator: " "))
      let isIgnored = settings.ignoredBundleIDs.contains(bundleID)
      let shouldIgnore = values[0].lowercased() == "toggle" ? !isIgnored : values[0].lowercased() == "add"
      if shouldIgnore, !isIgnored {
        settings.ignoredBundleIDs.append(bundleID)
      } else if !shouldIgnore {
        settings.ignoredBundleIDs.removeAll { $0 == bundleID }
      }
    default:
      throw Failure(message: "ignore takes list, add, remove or toggle")
    }
  }

  private func group(_ values: [String]) throws {
    switch values.first?.lowercased() {
    case nil, "list": return
    case "add":
      let members = try values.dropFirst().map { try bundleID(for: $0) }
      guard Set(members).count >= 2 else { throw Failure(message: "a group needs at least two different apps") }
      settings.groups.append(members)
    case "remove":
      guard let index = values.dropFirst().first.flatMap(Int.init), settings.groups.indices.contains(index - 1) else {
        throw Failure(message: "group remove takes the group's number, starting at 1")
      }
      settings.groups.remove(at: index - 1)
    default:
      throw Failure(message: "group takes list, add or remove")
    }
  }

  /// Resolves a bundle identifier, running app name or installed app name.
  func bundleID(for text: String) throws -> String {
    let name = text.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { throw Failure(message: "name an app") }
    let running = NSWorkspace.shared.runningApplications
    if let match = running.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(name) == .orderedSame }) {
      return match.bundleIdentifier ?? name
    }
    if let match = running.first(where: { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }),
       let bundleID = match.bundleIdentifier {
      return bundleID
    }
    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) != nil {
      return name
    }
    for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
      let url = URL(fileURLWithPath: folder).appendingPathComponent(name).appendingPathExtension("app")
      if let bundleID = Bundle(url: url)?.bundleIdentifier {
        return bundleID
      }
    }
    throw Failure(message: "no app called \"\(name)\" was found")
  }

  // MARK: - Parsing

  private func unit(_ text: String?, _ name: String) throws -> Double {
    guard let text, let number = Double(text), (0...100).contains(number) else {
      throw Failure(message: "\(name) takes a number from 0 to 100")
    }
    return number / 100
  }

  private func flag(_ text: String?, current: Bool) throws -> Bool {
    switch text?.lowercased() {
    case nil, "toggle": !current
    case "on", "true", "yes", "1": true
    case "off", "false", "no", "0": false
    default: throw Failure(message: "expected on, off or toggle")
    }
  }

  private func percent(_ value: Double) -> Int {
    Int((value * 100).rounded())
  }
}
