import SwiftUI

/// Blur, tint and grain.
struct LookCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard(spacing: 16) {
      SliderRow(title: "Blur", value: $settings.blur) {
        Image(systemName: "drop.fill")
          .font(.title3)
          .accessibilityHidden(true)
      }
      SliderRow(title: "Tint", value: $settings.tint) {
        TintSwatch()
      }
      SliderRow(title: "Grain", value: $settings.grain) {
        Image(systemName: "water.waves")
          .font(.title3)
          .accessibilityHidden(true)
      }
    }
  }
}

/// Monochrome, the speed of the fade, and how the blur arrives.
struct FinishCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard {
      ToggleRow(symbol: "camera.filters", title: "Monochrome", isOn: $settings.isMonochrome)
      RowDivider()
      SliderRow(title: "Transition", value: $settings.transition, steps: 5) {
        Image(systemName: "timer")
          .font(.title3)
          .accessibilityHidden(true)
      }
      RowDivider()
      PanelRow(symbol: "wand.and.sparkles", title: "Reveal effect") {
        RowPicker(title: "Reveal effect", selection: $settings.revealEffect, options: RevealEffect.allCases) { $0.title }
      }
    }
  }
}
