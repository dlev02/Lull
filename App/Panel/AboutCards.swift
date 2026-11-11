import SwiftUI

/// Version, start at login, the command line, and housekeeping.
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
          .buttonStyle(.glass)
          .buttonBorderShape(.capsule)
          .disabled(!model.updates.canCheck)
        }
      }
      if model.updates.isAvailable {
        ToggleRow(title: "Automatic updates", isOn: Binding {
          model.updates.checksAutomatically
        } set: { enabled in
          model.updates.checksAutomatically = enabled
        })
      }
      Divider()
      ToggleRow(title: "Launch at login", isOn: Binding {
        model.launchesAtLogin
      } set: { enabled in
        model.setLaunchesAtLogin(enabled)
      })
      Divider()
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
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(model.isCommandInstalled)
      }
      Divider()
      HStack {
        Button("Show Intro") {
          model.isIntroVisible = true
        }
        Spacer()
        Button("Reset All Settings") {
          model.resetAll()
        }
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.capsule)
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
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        Text("© 2026 \(AppInfo.author)")
          .font(.caption)
          .opacity(0.7)
      }
      .frame(maxWidth: .infinity)
    }
    .foregroundStyle(.white)
  }
}
