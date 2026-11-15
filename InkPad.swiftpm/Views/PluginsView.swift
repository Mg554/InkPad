import SwiftUI

/// The services InkPad can reach: mail, calendars, and the tools the owner
/// keeps their work in. Each plugin is turned on here and then opened from
/// anywhere InkPad can reach it — the sidebar, the command palette, or a
/// note's own menu.
struct PluginsView: View {
    @StateObject private var plugins = PluginStore.shared

    var body: some View {
        List {
            Section {
                ForEach(PluginCatalog.mail) { plugin in
                    row(plugin)
                }
            } header: {
                Label(tr(PluginCategory.mail.title), systemImage: PluginCategory.mail.symbol)
            } footer: {
                Text("Mail plugins open the service on this iPad: the owner writes and sends in Mail, Gmail, Outlook or Fastmail, and InkPad never keeps a copy.")
            }

            Section {
                ForEach(PluginCatalog.calendars) { plugin in
                    row(plugin)
                }
            } header: {
                Label(tr(PluginCategory.calendar.title), systemImage: PluginCategory.calendar.symbol)
            } footer: {
                Text("Calendar plugins open your events — Apple's Calendar, Google Calendar, Outlook or Fantastical. InkPad reads nothing from them.")
            }

            Section {
                ForEach(PluginCatalog.tasks + PluginCatalog.notes) { plugin in
                    row(plugin)
                }
            } header: {
                Label("Tasks and Notes", systemImage: "square.grid.2x2")
            }

            Section {
                ForEach(PluginCatalog.other) { plugin in
                    row(plugin)
                }
            } header: {
                Label(tr(PluginCategory.other.title), systemImage: PluginCategory.other.symbol)
            } footer: {
                Text("More services can be added as InkPad grows; these are the ones that work on the iPad today.")
            }
        }
        .themedBackground()
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ plugin: Plugin) -> some View {
        HStack(spacing: Theme.Spacing.xxl) {
            Image(systemName: plugin.symbol)
                .font(.title3)
                .foregroundStyle(Color.inkAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: Theme.Spacing.x2) {
                Text(plugin.title)
                Text(plugin.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(plugin.links) { link in
                    Button {
                        PluginStore.open(link)
                    } label: {
                        Label(link.title, systemImage: "arrow.up.right.square")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.title3)
            }
            .disabled(!plugins.isEnabled(plugin))
            Toggle("", isOn: Binding(
                get: { plugins.isEnabled(plugin) },
                set: { plugins.setEnabled($0, for: plugin) }
            ))
            .labelsHidden()
        }
    }
}
