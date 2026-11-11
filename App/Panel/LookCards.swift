import SwiftUI

/// Blur, tint and grain.
struct LookCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard {
      SliderRow(title: "Blur", value: $settings.blur) {
        Image(systemName: "drop.fill")
          .accessibilityHidden(true)
      }
      SliderRow(title: "Tint", value: $settings.tint) {
        TintSwatch()
      }
      SliderRow(title: "Grain", value: $settings.grain) {
        Image(systemName: "water.waves")
          .accessibilityHidden(true)
      }
    }
  }
}

/// Monochrome and the speed of the fade.
struct FinishCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard {
      ToggleRow(symbol: "circle.lefthalf.filled", title: "Monochrome", isOn: $settings.isMonochrome)
      SliderRow(title: "Transition", value: $settings.transition) {
        Image(systemName: "timer")
          .accessibilityHidden(true)
      }
      PanelRow(symbol: "sparkles", title: "Reveal effect") {
        Picker("Reveal effect", selection: $settings.revealEffect) {
          ForEach(RevealEffect.allCases, id: \.self) { effect in
            Text(effect.title).tag(effect)
          }
        }
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .labelsHidden()
        .fixedSize()
      }
    }
  }
}
