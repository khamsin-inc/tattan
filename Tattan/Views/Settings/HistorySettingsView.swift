import SwiftUI

/// 履歴タブ: 保存上限（H-4, N-1）/ 自動削除（C-7, N-2）/ 全消去
struct HistorySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(HistoryService.self) private var history
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Stepper(value: $settings.historyLimit, in: 10...1000, step: 10) {
                Text(String(localized: "Keep up to \(settings.historyLimit) items"))
            }
            // 上限を下げたら即座に刈り込む。従来は次のコピーまで超過分が残っていた
            // （2026-07-02 レビュー指摘 #14）
            .onChange(of: settings.historyLimit) { _, _ in
                history.enforceLimit()
            }

            Section {
                Toggle(String(localized: "Automatically delete old items"), isOn: $settings.autoDeleteEnabled)
                Stepper(value: $settings.autoDeleteDays, in: 1...365) {
                    Text(String(localized: "Delete after \(settings.autoDeleteDays) days"))
                }
                .disabled(!settings.autoDeleteEnabled)
            } footer: {
                // 2026-06-12 裁定 #2: 削除も同期されるため、実効上限は全 Mac の最小設定値になる
                Text(String(localized:
                    "Deletions sync across Macs — the effective limit is the smallest configured on any Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(String(localized: "Clear All History…"), role: .destructive) {
                    confirmingClear = true
                }
                .confirmationDialog(
                    String(localized: "Clear all history?"),
                    isPresented: $confirmingClear
                ) {
                    Button(String(localized: "Clear History"), role: .destructive) {
                        history.deleteAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
