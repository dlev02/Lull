import AppKit
import Observation

/// Decides which window is in focus and keeps one overlay per display slotted
/// beneath it. It only does work when something changes: an app switch, a click,
/// a Space or display change, or a setting.
@Observable
final class FocusEngine {
  enum StandDown: String {
    case off, peeking, ignoredApp = "ignored-app", noWindow = "no-window", missionControl = "mission-control"
  }

  let settings: LullSettings

  /// True while the overlays are up.
  private(set) var isActive = false
  private(set) var standDown: StandDown?
  private(set) var frontAppName: String?
  private(set) var frontBundleID: String?
  private(set) var focusedWindowID: CGWindowID?

  /// Held by the peek gesture and `lull peek on`: everything is sharp until released.
  var isPeeking = false {
    didSet {
      guard isPeeking != oldValue else { return }
      evaluate(reason: "peek")
    }
  }

  @ObservationIgnored private var overlays: [CGDirectDisplayID: OverlayPanel] = [:]
  @ObservationIgnored private var mouseMonitor: Any?
  @ObservationIgnored private var followUps: [DispatchWorkItem] = []
  @ObservationIgnored private var lastFrontPID: pid_t?
  @ObservationIgnored private var lastLook: OverlayLook?
  @ObservationIgnored private var lastMode: FocusMode?
  @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier
  @ObservationIgnored private(set) var evaluationCount = 0

  init(settings: LullSettings) {
    self.settings = settings
  }

