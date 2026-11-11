import AppKit
import Carbon.HIToolbox
import Observation

/// The actions that can have a global keyboard shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable {
  case toggle, switchMode, ignoreApp, toggleControls

  var id: String { rawValue }

  var title: String {
    switch self {
    case .toggle: "Toggle Lull"
    case .switchMode: "Switch Mode"
    case .ignoreApp: "Ignore App"
    case .toggleControls: "Toggle Controls"
    }
  }

  var defaultShortcut: Shortcut {
    let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    switch self {
    case .toggle: return Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: modifiers)
    case .switchMode: return Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers)
    case .ignoreApp: return Shortcut(keyCode: UInt32(kVK_ANSI_E), modifiers: modifiers)
    case .toggleControls: return Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers)
    }
  }
}

struct Shortcut: Equatable {
  var keyCode: UInt32
  var modifiers: NSEvent.ModifierFlags

  /// The key caps to draw, modifiers first: ["⌃", "⌥", "⌘", "F"].
  var keyCaps: [String] {
    var caps: [String] = []
    if modifiers.contains(.control) { caps.append("⌃") }
    if modifiers.contains(.option) { caps.append("⌥") }
    if modifiers.contains(.shift) { caps.append("⇧") }
    if modifiers.contains(.command) { caps.append("⌘") }
    caps.append(Shortcut.name(forKeyCode: keyCode))
    return caps
  }

  var spokenDescription: String {
    var words: [String] = []
    if modifiers.contains(.control) { words.append("Control") }
    if modifiers.contains(.option) { words.append("Option") }
    if modifiers.contains(.shift) { words.append("Shift") }
    if modifiers.contains(.command) { words.append("Command") }
    words.append(Shortcut.name(forKeyCode: keyCode))
    return words.joined(separator: " ")
  }

  fileprivate var carbonModifiers: UInt32 {
    var flags: UInt32 = 0
    if modifiers.contains(.control) { flags |= UInt32(controlKey) }
    if modifiers.contains(.option) { flags |= UInt32(optionKey) }
    if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
    if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
    return flags
  }

  private static let specialKeys: [Int: String] = [
    kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  ]

  /// The character a key produces on the current keyboard layout, with no modifiers.
  static func name(forKeyCode keyCode: UInt32) -> String {
    if let special = specialKeys[Int(keyCode)] {
      return special
    }
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
    let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    var deadKeys: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
      guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
      return UCKeyTranslate(
        layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
      )
    }
    guard status == noErr, length > 0 else { return "?" }
    return String(utf16CodeUnits: characters, count: length).uppercased()
  }
}

/// Registers the global shortcuts. Carbon hot keys are the one way to do this that
/// needs no permission prompt.
@Observable
final class HotKeys {
  private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var references: [ShortcutAction: EventHotKeyRef] = [:]
  @ObservationIgnored private var handlerReference: EventHandlerRef?
  @ObservationIgnored private let handler: (ShortcutAction) -> Void
  /// The C callback cannot capture, so it finds the instance here.
  @ObservationIgnored private static weak var current: HotKeys?
  private static let signature: OSType = 0x4C55_4C4C // "LULL"

  init(defaults: UserDefaults = .standard, handler: @escaping (ShortcutAction) -> Void) {
    self.defaults = defaults
    self.handler = handler
  }

  func start() {
    HotKeys.current = self
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var identifier = EventHotKeyID()
      let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
      )
      guard status == noErr else { return status }
      let index = Int(identifier.id)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard ShortcutAction.allCases.indices.contains(index) else { return }
          HotKeys.current?.pressed(ShortcutAction.allCases[index])
        }
      }
      return noErr
    }, 1, &eventType, nil, &handlerReference)

    for action in ShortcutAction.allCases {
      shortcuts[action] = stored(for: action)
    }
    registerAll()
  }

  /// Sets or clears (nil) an action's shortcut and saves it.
  func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
    shortcuts[action] = shortcut
    if let shortcut {
      defaults.set(["keyCode": Int(shortcut.keyCode), "modifiers": Int(shortcut.modifiers.rawValue)], forKey: key(action))
    } else {
      defaults.set(["none": true], forKey: key(action))
    }
    registerAll()
  }

  func resetAll() {
    for action in ShortcutAction.allCases {
      defaults.removeObject(forKey: key(action))
      shortcuts[action] = action.defaultShortcut
    }
    registerAll()
  }

  /// Unregisters everything while a new shortcut is being recorded, so pressing an
  /// existing shortcut records it instead of firing it.
  func suspend() {
    for reference in references.values {
      UnregisterEventHotKey(reference)
    }
    references.removeAll()
  }

  func resume() {
    registerAll()
  }

  private func pressed(_ action: ShortcutAction) {
    Log.info(.control, "shortcut: \(action.rawValue)")
    handler(action)
  }

  private func registerAll() {
    suspend()
    for (index, action) in ShortcutAction.allCases.enumerated() {
      guard let shortcut = shortcuts[action] else { continue }
      var reference: EventHotKeyRef?
      let identifier = EventHotKeyID(signature: HotKeys.signature, id: UInt32(index))
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &reference
      )
      if status == noErr, let reference {
        references[action] = reference
      } else {
        Log.warning(.control, "could not register shortcut for \(action.rawValue): \(status)")
      }
    }
  }

  private func stored(for action: ShortcutAction) -> Shortcut? {
    guard let saved = defaults.dictionary(forKey: key(action)) else { return action.defaultShortcut }
    guard let keyCode = saved["keyCode"] as? Int, let modifiers = saved["modifiers"] as? Int else { return nil }
    return Shortcut(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
  }

  private func key(_ action: ShortcutAction) -> String {
    "shortcut." + action.rawValue
  }
}
