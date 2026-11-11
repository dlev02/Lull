import SwiftUI

/// One glass card in the panel.
struct PanelCard<Content: View>: View {
  var isTinted = false
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      content
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(isTinted ? .regular.tint(.accentColor) : .regular, in: .rect(cornerRadius: 26))
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
      .font(.body.weight(.medium))
      .frame(width: 24)
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
  }
}

/// A slider row: symbol, name, then the track filling the rest.
struct SliderRow<Leading: View>: View {
  var title: String
  @Binding var value: Double
  @ViewBuilder var leading: Leading

  var body: some View {
    HStack(spacing: 12) {
      leading
        .frame(width: 24)
      Text(title)
        .font(.headline)
        .frame(width: 74, alignment: .leading)
      Slider(value: $value, in: 0...1) {
        Text(title)
      }
      .labelsHidden()
      .tint(.accentColor)
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
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

      if isExpanded {
        content
      }
    }
  }
}

/// A small round button holding one symbol, for adding and removing list items.
struct SymbolButton: View {
  var title: String
  var symbol: String
  var action: () -> Void

  var body: some View {
    Button(title, systemImage: symbol, action: action)
      .labelStyle(.iconOnly)
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
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
      .background(.quaternary, in: .rect(cornerRadius: 9))
  }
}

struct AppIcon: View {
  var identity: AppIdentity
  var size: CGFloat = 26

  var body: some View {
    Image(nsImage: identity.icon)
      .resizable()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
