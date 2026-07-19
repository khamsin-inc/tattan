import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 除外アプリタブ（C-6 / H-5）: ここに載せたアプリからのコピーは履歴に残らない。
struct ExcludedAppsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Copies made in these apps are never recorded."))
                .font(.caption)
                .foregroundStyle(.secondary)

            List(settings.excludedBundleIdentifiers, id: \.self, selection: $selection) { bundleID in
                HStack {
                    Text(appName(for: bundleID))
                    Spacer()
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 180)
            .overlay {
                if settings.excludedBundleIdentifiers.isEmpty {
                    Text(String(localized: "No excluded apps"))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Menu {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                } label: {
                    Label(String(localized: "Add Running App"), systemImage: "plus")
                }
                .fixedSize()

                Button(String(localized: "Choose App…")) { chooseApp() }

                Spacer()

                Button {
                    if let selection {
                        settings.excludedBundleIdentifiers.removeAll { $0 == selection }
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
            }
        }
        .padding(16)
    }

    private func add(_ bundleID: String) {
        guard !settings.excludedBundleIdentifiers.contains(bundleID) else { return }
        settings.excludedBundleIdentifiers.append(bundleID)
    }

    private func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? bundleID, bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}
