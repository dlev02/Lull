import Foundation
import Observation

enum FocusMode: String, CaseIterable {
  case ambient, deep

  var title: String {
    switch self {
    case .ambient: "Ambient"
    case .deep: "Deep"
    }
  }

  var next: FocusMode { self == .ambient ? .deep : .ambient }
}

enum ScreenMode: String, CaseIterable {
  case global
  case perScreen = "per-screen"

  var title: String {
    switch self {
    case .global: "Global"
    case .perScreen: "Per screen"
    }
  }
}

/// What the menu bar icon does when clicked, or that it is hidden altogether.
enum MenuBarClick: String, CaseIterable {
  case panel, toggle, hidden

  var title: String {
    switch self {
    case .panel: "Open Settings"
    case .toggle: "Toggle Lull"
    case .hidden: "Hidden"
    }
  }
}

enum GestureModifier: String, CaseIterable {
  case none, control, option, shift, command

  var title: String {
    switch self {
    case .none: "No modifier"
    case .control: "Control"
    case .option: "Option"
    case .shift: "Shift"
    case .command: "Command"
    }
  }
}

/// Everything the user can change, persisted in UserDefaults. Every control surface
/// (panel, shortcuts, gestures, the `lull` command) reads and writes these values.
@Observable
final class LullSettings {
  enum Key: String, CaseIterable {
    case isEnabled, mode, blur, tint, tintColor, grain, isMonochrome, transition
    case isAppWideFocus, screenMode, blursStageManager, menuBarClick
    case isShakeEnabled, shakeToggleModifier, shakePeekModifier, shakeSensitivity
    case ignoredBundleIDs, groups, hasSeenIntro
  }

  static let defaultIgnored = ["com.apple.finder"]
  static let defaultTintColor = "#1D2B4F"

  @ObservationIgnored private let defaults: UserDefaults
  /// Called after any value changes, so the engine can re-apply the look.
  @ObservationIgnored var onChange: (() -> Void)?

  var isEnabled: Bool { didSet { store(isEnabled, .isEnabled) } }
  var mode: FocusMode { didSet { store(mode.rawValue, .mode) } }
  /// 0...1 slider values.
  var blur: Double { didSet { store(blur, .blur) } }
  var tint: Double { didSet { store(tint, .tint) } }
  var tintColor: String { didSet { store(tintColor, .tintColor) } }
  var grain: Double { didSet { store(grain, .grain) } }
  var isMonochrome: Bool { didSet { store(isMonochrome, .isMonochrome) } }
  var transition: Double { didSet { store(transition, .transition) } }

  var isAppWideFocus: Bool { didSet { store(isAppWideFocus, .isAppWideFocus) } }
  var screenMode: ScreenMode { didSet { store(screenMode.rawValue, .screenMode) } }
  var blursStageManager: Bool { didSet { store(blursStageManager, .blursStageManager) } }
  var menuBarClick: MenuBarClick { didSet { store(menuBarClick.rawValue, .menuBarClick) } }

  var isShakeEnabled: Bool { didSet { store(isShakeEnabled, .isShakeEnabled) } }
  var shakeToggleModifier: GestureModifier { didSet { store(shakeToggleModifier.rawValue, .shakeToggleModifier) } }
  var shakePeekModifier: GestureModifier { didSet { store(shakePeekModifier.rawValue, .shakePeekModifier) } }
  var shakeSensitivity: Double { didSet { store(shakeSensitivity, .shakeSensitivity) } }

  var ignoredBundleIDs: [String] { didSet { store(ignoredBundleIDs, .ignoredBundleIDs) } }
  /// Each group is a list of bundle identifiers that stay in focus together.
  var groups: [[String]] { didSet { store(groups, .groups) } }
  var hasSeenIntro: Bool { didSet { store(hasSeenIntro, .hasSeenIntro) } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    func value<T>(_ key: Key, _ fallback: T) -> T {
      defaults.object(forKey: key.rawValue) as? T ?? fallback
    }
    func unit(_ key: Key, _ fallback: Double) -> Double {
      min(1, max(0, value(key, fallback)))
    }
    isEnabled = value(.isEnabled, true)
    mode = FocusMode(rawValue: value(.mode, "")) ?? .ambient
    blur = unit(.blur, 0.6)
    tint = unit(.tint, 0)
    tintColor = value(.tintColor, LullSettings.defaultTintColor)
    grain = unit(.grain, 0.3)
    isMonochrome = value(.isMonochrome, false)
    transition = unit(.transition, 0.4)
    isAppWideFocus = value(.isAppWideFocus, false)
    screenMode = ScreenMode(rawValue: value(.screenMode, "")) ?? .global
    blursStageManager = value(.blursStageManager, false)
    menuBarClick = MenuBarClick(rawValue: value(.menuBarClick, "")) ?? .panel
    isShakeEnabled = value(.isShakeEnabled, true)
    shakeToggleModifier = GestureModifier(rawValue: value(.shakeToggleModifier, "")) ?? .none
    shakePeekModifier = GestureModifier(rawValue: value(.shakePeekModifier, "")) ?? .shift
    shakeSensitivity = unit(.shakeSensitivity, 0.5)
    ignoredBundleIDs = value(.ignoredBundleIDs, LullSettings.defaultIgnored)
    groups = value(.groups, [[String]]())
    hasSeenIntro = value(.hasSeenIntro, false)
  }

  /// Seconds the fade in and out takes.
  var transitionDuration: TimeInterval { 0.05 + transition * 0.75 }

  func resetAll() {
    for key in Key.allCases {
      defaults.removeObject(forKey: key.rawValue)
    }
    let fresh = LullSettings(defaults: defaults)
    let handler = onChange
    onChange = nil
    isEnabled = fresh.isEnabled
    mode = fresh.mode
    blur = fresh.blur
    tint = fresh.tint
    tintColor = fresh.tintColor
    grain = fresh.grain
    isMonochrome = fresh.isMonochrome
    transition = fresh.transition
    isAppWideFocus = fresh.isAppWideFocus
    screenMode = fresh.screenMode
    blursStageManager = fresh.blursStageManager
    menuBarClick = fresh.menuBarClick
    isShakeEnabled = fresh.isShakeEnabled
    shakeToggleModifier = fresh.shakeToggleModifier
    shakePeekModifier = fresh.shakePeekModifier
    shakeSensitivity = fresh.shakeSensitivity
    ignoredBundleIDs = fresh.ignoredBundleIDs
    groups = fresh.groups
    hasSeenIntro = fresh.hasSeenIntro
    onChange = handler
    handler?()
  }

  private func store(_ value: Any, _ key: Key) {
    defaults.set(value, forKey: key.rawValue)
    onChange?()
  }
}
