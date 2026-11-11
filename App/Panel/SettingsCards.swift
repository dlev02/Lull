import SwiftUI

/// How focus behaves across windows, displays and Stage Manager.
struct FocusSettingsCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    PanelCard {
      ToggleRow(title: "App-wide focus", subtitle: "Every window of the app in front", isOn: $settings.isAppWideFocus)
      RowDivider()
      PanelRow(title: "Multi-screen mode") {
        RowPicker(title: "Multi-screen mode", selection: $settings.screenMode, options: ScreenMode.allCases) { $0.title }
      }
      RowDivider()
      PanelRow(title: "Auto-hide", subtitle: "While Lull is focusing") {
        RowPicker(title: "Auto-hide", selection: $settings.autoHide, options: AutoHide.allCases) { $0.title }
      }
      RowDivider()
      ToggleRow(title: "Blur Stage Manager", subtitle: "Cover the thumbnails too", isOn: $settings.blursStageManager)
      RowDivider()
      PanelRow(title: "Menu bar icon") {
        RowPicker(title: "Menu bar icon", selection: $settings.menuBarClick, options: MenuBarClick.allCases) { $0.title }
      }
    }
  }
}

struct GesturesCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    DisclosureCard(symbol: "computermouse.fill", title: "Gestures") {
      ToggleRow(title: "Shake gestures", isOn: $settings.isShakeEnabled)
      Group {
        PanelRow(title: "Shake to toggle") {
          // A modifier can't do both jobs, so the one in use is left out of the other menu.
          RowPicker(
            title: "Shake to toggle",
            selection: $settings.shakeToggleModifier,
            options: GestureModifier.allCases.filter { $0 == .none || $0 != settings.shakePeekModifier }
          ) { $0.title }
        }
        PanelRow(title: "Hold + shake to peek") {
          RowPicker(
            title: "Hold and shake to peek",
            selection: $settings.shakePeekModifier,
            options: GestureModifier.allCases.filter { $0 == .none || $0 != settings.shakeToggleModifier }
          ) { $0 == .none ? "Off" : $0.title }
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Sensitivity")
            .font(.headline)
          HStack(spacing: 10) {
            Text("Low")
              .font(.caption)
              .foregroundStyle(.secondary)
            SteppedSlider(title: "Sensitivity", value: $settings.shakeSensitivity, steps: 6)
            Text("High")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .disabled(!settings.isShakeEnabled)
      RowDivider()
      ToggleRow(title: "Peek at corners", isOn: $settings.peeksAtCorners)
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
      Group {
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
      .frame(width: 26, height: 30)
    }
  }
}
