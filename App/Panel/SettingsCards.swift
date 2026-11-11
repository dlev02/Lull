import SwiftUI

/// How focus behaves across windows, displays and Stage Manager.
struct FocusSettingsCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard {
      ToggleRow(title: "App-wide focus", subtitle: "Every window of the app in front", isOn: $settings.isAppWideFocus)
      PanelRow(title: "Multi-screen mode") {
        Picker("Multi-screen mode", selection: $settings.screenMode) {
          ForEach(ScreenMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .labelsHidden()
        .fixedSize()
      }
      ToggleRow(title: "Blur Stage Manager", subtitle: "Cover the thumbnails too", isOn: $settings.blursStageManager)
      PanelRow(title: "Menu bar icon") {
        Picker("Menu bar icon", selection: $settings.menuBarClick) {
          ForEach(MenuBarClick.allCases, id: \.self) { choice in
            Text(choice.title).tag(choice)
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

struct GesturesCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    DisclosureCard(symbol: "cursorarrow.motionlines", title: "Gestures") {
      ToggleRow(title: "Shake gestures", isOn: $settings.isShakeEnabled)
      Group {
        PanelRow(title: "Shake to toggle") {
          Picker("Shake to toggle", selection: $settings.shakeToggleModifier) {
            ForEach(GestureModifier.allCases.filter { $0 == .none || $0 != settings.shakePeekModifier }, id: \.self) { modifier in
              Text(modifier.title).tag(modifier)
            }
          }
          .pickerStyle(.menu)
          .buttonStyle(.borderless)
          .labelsHidden()
          .fixedSize()
        }
        PanelRow(title: "Hold + shake to peek") {
          Picker("Hold and shake to peek", selection: $settings.shakePeekModifier) {
            ForEach(GestureModifier.allCases.filter { $0 == .none || $0 != settings.shakeToggleModifier }, id: \.self) { modifier in
              Text(modifier == .none ? "Off" : modifier.title).tag(modifier)
            }
          }
          .pickerStyle(.menu)
          .buttonStyle(.borderless)
          .labelsHidden()
          .fixedSize()
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Sensitivity")
            .font(.headline)
          Slider(value: $settings.shakeSensitivity, in: 0...1) {
            Text("Sensitivity")
          } minimumValueLabel: {
            Text("Low").font(.caption).foregroundStyle(.secondary)
          } maximumValueLabel: {
            Text("High").font(.caption).foregroundStyle(.secondary)
          }
          .labelsHidden()
          .tint(.accentColor)
        }
      }
      .disabled(!settings.isShakeEnabled)
    }
  }
}

struct ShortcutsCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    DisclosureCard(symbol: "command", title: "Shortcuts") {
      ForEach(ShortcutAction.allCases) { action in
        ShortcutRow(action: action)
      }
    }
  }
}

/// One action's shortcut, with buttons to record a new one or remove it.
private struct ShortcutRow: View {
  @Environment(AppModel.self) private var model
  var action: ShortcutAction

  var body: some View {
    let shortcut = model.hotKeys.shortcuts[action]
    let isRecording = model.recordingAction == action
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        Text(action.title)
          .font(.headline)
        if isRecording {
          Text("Press a shortcut…")
            .foregroundStyle(.tint)
            .frame(minHeight: 30)
        } else if let shortcut {
          HStack(spacing: 4) {
            ForEach(shortcut.keyCaps, id: \.self) { cap in
              KeyCap(text: cap)
            }
          }
          .accessibilityElement()
          .accessibilityLabel(shortcut.spokenDescription)
        } else {
          Text("None")
            .foregroundStyle(.secondary)
            .frame(minHeight: 30)
        }
      }
      Spacer(minLength: 4)
      Button(isRecording ? "Cancel" : "Change Shortcut", systemImage: isRecording ? "xmark" : "pencil") {
        if isRecording {
          model.finishRecording(nil)
        } else {
          model.beginRecording(action)
        }
      }
      Button("Remove Shortcut", systemImage: "trash") {
        model.hotKeys.set(nil, for: action)
      }
      .disabled(shortcut == nil || isRecording)
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
  }
}