  func start() {
    settings.onChange = { [weak self] in self?.evaluate(reason: "settings") }

    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didUnhideApplicationNotification,
      NSWorkspace.activeSpaceDidChangeNotification,
    ] {
      workspace.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged(_:)),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(appearanceChanged(_:)),
      name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil
    )
    // Mouse events need no permission. A click is how focus moves between windows
    // of the same app, which no notification reports.
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] _ in
      self?.scheduleFollowUps(reason: "click", delays: [0.04, 0.25])
    }
    evaluate(reason: "start")
    Log.info(.engine, "engine started, enabled=\(settings.isEnabled)")
  }

  @objc private func workspaceChanged(_ notification: Notification) {
    let reason = notification.name.rawValue
      .replacingOccurrences(of: "NSWorkspace", with: "")
      .replacingOccurrences(of: "Notification", with: "")
    evaluate(reason: reason)
    // Window order settles a moment after the notification, most of all on Space changes.
    scheduleFollowUps(reason: reason + "+settle", delays: [0.08, 0.35])
  }

  @objc private func screensChanged(_ notification: Notification) {
    evaluate(reason: "screens")
    scheduleFollowUps(reason: "screens+settle", delays: [0.5])
  }

  @objc private func appearanceChanged(_ notification: Notification) {
    // The app's own appearance updates a beat after the system announces the switch.
    scheduleFollowUps(reason: "appearance", delays: [0.3])
  }

  private func scheduleFollowUps(reason: String, delays: [TimeInterval]) {
    followUps.forEach { $0.cancel() }
    followUps = delays.map { delay in
      let item = DispatchWorkItem { [weak self] in self?.evaluate(reason: reason) }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
      return item
    }
  }

  // MARK: - Evaluation

  /// Reads the window list once and puts every overlay where it belongs.
  func evaluate(reason: String) {
    evaluationCount += 1
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.processIdentifier != ownPID {
      lastFrontPID = front.processIdentifier
      frontAppName = front.localizedName
      frontBundleID = front.bundleIdentifier
    }

    guard settings.isEnabled else { return hideAll(.off, reason: reason) }
    guard !isPeeking else { return hideAll(.peeking, reason: reason) }
    if let frontBundleID, settings.ignoredBundleIDs.contains(frontBundleID) {
      return hideAll(.ignoredApp, reason: reason)
    }
    guard let frontPID = lastFrontPID else { return hideAll(.noWindow, reason: reason) }

    let snapshot = WindowSnapshot.capture(ownPID: ownPID)
    guard let focused = snapshot.candidates.first(where: { $0.pid == frontPID }) else {
      return hideAll(.noWindow, reason: reason)
    }

    let sharpPIDs = sharpProcessIDs(frontPID: frontPID)
    func isSharp(_ window: WindowInfo) -> Bool {
      window.id == focused.id || sharpPIDs.contains(window.pid)
    }

    syncOverlays()
    let look = currentLook()
    // Switching mode eases between strengths; slider drags apply at once.
    let animateLook = isActive && lastMode != nil && lastMode != settings.mode
    let duration = settings.transitionDuration

    for (displayID, panel) in overlays {
      let displayBounds = CGDisplayBounds(displayID)
      let onDisplay = snapshot.candidates.filter { displayBounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }

      // The overlay goes beneath the rearmost window that should stay sharp.
      let anchor: WindowInfo?
      switch settings.screenMode {
      case .global:
        anchor = snapshot.candidates.last(where: isSharp)
      case .perScreen:
        anchor = onDisplay.last(where: isSharp) ?? onDisplay.first
      }

      var coverage = CGRect(origin: .zero, size: displayBounds.size)
      if !settings.blursStageManager, let strip = snapshot.stripColumn(on: displayBounds) {
        // Leave Stage Manager's strip uncovered so its thumbnails stay sharp.
        let local = strip.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        if local.minX <= 0 {
          coverage.origin.x = local.maxX
          coverage.size.width -= local.maxX
        } else {
          coverage.size.width = local.minX
        }
      }
      panel.apply(look, coverage: coverage, animated: animateLook, duration: duration)

      if !isSlotted(panel, beneath: anchor, in: snapshot) {
        panel.slot(beneath: anchor?.id)
      }
      panel.fadeIn(duration: duration)
    }

    if !isActive || focusedWindowID != focused.id {
      Log.info(.engine, "focus \(frontAppName ?? "?") window \(focused.id) (\(reason)), sharp apps \(sharpPIDs.count)")
    }
    lastLook = look
    lastMode = settings.mode
    focusedWindowID = focused.id
    standDown = nil
    isActive = true
  }

  /// Apps whose every window stays sharp: the front app when app-wide focus is on,
  /// plus every running member of a group the front app belongs to.
  private func sharpProcessIDs(frontPID: pid_t) -> Set<pid_t> {
    var pids: Set<pid_t> = []
    if settings.isAppWideFocus {
      pids.insert(frontPID)
    }
    if let frontBundleID {
      let partners = Set(settings.groups.filter { $0.contains(frontBundleID) }.flatMap { $0 })
      if !partners.isEmpty {
        for app in NSWorkspace.shared.runningApplications {
          if let bundleID = app.bundleIdentifier, partners.contains(bundleID) {
            pids.insert(app.processIdentifier)
          }
        }
      }
    }
    return pids
  }

  /// True when the panel already sits directly beneath the anchor, with no other
  /// app's window between them, so it need not be moved.
  private func isSlotted(_ panel: OverlayPanel, beneath anchor: WindowInfo?, in snapshot: WindowSnapshot) -> Bool {
    guard panel.isVisible else { return false }
    let panelID = CGWindowID(panel.windowNumber)
    guard let panelIndex = snapshot.ordered.firstIndex(where: { $0.id == panelID }) else { return false }
    guard let anchor else {
      return !snapshot.ordered[(panelIndex + 1)...].contains { $0.pid != ownPID && $0.owner != WindowSnapshot.stageManagerOwner && $0.alpha > 0.01 }
    }
    guard let anchorIndex = snapshot.ordered.firstIndex(where: { $0.id == anchor.id }), anchorIndex < panelIndex else {
      return false
    }
    return !snapshot.ordered[(anchorIndex + 1)..<panelIndex].contains { $0.pid != ownPID }
  }

  private func hideAll(_ why: StandDown, reason: String) {
    if isActive || standDown != why {
      Log.info(.engine, "stand down: \(why.rawValue) (\(reason))")
    }
    for panel in overlays.values {
      panel.fadeOut(duration: settings.transitionDuration)
    }
    standDown = why
    isActive = false
    focusedWindowID = nil
  }

  // MARK: - Overlays and look

  private func syncOverlays() {
    var seen: Set<CGDirectDisplayID> = []
    for screen in NSScreen.screens {
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
      let displayID = CGDirectDisplayID(number.uint32Value)
      seen.insert(displayID)
      if let panel = overlays[displayID] {
        if panel.frame != screen.frame {
          panel.setFrame(screen.frame, display: false)
        }
      } else {
        overlays[displayID] = OverlayPanel(screen: screen, displayID: displayID)
      }
    }
    for (displayID, panel) in overlays where !seen.contains(displayID) {
      panel.orderOut(nil)
      overlays[displayID] = nil
      Log.info(.overlay, "display \(displayID) removed")
    }
  }

  /// The sliders set the look once; the mode is a strength on top of them.
  func currentLook() -> OverlayLook {
    var look = OverlayLook()
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    switch settings.mode {
    case .ambient:
      look.blurRadius = settings.blur * 12
      look.veilOpacity = 0.03 + settings.blur * 0.05
    case .deep:
      look.blurRadius = settings.blur * 60
      look.veilOpacity = 0.08 + settings.blur * 0.10
    }
    // Quarter-resolution sampling halves the cost and is invisible once the blur is
    // soft enough; a very light blur needs more resolution to stay smooth.
    look.scale = look.blurRadius >= 6 ? 0.25 : 0.5
    look.veilColor = isDark ? .black : .white
    if !isDark {
      look.veilOpacity *= 1.6
    }
    look.saturation = settings.isMonochrome ? 0 : 1
    look.tintColor = (NSColor(hex: settings.tintColor) ?? .black).cgColor
    look.tintOpacity = settings.tint * 0.6
    look.grainOpacity = settings.grain * 0.22
    // Developer overrides from `lull tune`, for measuring cost against quality.
    if let value = tuning["scale"] { look.scale = value }
    if let value = tuning["radius"] { look.blurRadius = value }
    if let value = tuning["veil"] { look.veilOpacity = value }
    if let value = tuning["grain"] { look.grainOpacity = value }
    return look
  }

  /// Temporary look overrides; not saved.
  @ObservationIgnored var tuning: [String: Double] = [:] {
    didSet { evaluate(reason: "tune") }
  }

  var blurBackend: String {
    overlays.values.first?.backend.rawValue ?? (SystemBlur.isAvailable ? "backdrop" : "material")
  }

  var overlayCount: Int { overlays.count }

  // MARK: - Actions shared by every control surface

  func toggle() {
    settings.isEnabled.toggle()
  }

  func switchMode() {
    settings.mode = settings.mode.next
  }

  /// Adds the front app to the ignored list, or removes it if it is already there.
  @discardableResult
  func toggleIgnoreFrontApp() -> Bool {
    guard let frontBundleID else { return false }
    if let index = settings.ignoredBundleIDs.firstIndex(of: frontBundleID) {
      settings.ignoredBundleIDs.remove(at: index)
      return false
    }
    settings.ignoredBundleIDs.append(frontBundleID)
    return true
  }
}

extension NSColor {
  /// Parses "#RRGGBB" or "RRGGBB".
  convenience init?(hex: String) {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") {
      text.removeFirst()
    }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    self.init(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }

  var hexString: String {
    guard let color = usingColorSpace(.sRGB) else { return "#000000" }
    return String(
      format: "#%02X%02X%02X",
      Int((color.redComponent * 255).rounded()),
      Int((color.greenComponent * 255).rounded()),
      Int((color.blueComponent * 255).rounded())
    )
  }
}
