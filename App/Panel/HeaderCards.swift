import SwiftUI

/// Shown on first launch and from Show Intro.
struct IntroCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PanelCard(isTinted: true) {
      Image(systemName: "circle.inset.filled")
        .font(.largeTitle)
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
          .padding(.vertical, 4)
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.capsule)
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
          AppIcon(identity: .lookup(bundleID), size: 30)
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
      .frame(maxWidth: .infinity, minHeight: 56)
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
        .font(.title3.weight(.semibold))
        .frame(width: 56, height: 56)
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
      RowSymbol(name: settings.mode == .deep ? "circle.fill" : "circle.lefthalf.filled")
      Text("Mode")
        .font(.headline)
      Spacer()
      Picker("Mode", selection: $settings.mode) {
        ForEach(FocusMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.menu)
      .buttonStyle(.borderless)
      .labelsHidden()
      .fixedSize()
    }
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, minHeight: 56)
    .glassEffect(.regular, in: .capsule)
  }
}
