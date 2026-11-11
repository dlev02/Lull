import AppKit
import SwiftUI

/// The settings panel: a column of glass cards under the menu bar at the right edge
/// of the screen. It fades in place and never activates the app, so the window the
/// person was working in stays in focus while they adjust things.
final class PanelController {
  static let width: CGFloat = 316

  private let model: AppModel
  private var panel: NSPanel?
  private var outsideMonitor: Any?
  private var keyMonitor: Any?
  private(set) var isVisible = false

  init(model: AppModel) {
    self.model = model
    model.closePanel = { [weak self] in self?.hide() }
  }

  func toggle(on screen: NSScreen?) {
    isVisible ? hide() : show(on: screen)
  }

  func show(on screen: NSScreen?) {
    guard !isVisible, let screen = screen ?? NSScreen.main else { return }
    let panel = panel ?? makePanel()
    self.panel = panel
    model.refresh()

    let visible = screen.visibleFrame
    panel.setFrame(
      NSRect(x: visible.maxX - PanelController.width - 6, y: visible.minY, width: PanelController.width, height: visible.height),
      display: true
    )
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
    }
    isVisible = true

    // A click anywhere outside the panel closes it, like Control Centre.
    outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      self?.hide()
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKey(event) ?? event
    }
    Log.debug(.app, "panel shown")
  }

  func hide() {
    guard isVisible, let panel else { return }
    isVisible = false
    model.finishRecording(nil)
    for monitor in [outsideMonitor, keyMonitor].compactMap({ $0 }) {
      NSEvent.removeMonitor(monitor)
    }
    outsideMonitor = nil
    keyMonitor = nil
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isVisible else { return }
        panel.orderOut(nil)
      }
    }
  }

  private func handleKey(_ event: NSEvent) -> NSEvent? {
    let escape: UInt16 = 53
    if model.recordingAction != nil {
      if event.keyCode == escape {
        model.finishRecording(nil)
        return nil
      }
      let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
      // A global shortcut needs Control, Option or Command, or it would swallow typing.
      guard !modifiers.intersection([.control, .option, .command]).isEmpty else {
        NSSound.beep()
        return nil
      }
      model.finishRecording(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
      return nil
    }
    if event.keyCode == escape {
      hide()
      return nil
    }
    return event
  }

  private func makePanel() -> NSPanel {
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: PanelController.width, height: 600),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.animationBehavior = .none
    // Take every event over the panel's column, including the clear gaps between
    // cards. Left automatic, scrolling over a gap went to the window underneath, which
    // made the panel scroll in fits and starts.
    panel.ignoresMouseEvents = false
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    let host = NSHostingView(rootView: PanelView().environment(model))
    host.sizingOptions = []
    panel.contentView = host
    return panel
  }
}

/// A borderless panel can't take the keyboard unless it says so; the panel needs it
/// for Escape and for recording shortcuts.
private final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}
