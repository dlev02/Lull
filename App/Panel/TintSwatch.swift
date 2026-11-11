import AppKit
import SwiftUI

/// A round colour swatch that opens the system colour panel for the tint.
struct TintSwatch: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Button {
      TintColorPanel.shared.show(current: NSColor(hex: model.settings.tintColor) ?? .black) { color in
        model.settings.tintColor = color.hexString
      }
    } label: {
      Circle()
        .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
        .overlay {
          Circle()
            .fill(Color(nsColor: NSColor(hex: model.settings.tintColor) ?? .black))
            .padding(5)
        }
        .frame(width: 26, height: 26)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Tint colour")
  }
}

/// Bridges the shared colour panel's target/action to a closure.
final class TintColorPanel: NSObject {
  static let shared = TintColorPanel()
  private var onChange: ((NSColor) -> Void)?

  func show(current: NSColor, onChange: @escaping (NSColor) -> Void) {
    self.onChange = onChange
    let panel = NSColorPanel.shared
    panel.showsAlpha = false
    panel.color = current
    panel.setTarget(self)
    panel.setAction(#selector(changed(_:)))
    panel.level = .popUpMenu
    panel.orderFrontRegardless()
  }

  @objc private func changed(_ sender: NSColorPanel) {
    onChange?(sender.color)
  }
}
