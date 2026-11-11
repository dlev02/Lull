import AppKit

/// The menu bar icon. A click opens the panel or toggles Lull, as the person chose;
/// a right-click always offers a short menu.
final class StatusItemController: NSObject {
  private let model: AppModel
  private let panel: PanelController
  private let quit: () -> Void
  private var item: NSStatusItem?

  init(model: AppModel, panel: PanelController, quit: @escaping () -> Void) {
    self.model = model
    self.panel = panel
    self.quit = quit
  }

  var screen: NSScreen? {
    item?.button?.window?.screen
  }

  /// The icon's frame in screen coordinates.
  var frame: NSRect? {
    guard let button = item?.button, let window = button.window else { return nil }
    return window.convertToScreen(button.convert(button.bounds, to: nil))
  }

  /// Creates, removes or redraws the icon to match the settings.
  func update() {
    if model.settings.menuBarClick == .hidden {
      if let item {
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
      }
      return
    }
    let item = item ?? {
      let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      created.button?.target = self
      created.button?.action = #selector(clicked(_:))
      created.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      created.button?.setAccessibilityLabel(AppInfo.name)
      self.item = created
      return created
    }()
    let isOn = model.settings.isEnabled
    let image = NSImage(systemSymbolName: isOn ? "circle.inset.filled" : "circle", accessibilityDescription: AppInfo.name)
    image?.isTemplate = true
    item.button?.image = image
    item.button?.toolTip = isOn ? "Lull is on" : "Lull is off"
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if wantsMenu {
      showMenu()
    } else if model.settings.menuBarClick == .toggle {
      model.engine.toggle()
    } else {
      panel.toggle(on: screen)
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.addItem(menuItem(model.settings.isEnabled ? "Turn Off" : "Turn On", #selector(toggleFocus)))
    let other = model.settings.mode.next
    menu.addItem(menuItem("Switch to \(other.title)", #selector(switchMode)))
    menu.addItem(.separator())
    menu.addItem(menuItem("Settings…", #selector(openPanel)))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit \(AppInfo.name)", #selector(quitApp)))
    item?.menu = menu
    item?.button?.performClick(nil)
    item?.menu = nil
  }

  private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func toggleFocus() { model.engine.toggle() }
  @objc private func switchMode() { model.engine.switchMode() }
  @objc private func openPanel() { panel.show(on: screen) }
  @objc private func quitApp() { quit() }
}
