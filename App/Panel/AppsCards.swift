import SwiftUI

/// Apps that stay in focus together.
struct AppGroupsCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PanelCard {
      HStack {
        Text("App Groups")
          .font(.headline)
        Spacer()
        SymbolButton(title: "Add Group", symbol: "plus") {
          model.chooseGroup()
        }
      }
      if model.settings.groups.isEmpty {
        Text("Apps that stay in focus together")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(Array(model.settings.groups.enumerated()), id: \.offset) { index, group in
        let members = group.map(AppIdentity.lookup)
        RowDivider()
        HStack(spacing: 10) {
          HStack(spacing: -6) {
            ForEach(members) { member in
              AppIcon(identity: member)
            }
          }
          Text(members.map(\.name).joined(separator: " + "))
            .lineLimit(1)
          Spacer(minLength: 4)
          RemoveButton(title: "Remove Group") {
            model.settings.groups.remove(at: index)
          }
        }
      }
    }
  }
}

/// Apps Lull stands down for.
struct IgnoredAppsCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PanelCard {
      HStack {
        Text("Ignored apps")
          .font(.headline)
        Spacer()
        Menu("Add Ignored App", systemImage: "plus") {
          ForEach(AppIdentity.running.filter { !model.settings.ignoredBundleIDs.contains($0.bundleID) }) { app in
            Button(app.name) {
              model.toggleIgnore(app.bundleID)
            }
          }
          Divider()
          Button("Choose…") {
            model.chooseIgnoredApps()
          }
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .buttonStyle(PanelButtonStyle(shape: .circle))
        .fixedSize()
      }
      ForEach(model.settings.ignoredBundleIDs.map(AppIdentity.lookup)) { app in
        RowDivider()
        HStack(spacing: 12) {
          AppIcon(identity: app)
          Text(app.name)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 4)
          RemoveButton(title: "Stop Ignoring \(app.name)") {
            model.toggleIgnore(app.bundleID)
          }
        }
      }
    }
  }
}
