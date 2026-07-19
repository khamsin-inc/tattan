import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Data ペイン: iCloud 同期（E 系）とバックアップ（M-1 インポート/エクスポート）を
/// 「データの扱い」として 1 箇所に集約（2026-06-12 Ken の構成案）。
/// 同期 ON/OFF の反映は再起動方式（2026-06-12 裁定 / §4.5）。
struct DataSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(ImportExportService.self) private var importExport
    @Environment(SyncResetService.self) private var syncReset

    @State private var confirmingChange = false
    @State private var pendingEnabled = false
    @State private var includeHistoryInExport = false
    @State private var resultMessage: String?
    @State private var confirmingReset = false
    @State private var pendingResetDirection = SyncResetService.Direction.replaceCloud
    @State private var resetResultMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent(String(localized: "iCloud Sync")) {
                    Text(statusLabel)
                        .foregroundStyle(.secondary)
                }
                // 同期の生存確認（2026-07-18「詰まっても気付けない」事故対策）。
                // 最終同期が古いまま止まっていることが、ユーザーに見える唯一の手がかり
                if sync.isSyncEnabled {
                    LabeledContent(String(localized: "Last Synced")) {
                        if let lastSyncedAt = sync.lastSyncedAt {
                            Text(lastSyncedAt, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "Not yet"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if sync.isLikelyFailing {
                        Label {
                            Text(String(localized: """
                            Sync keeps failing. Last error: \(sync.lastErrorMessage ?? "")
                            """))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        .font(.caption)
                    }
                }
                Button(sync.isSyncEnabled
                       ? String(localized: "Turn Off Sync…")
                       : String(localized: "Turn On Sync…")) {
                    pendingEnabled = !sync.isSyncEnabled
                    confirmingChange = true
                }
                .confirmationDialog(
                    String(localized: "Relaunch to apply?"),
                    isPresented: $confirmingChange
                ) {
                    Button(String(localized: "Relaunch Now")) {
                        sync.setSyncEnabled(pendingEnabled)
                    }
                } message: {
                    Text(String(localized: "Tattan will relaunch to apply the sync setting."))
                }
            } footer: {
                Text(String(localized: """
                Snippets always sync. History items sync too, except oversized items and \
                detected credit card numbers, which never leave this Mac.
                """))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $settings.syncSizeThresholdMB, in: 1...100) {
                    Text(String(localized: "Don't sync items larger than \(settings.syncSizeThresholdMB) MB"))
                }
            } footer: {
                // 2026-06-12 裁定 #3: 閾値変更は既存項目に遡及しない（キャプチャ時判定）
                Text(String(localized: "Applies to newly copied items. Existing items are not re-evaluated."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Backup")) {
                Toggle(String(localized: "Include history in export"), isOn: $includeHistoryInExport)
                HStack {
                    Button(String(localized: "Export…")) { runExport() }
                    Button(String(localized: "Import…")) { runImport() }
                }
                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if sync.isSyncEnabled {
                resetSection
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task { await sync.refreshAccountStatus() }
    }

    /// 同期リセット（詰んだ同期の復旧手段）。同期 ON のときだけ表示する
    private var resetSection: some View {
        Section {
            Button(String(localized: "Replace iCloud Data with This Mac's Data…"), role: .destructive) {
                pendingResetDirection = .replaceCloud
                confirmingReset = true
            }
            Button(String(localized: "Replace This Mac's Data with iCloud Data…"), role: .destructive) {
                pendingResetDirection = .replaceLocal
                confirmingReset = true
            }
            if syncReset.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            if let resetResultMessage {
                Text(resetResultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "Reset Sync"))
        } footer: {
            Text(String(localized: """
            Use these if sync is stuck. A JSON backup of all data is saved to your \
            Downloads folder before anything is changed, and Tattan relaunches to \
            apply the reset.
            """))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(syncReset.isWorking)
        .confirmationDialog(resetDialogTitle, isPresented: $confirmingReset) {
            Button(String(localized: "Back Up and Reset"), role: .destructive) {
                runReset(pendingResetDirection)
            }
        } message: {
            Text(resetDialogMessage)
        }
    }

    private var resetDialogTitle: String {
        switch pendingResetDirection {
        case .replaceCloud:
            String(localized: "Replace iCloud data?")
        case .replaceLocal:
            String(localized: "Replace this Mac's data?")
        }
    }

    private var resetDialogMessage: String {
        switch pendingResetDirection {
        case .replaceCloud:
            // 他機が起動中だとゾーン削除を検知してローカルデータを再アップロードし、
            // 「まっさら」が無効化される（和集合マージ）。2026-07-18 の実戦で確認した事故
            String(localized: """
            All Tattan data in iCloud will be deleted and rebuilt from this Mac's data. \
            On each of your other Macs, run "Replace This Mac's Data with iCloud Data" \
            afterward — other Macs running Tattan may write their old data back to iCloud.
            """)
        case .replaceLocal:
            String(localized: """
            This Mac's snippets and synced history will be discarded and downloaded \
            again from iCloud. Locally excluded items are kept.
            """)
        }
    }

    private func runReset(_ direction: SyncResetService.Direction) {
        Task {
            do {
                try await syncReset.reset(direction)
            } catch {
                resetResultMessage = String(localized: "Reset failed: \(error.localizedDescription)")
            }
        }
    }

    private var statusLabel: String {
        switch sync.displayStatus {
        case .enabled:
            String(localized: "On")
        case .disabled:
            String(localized: "Off")
        case .enabledButDegraded:
            String(localized: "On — currently unavailable, running locally")
        case .noAccount:
            String(localized: "Off — sign in to iCloud to enable")
        }
    }

    // MARK: - バックアップ操作（M-1）

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tattan-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try importExport.exportData(includeHistory: includeHistoryInExport)
            try data.write(to: url)
            resultMessage = String(localized: "Exported successfully.")
        } catch {
            resultMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // importData は前処理を背景で行う async API。UI を塞がないよう Task で呼ぶ
        Task {
            do {
                let data = try Data(contentsOf: url)
                try await importExport.importData(data)
                resultMessage = String(localized: "Imported successfully.")
            } catch {
                resultMessage = String(localized: "Import failed: \(error.localizedDescription)")
            }
        }
    }
}
