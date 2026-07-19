import AppKit
import SwiftUI

/// 一般タブ: ログイン時自動起動（H-1）/ 文字サイズ（F-7, N-4）/ プレビュー文字数（F-9, N-3）
/// / 機密情報トグル（O-3）/ Pasteboard Privacy 警告（O-4）
struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LaunchAtLoginService.self) private var launchAtLogin
    @Environment(PermissionService.self) private var permissions
    @Environment(UpdaterService.self) private var updater
    @State private var languageBeforeChange: AppLanguage?

    var body: some View {
        @Bindable var settings = settings
        Form {
            // ユーザーマニュアル（khamsin.jp に日英で公開予定。2026-07-02 Ken 依頼）。
            // リンク先は表示言語に追従する
            Section {
                Link(destination: manualURL) {
                    Label(String(localized: "User Manual"), systemImage: "book")
                }
            }

            // 言語選択。選択肢は各言語の現地表記（"English" / "日本語"）。
            // 反映は再起動が必要 — NSMenu の項目を含めて Bundle を再ロードしないと切り替わらないため
            Picker(String(localized: "Language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.nativeName).tag(lang)
                }
            }
            .onChange(of: settings.language) { oldValue, newValue in
                guard oldValue != newValue else { return }
                languageBeforeChange = oldValue
            }
            .alert(
                String(localized: "Restart Tattan to apply the new language?"),
                isPresented: Binding(
                    get: { languageBeforeChange != nil },
                    set: { if !$0 { languageBeforeChange = nil } }
                )
            ) {
                Button(String(localized: "Restart Now")) {
                    languageBeforeChange = nil
                    AppRelauncher.relaunch()
                }
                Button(String(localized: "Later"), role: .cancel) {
                    languageBeforeChange = nil
                }
            } message: {
                Text(String(localized:
                    "Menu bar items and existing windows will keep using the previous language until Tattan restarts."))
            }

            Toggle(
                String(localized: "Launch at login"),
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            // Sparkle 自動アップデート（G-4 / K-4）。オフにするとバックグラウンドチェックが止まり、
                            // ネットワーク通信は「Check for Updates…」を押した時だけになる
            Toggle(
                String(localized: "Automatically check for updates"),
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                )
            )

            Picker(String(localized: "Appearance"), selection: $settings.appearance) {
                Text(String(localized: "System")).tag(AppearancePreference.system)
                Text(String(localized: "Light")).tag(AppearancePreference.light)
                Text(String(localized: "Dark")).tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(String(localized: "Text size"))
                Slider(value: $settings.uiScale, in: 0.7...2.0, step: 0.05)
                Text("\(Int((settings.uiScale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }

            Stepper(value: $settings.previewLength, in: 10...500, step: 10) {
                Text(String(localized: "Preview length: \(settings.previewLength) characters"))
            }

            HStack {
                Text(String(localized: "Popup width"))
                Slider(
                    value: Binding(
                        get: { Double(settings.popupWidth) },
                        set: { settings.popupWidth = Int($0) }
                    ),
                    in: 280...800,
                    step: 20
                )
                Text("\(settings.popupWidth) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }

            Section {
                Toggle(
                    String(localized: "Don't record sensitive content"),
                    isOn: $settings.skipConcealedContent
                )
            } footer: {
                Text(String(localized: """
                Skip clipboard items that password managers and other apps mark as confidential \
                (e.g., passwords). When off, those items are kept locally only and never synced to iCloud.
                """))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // O-4: Pasteboard Privacy（macOS 26 Tahoe）警告。.alwaysAllow のときは非表示
            if !permissions.isPasteboardAccessAllowed {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: """
                            Tattan may stop monitoring the clipboard if macOS prompts you \
                            for permission every time.
                            """))
                            Button(String(localized: "Open System Settings")) {
                                permissions.openPasteboardSettings()
                            }
                        }
                    }
                } footer: {
                    Text(String(localized: """
                    Set Tattan to "Allow" under Privacy & Security > Paste from Other Apps.
                    """))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    /// マニュアルの URL は表示言語に追従する（日本語 → khamsin.jp、それ以外 → /en/）。
    private var manualURL: URL {
        settings.language == .japanese
            ? URL(string: "https://khamsin.jp/products/tattan/manual/")!
            : URL(string: "https://khamsin.jp/en/products/tattan/manual/")!
    }
}
