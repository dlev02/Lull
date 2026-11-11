import SwiftUI

/// One glass card in the panel. Rows inside it are separated by hairlines.
struct PanelCard<Content: View>: View {
  var isTinted = false
  var spacing: CGFloat = 14
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(isTinted ? .regular.tint(.accentColor) : .regular, in: .rect(cornerRadius: 30))
  }
}

/// The hairline between two rows of a card.
struct RowDivider: View {
  var body: some View {
    Divider()
      .opacity(0.6)
  }
}

/// A row with a title, an optional second line, and a control at the trailing edge.
struct PanelRow<Trailing: View>: View {
  var symbol: String?
  var title: String
  var subtitle: String?
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 12) {
      if let symbol {
        RowSymbol(name: symbol)
      }
      RowTitle(title: title, subtitle: subtitle)
      Spacer(minLength: 8)
      trailing
    }
    .frame(minHeight: 30)
  }
}

struct RowTitle: View {
  var title: String
  var subtitle: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.headline)
      if let subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct RowSymbol: View {
  var name: String

  var body: some View {
    Image(systemName: name)
      .font(.title3)
      .frame(width: 28)
      .accessibilityHidden(true)
  }
}

/// A switch row whose whole label is the toggle's accessible name.
struct ToggleRow: View {
  var symbol: String?
  var title: String
  var subtitle: String?
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 12) {
        if let symbol {
          RowSymbol(name: symbol)
        }
        RowTitle(title: title, subtitle: subtitle)
        Spacer(minLength: 8)
      }
    }
    .toggleStyle(.switch)
    .tint(.accentColor)
    .frame(minHeight: 30)
  }
}

/// A slider row: symbol, name, then a track with a stop at each step, so a value is
/// easy to return to.
struct SliderRow<Leading: View>: View {
  var title: String
  @Binding var value: Double
  var steps = 10
  @ViewBuilder var leading: Leading

  var body: some View {
    HStack(spacing: 12) {
      leading
        .frame(width: 28)
      Text(title)
        .font(.headline)
        .frame(width: 78, alignment: .leading)
      SteppedSlider(title: title, value: $value, steps: steps)
    }
    .frame(minHeight: 30)
  }
}

/// A 0...1 slider that snaps to `steps` equal stops and shows a tick at each.
struct SteppedSlider: View {
  var title: String
  @Binding var value: Double
  var steps: Int

  var body: some View {
    Slider(value: position, in: 0...Double(steps), step: 1) {
      Text(title)
    }
    .labelsHidden()
    .tint(.accentColor)
    .accessibilityValue("\(Int((value * 100).rounded())) percent")
  }

  /// The slider works in whole steps; the setting stays a fraction.
  private var position: Binding<Double> {
    Binding {
      (value * Double(steps)).rounded()
    } set: { step in
      value = step / Double(steps)
    }
  }
}

/// A card that opens to show more rows.
struct DisclosureCard<Content: View>: View {
  var symbol: String
  var title: String
  @State private var isExpanded = false
  @ViewBuilder var content: Content

  var body: some View {
    PanelCard {
      Button {
        withAnimation(.smooth(duration: 0.3)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 12) {
          RowSymbol(name: symbol)
          Text(title)
            .font(.headline)
          Spacer()
          Image(systemName: "chevron.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .frame(minHeight: 30)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

      if isExpanded {
        RowDivider()
        content
      }
    }
  }
}

/// The panel's own button look: a soft filled capsule or circle that brightens under
/// the pointer. Glass is kept for the cards themselves, so buttons inside them don't
/// stack glass on glass.
struct PanelButtonStyle: ButtonStyle {
  enum Shape {
    case capsule, circle
  }

  var shape: Shape = .capsule
  /// For buttons on an accent-coloured card.
  var isOnTint = false

  func makeBody(configuration: Configuration) -> some View {
    PanelButtonBody(configuration: configuration, shape: shape, isOnTint: isOnTint)
  }
}

private struct PanelButtonBody: View {
  let configuration: ButtonStyle.Configuration
  var shape: PanelButtonStyle.Shape
  var isOnTint: Bool
  @State private var isHovered = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let isLit = isHovered || configuration.isPressed
    configuration.label
      .font(.callout.weight(.medium))
      .padding(.horizontal, shape == .circle ? 0 : 14)
      .frame(width: shape == .circle ? 36 : nil, height: shape == .circle ? 36 : 30)
      .background(fill(isLit: isLit), in: shape == .circle ? AnyShape(.circle) : AnyShape(.capsule))
      .contentShape(shape == .circle ? AnyShape(.circle) : AnyShape(.capsule))
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .onHover { isHovered = $0 }
      .animation(.snappy(duration: 0.15), value: isLit)
  }

  private func fill(isLit: Bool) -> AnyShapeStyle {
    if isOnTint {
      return AnyShapeStyle(Color.white.opacity(isLit ? 0.3 : 0.18))
    }
    return isLit ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary)
  }
}

/// A round button holding one symbol, for adding list items.
struct SymbolButton: View {
  var title: String
  var symbol: String
  var action: () -> Void

  var body: some View {
    Button(title, systemImage: symbol, action: action)
      .labelStyle(.iconOnly)
      .buttonStyle(PanelButtonStyle(shape: .circle))
  }
}

/// A bare minus that removes a list item; it brightens under the pointer.
struct RemoveButton: View {
  var title: String
  var action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(title, systemImage: "minus", action: action)
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .font(.body.weight(.semibold))
      .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(width: 30, height: 30)
      .contentShape(.rect)
      .onHover { isHovered = $0 }
  }
}

/// A menu-style picker drawn as plain text with a chevron, at a row's trailing edge.
struct RowPicker<Value: Hashable>: View {
  var title: String
  @Binding var selection: Value
  var options: [Value]
  var label: (Value) -> String

  var body: some View {
    Picker(title, selection: $selection) {
      ForEach(options, id: \.self) { option in
        Text(label(option)).tag(option)
      }
    }
    .pickerStyle(.menu)
    .buttonStyle(.borderless)
    .labelsHidden()
    .fixedSize()
  }
}

/// One key of a shortcut.
struct KeyCap: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.callout.weight(.medium))
      .frame(minWidth: 30, minHeight: 30)
      .padding(.horizontal, text.count > 1 ? 8 : 0)
      .background(.fill.tertiary, in: .capsule)
  }
}

struct AppIcon: View {
  var identity: AppIdentity
  var size: CGFloat = 28

  var body: some View {
    Image(nsImage: identity.icon)
      .resizable()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
