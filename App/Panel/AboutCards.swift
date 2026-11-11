import SwiftUI

/// Version, updates, start at login, the command line, and housekeeping.
struct AboutCard: View {
  @Environment(AppModel.self) private var model
  @State private var showsCommands = false

  private let commands = [
    "lull toggle",
    "lull mode deep",
    "lull blur 60",
    "lull ignore add Mail",
    "lull status",
    "open lull://toggle",
  ]

  var body: some View {
    PanelCard {
      HStack(alignment: .center, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(AppInfo.name)
              .font(.headline)
            Text(AppInfo.version)
              .foregroundStyle(.secondary)
          }
          if let lastCheck = model.updates.lastCheck {
            Text("Update checked: \(lastCheck, format: .relative(presentation: .named))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if model.updates.isUpdateReady {
          Button("Relaunch to Update") {
            model.updates.relaunchToUpdate()
          }
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.capsule)
        } else if model.updates.isAvailable {
          Button("Check Updates") {
            model.updates.checkNow()
          }
          .buttonStyle(PanelButtonStyle())
          .disabled(!model.updates.canCheck)
        }
      }
      .frame(minHeight: 30)
      if model.updates.isAvailable {
        RowDivider()
        ToggleRow(title: "Automatic updates", isOn: Binding {
          model.updates.checksAutomatically
        } set: { enabled in
          model.updates.checksAutomatically = enabled
        })
      }
      RowDivider()
      ToggleRow(title: "Launch at login", isOn: Binding {
        model.launchesAtLogin
      } set: { enabled in
        model.setLaunchesAtLogin(enabled)
      })
      RowDivider()
      Button {
        withAnimation(.smooth(duration: 0.3)) {
          showsCommands.toggle()
        }
      } label: {
        HStack {
          Text("Scripting Commands")
            .font(.headline)
          Spacer()
          Image(systemName: "chevron.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(showsCommands ? 180 : 0))
        }
        .frame(minHeight: 30)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(showsCommands ? "Expanded" : "Collapsed")

      if showsCommands {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(commands, id: \.self) { command in
            Text(command)
              .font(.callout.monospaced())
              .textSelection(.enabled)
          }
        }
        Button(model.isCommandInstalled ? "lull Command Installed" : "Install lull Command", systemImage: model.isCommandInstalled ? "checkmark" : "terminal") {
          model.installCommand()
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(model.isCommandInstalled)
      }
      RowDivider()
      HStack {
        Button("Show Intro") {
          model.isIntroVisible = true
          model.scrollTarget = "top"
        }
        Spacer()
        Button("Reset All Settings") {
          model.resetAll()
        }
      }
      .buttonStyle(PanelButtonStyle())
    }
  }
}

/// Who made it and where to send feedback.
struct FooterCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PanelCard(isTinted: true) {
      VStack(spacing: 12) {
        HStack(spacing: 4) {
          Text("Made by")
          Link(AppInfo.author, destination: AppInfo.authorURL)
            .underline()
        }
        .font(.callout)
        HStack(spacing: 10) {
          Link("GitHub", destination: AppInfo.repositoryURL)
          Button("Ideas / Issues") {
            model.openIssue()
          }
        }
        .buttonStyle(PanelButtonStyle(isOnTint: true))
        HStack(spacing: 6) {
          Text("© 2026 \(AppInfo.author)")
          Text("·")
          Link("Privacy", destination: AppInfo.privacyURL)
            .underline()
        }
        .font(.caption)
        .opacity(0.8)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
    }
    .foregroundStyle(.white)
  }
}
