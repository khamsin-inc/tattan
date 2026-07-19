import SwiftUI

/// ショートカットタブ: グローバル 3 枠（P-2）のレコーダー（P-1）+ 権限の注意表示
struct ShortcutSettingsView: View {
    @Environment(HotkeyService.self) private var hotkeys
    @Environment(PermissionService.self) private var permissions
    /// レコーダー変更後に再描画させるためのトリガー
    @State private var revision = 0

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyService.Slot.allCases, id: \.self) { slot in
                    HotkeyRecorderField(
                        title: slot.title,
                        binding: hotkeys.binding(for: slot),
                        onChange: { binding in
                            hotkeys.setBinding(binding, for: slot)
                            revision += 1
                        },
                        duplicateCheck: { hotkeys.duplicateOwner(of: $0, excludingSlot: slot) }
                    )
                }
            } footer: {
                Text(String(localized: "Per-snippet shortcuts are assigned in the snippet editor."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id(revision)

            if !permissions.isAccessibilityTrusted {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized:
                                "Accessibility access is required for modifier double-tap shortcuts and auto-paste."))
                            Button(String(localized: "Open System Settings")) {
                                permissions.promptForAccessibility()
                                permissions.openAccessibilitySettings()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
