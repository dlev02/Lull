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

  /// Called when the overlays go up or come down.
  @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

  /// Held by the peek gesture and `lull peek on`: everything is sharp until released.
  var isPeeking = false {
    didSet {
      guard isPeeking != oldValue else { return }
      evaluate(reason: "peek")
    }
  }

  @ObservationIgnored private var overlays: [CGDirectDisplayID: OverlayPanel] = [:]
  /// One per display, behind every window. It blurs the wallpaper that shows around
  /// Stage Manager's thumbnails, where the main overlay leaves a hole.
  @ObservationIgnored private var desktopPanels: [CGDirectDisplayID: OverlayPanel] = [:]
  @ObservationIgnored private lazy var windowEvents = WindowEvents { [weak self] in
    self?.evaluate(reason: "window-event")
    self?.scheduleFollowUps(reason: "window-event+settle", delays: [0.12])
  }
  @ObservationIgnored private(set) var usesWindowEvents = false
  @ObservationIgnored private var mouseMonitor: Any?
  @ObservationIgnored private var followUps: [DispatchWorkItem] = []
  @ObservationIgnored private var lastFrontPID: pid_t?
  @ObservationIgnored private var lastLook: OverlayLook?
  @ObservationIgnored private var lastMode: FocusMode?
  @ObservationIgnored private var isConfirmingNoWindow = false
  @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier
  @ObservationIgnored private(set) var evaluationCount = 0

  init(settings: LullSettings) {
    self.settings = settings
  }

  func start() {
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
    usesWindowEvents = windowEvents.start()
    if !usesWindowEvents {
      // Fallback: mouse events need no permission either, and a click is how focus
      // usually moves between windows of the same app.
      mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] _ in
        self?.scheduleFollowUps(reason: "click", delays: [0.04, 0.25])
      }
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

  private func scheduleFollowUps(reason: String, delays: [TimeInterval]) {
    followUps.forEach { $0.cancel() }
    followUps = delays.map { delay in
      let item = DispatchWorkItem { [weak self] in self?.evaluate(reason: reason) }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
      return item
    }
  }

  /// Called whenever a setting changes, to re-apply the look.
  func settingsChanged() {
    evaluate(reason: "settings")
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
    windowEvents.watch(snapshot.candidates.map(\.id))
    // An app with no ordinary window can come to the front: a launcher, a menu bar
    // panel. The window that was in focus stays in focus behind it.
    let frontWindow = snapshot.candidates.first(where: { $0.pid == frontPID })
      ?? snapshot.candidates.first(where: { $0.id == focusedWindowID })
    guard let focused = frontWindow else {
      // A closing app is briefly frontmost with no windows before the next one takes
      // over. Wait a moment before standing down, so the blur does not flash off.
      if isActive, reason != "confirm-no-window" {
        if !isConfirmingNoWindow {
          isConfirmingNoWindow = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isConfirmingNoWindow = false
            self?.evaluate(reason: "confirm-no-window")
          }
        }
        return
      }
      return hideAll(.noWindow, reason: reason)
    }

    let sharpPIDs = sharpProcessIDs(frontPID: focused.pid)
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

      // Stage Manager's thumbnails stay sharp through holes in the main overlay.
      var holes: [CGRect] = []
      if !settings.blursStageManager {
        holes = snapshot.stripRects.filter { displayBounds.intersects($0) }.map { rect in
          // Window bounds have a top-left origin; layers have a bottom-left one.
          CGRect(
            x: rect.minX - displayBounds.minX,
            y: displayBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
          )
        }
      }
      panel.apply(look, holes: holes, animated: animateLook, duration: duration)
      if let desktopPanel = desktopPanels[displayID] {
        if holes.isEmpty {
          desktopPanel.conceal(settings.revealEffect, duration: duration)
        } else {
          desktopPanel.apply(look, holes: holes, animated: animateLook, duration: duration)
          if !desktopPanel.isVisible {
            desktopPanel.orderFrontRegardless()
          }
          desktopPanel.reveal(settings.revealEffect, duration: duration)
        }
      }

      if !isSlotted(panel, beneath: anchor, in: snapshot) {
        panel.slot(beneath: anchor?.id)
      }
      panel.reveal(settings.revealEffect, duration: duration)
    }

    if !isActive || focusedWindowID != focused.id {
      Log.info(.engine, "focus \(frontAppName ?? "?") window \(focused.id) (\(reason)), sharp apps \(sharpPIDs.count)")
    }
    lastLook = look
    lastMode = settings.mode
    focusedWindowID = focused.id
    standDown = nil
    if !isActive {
      isActive = true
      onActiveChange?(true)
    }
  }

  /// Apps whose every window stays sharp: the front app when app-wide focus is on,
  /// plus every running member of a group the front app belongs to.
  private func sharpProcessIDs(frontPID: pid_t) -> Set<pid_t> {
    var pids: Set<pid_t> = []
    if settings.isAppWideFocus {
      pids.insert(frontPID)
    }
    if let bundleID = NSRunningApplication(processIdentifier: frontPID)?.bundleIdentifier {
      let partners = Set(settings.groups.filter { $0.contains(bundleID) }.flatMap { $0 })
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
    for panel in Array(overlays.values) + Array(desktopPanels.values) {
      panel.conceal(settings.revealEffect, duration: settings.transitionDuration)
    }
    standDown = why
    if isActive {
      isActive = false
      onActiveChange?(false)
    }
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
          desktopPanels[displayID]?.setFrame(screen.frame, display: false)
        }
      } else {
        overlays[displayID] = OverlayPanel(screen: screen, displayID: displayID, placement: .beneathFocus)
        desktopPanels[displayID] = OverlayPanel(screen: screen, displayID: displayID, placement: .behindWindows)
      }
    }
    for (displayID, panel) in overlays where !seen.contains(displayID) {
      panel.orderOut(nil)
      desktopPanels[displayID]?.orderOut(nil)
      overlays[displayID] = nil
      desktopPanels[displayID] = nil
      Log.info(.overlay, "display \(displayID) removed")
    }
    windowEvents.ownWindowIDs = Set((Array(overlays.values) + Array(desktopPanels.values)).map { UInt32($0.windowNumber) })
  }

  /// The sliders set the look once; the mode is a strength on top of them.
  func currentLook() -> OverlayLook {
    var look = OverlayLook()
    look.blurRadius = settings.blur * 60
    // Quarter-resolution sampling halves the cost and is invisible once the blur is
    // soft enough; a very light blur needs more resolution to stay smooth.
    look.scale = look.blurRadius >= 6 ? 0.25 : 0.5
    // Ambient leaves the top of the screen clear and reaches full strength about
    // halfway down; Deep covers everything.
    look.fadeDepth = settings.mode == .ambient ? 0.49 : 0
    look.saturation = settings.isMonochrome ? 0 : 1
    look.tintColor = (NSColor(hex: settings.tintColor) ?? .black).cgColor
    look.tintOpacity = settings.tint * 0.6
    look.grainOpacity = settings.grain * 0.22
    // Developer overrides from `lull tune`, for measuring cost against quality.
    if let value = tuning["scale"] { look.scale = value }
    if let value = tuning["radius"] { look.blurRadius = value }
    if let value = tuning["grain"] { look.grainOpacity = value }
    if let value = tuning["fade"] { look.fadeDepth = value }
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
