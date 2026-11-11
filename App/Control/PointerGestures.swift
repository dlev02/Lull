import AppKit

/// Recognises a quick side-to-side shake of the pointer, and the pointer resting in
/// a screen corner. Watching pointer movement needs no permission; the monitor only
/// exists while one of the gestures is on.
final class PointerGestures {
  enum Gesture {
    case toggle
    case peekBegan
    case peekEnded
  }

  private let settings: LullSettings
  private let handler: (Gesture) -> Void
  private var globalMonitor: Any?
  private var localMonitor: Any?

  private var lastX: CGFloat = 0
  private var strokeStartX: CGFloat = 0
  private var direction: CGFloat = 0
  /// When each recent change of direction happened.
  private var reversals: [TimeInterval] = []
  private var lastTrigger: TimeInterval = 0
  private var peekTimer: Timer?
  private var peekModifier: NSEvent.ModifierFlags = []
  private var isInCorner = false

  init(settings: LullSettings, handler: @escaping (Gesture) -> Void) {
    self.settings = settings
    self.handler = handler
  }

  /// Installs or removes the monitors to match the setting.
  func update() {
    let isNeeded = settings.isShakeEnabled || settings.peeksAtCorners
    if isNeeded, globalMonitor == nil {
      // Keep strong references: a monitor that is not retained stops silently.
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
        // Events for other apps carry screen coordinates.
        self?.moved(to: event.locationInWindow.x, at: event.timestamp, holding: event.modifierFlags)
      }
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
        let x = event.window?.convertPoint(toScreen: event.locationInWindow).x ?? event.locationInWindow.x
        self?.moved(to: x, at: event.timestamp, holding: event.modifierFlags)
        return event
      }
      Log.info(.gesture, "pointer gestures on")
    } else if !isNeeded, let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
      if let localMonitor {
        NSEvent.removeMonitor(localMonitor)
      }
      globalMonitor = nil
      localMonitor = nil
      endPeek()
      Log.info(.gesture, "pointer gestures off")
    }
    if !settings.peeksAtCorners, isInCorner {
      isInCorner = false
      handler(.peekEnded)
    }
  }

  /// Peeks while the pointer rests in any corner of any display.
  private func checkCorners() {
    let point = NSEvent.mouseLocation
    let reach: CGFloat = 5
    let inCorner = NSScreen.screens.contains { screen in
      let frame = screen.frame
      let nearX = point.x <= frame.minX + reach || point.x >= frame.maxX - reach
      let nearY = point.y <= frame.minY + reach || point.y >= frame.maxY - reach
      return frame.insetBy(dx: -1, dy: -1).contains(point) && nearX && nearY
    }
    guard inCorner != isInCorner else { return }
    isInCorner = inCorner
    Log.info(.gesture, inCorner ? "corner: peek" : "corner: left")
    handler(inCorner ? .peekBegan : .peekEnded)
  }

  private func moved(to x: CGFloat, at time: TimeInterval, holding flags: NSEvent.ModifierFlags) {
    if settings.peeksAtCorners {
      checkCorners()
    }
    guard settings.isShakeEnabled else { return }
    let delta = x - lastX
    lastX = x
    guard abs(delta) >= 1 else { return }
    let newDirection: CGFloat = delta > 0 ? 1 : -1
    guard newDirection != direction else { return }

    // Higher sensitivity needs shorter strokes and fewer of them.
    let sensitivity = settings.shakeSensitivity
    let minimumStroke = 150 - sensitivity * 110
    let needed = sensitivity > 0.75 ? 3 : (sensitivity > 0.3 ? 4 : 5)
    let window = 0.55

    let stroke = abs(x - strokeStartX)
    strokeStartX = x
    direction = newDirection
    if stroke >= minimumStroke {
      reversals.append(time)
    } else {
      reversals.removeAll()
    }
    reversals.removeAll { time - $0 > window }
    guard reversals.count >= needed, time - lastTrigger > 0.9 else { return }
    reversals.removeAll()
    lastTrigger = time
    recognised(holding: flags)
  }

  private func recognised(holding flags: NSEvent.ModifierFlags) {
    let held = flags.intersection([.control, .option, .shift, .command])
    let peekFlag = flag(for: settings.shakePeekModifier)
    let toggleFlag = flag(for: settings.shakeToggleModifier)

    if let peekFlag, held == peekFlag {
      beginPeek(holding: peekFlag)
    } else if held == (toggleFlag ?? []) {
      Log.info(.gesture, "shake: toggle")
      handler(.toggle)
    }
  }

  private func beginPeek(holding flag: NSEvent.ModifierFlags) {
    guard peekTimer == nil else { return }
    Log.info(.gesture, "shake: peek")
    peekModifier = flag
    handler(.peekBegan)
    // Modifier keys can't be observed globally without Accessibility, so check the
    // key state a few times a second, only while the peek lasts.
    peekTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if !NSEvent.modifierFlags.contains(self.peekModifier) {
          self.endPeek()
        }
      }
    }
  }

  private func endPeek() {
    guard let peekTimer else { return }
    peekTimer.invalidate()
    self.peekTimer = nil
    handler(.peekEnded)
  }

  private func flag(for modifier: GestureModifier) -> NSEvent.ModifierFlags? {
    switch modifier {
    case .none: nil
    case .control: .control
    case .option: .option
    case .shift: .shift
    case .command: .command
    }
  }
}
