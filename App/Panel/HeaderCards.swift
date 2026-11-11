import SwiftUI

/// Shown on first launch and from Show Intro.
struct IntroCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PanelCard(isTinted: true) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      Text("A quieter screen")
        .font(.title2.weight(.semibold))
      Text("Lull softens everything except the window you're working in.")
      Text("Shake the pointer to turn it on or off. Hold Shift and shake to peek.")
      Button {
        model.dismissIntro()
      } label: {
        Text("Got it")
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PanelButtonStyle(isOnTint: true))
      .padding(.top, 4)
    }
    .foregroundStyle(.white)
  }
}

/// The app in front, with a one-tap way to ignore it or stop ignoring it.
struct CurrentAppCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let bundleID = model.engine.frontBundleID
    let isIgnored = bundleID.map(model.settings.ignoredBundleIDs.contains) ?? false
    Button {
      if let bundleID {
        model.toggleIgnore(bundleID)
      }
    } label: {
      HStack(spacing: 12) {
        if let bundleID {
          AppIcon(identity: .lookup(bundleID), size: 36)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(isIgnored ? "Ignored" : "Ignore")
            .font(.headline)
          Text(model.engine.frontAppName ?? "No app")
            .font(.caption)
            .opacity(0.75)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        Image(systemName: isIgnored ? "minus" : "plus")
          .font(.body.weight(.semibold))
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 62)
      .foregroundStyle(isIgnored ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .glassEffect(isIgnored ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
    .disabled(bundleID == nil)
    .accessibilityLabel(isIgnored ? "Stop ignoring \(model.engine.frontAppName ?? "app")" : "Ignore \(model.engine.frontAppName ?? "app")")
  }
}

/// Turns Lull on and off.
struct PowerButton: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    Toggle(isOn: $settings.isEnabled) {
      Label("Lull", systemImage: "power")
        .labelStyle(.iconOnly)
        .font(.title2.weight(.medium))
        .frame(width: 62, height: 62)
        .foregroundStyle(settings.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .contentShape(.circle)
    }
    .toggleStyle(.button)
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .accessibilityValue(settings.isEnabled ? "On" : "Off")
  }
}

struct ModeCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    HStack(spacing: 12) {
      // A glowing dot for Ambient, a plain solid one for Deep.
      Circle()
        .fill(.white)
        .frame(width: 16, height: 16)
        .shadow(color: .white.opacity(settings.mode == .ambient ? 0.9 : 0), radius: 5)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        .frame(width: 28)
        .animation(.smooth, value: settings.mode)
        .accessibilityHidden(true)
      Text("Mode")
        .font(.headline)
      Spacer()
      RowPicker(title: "Mode", selection: $settings.mode, options: FocusMode.allCases) { $0.title }
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, minHeight: 62)
    .glassEffect(.regular, in: .capsule)
  }
}
