import SwiftUI

/// About ペイン: アプリについて / 作者について / 謝辞 の 3 部構成（2026-06-12 Ken の構成案）。
struct AboutSettingsView: View {
    @Environment(UpdaterService.self) private var updater

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // アプリアイコン + 名前のヘッダー（Form の外に置いてセクション枠を付けない）
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text(verbatim: "Tattan")
                    .font(.title2.weight(.semibold))
            }
            .padding(.top, 16)
            form
        }
    }

    private var form: some View {
        Form {
            Section(String(localized: "About Tattan")) {
                Text(String(localized: """
                Tattan — tat-tan! Double-tap ⌘ and your clipboard history appears. \
                Named after the Japanese onomatopoeia for that double-tap sound.
                """))
                .font(.callout)
                .foregroundStyle(.secondary)
                LabeledContent(String(localized: "Version"), value: version)
                LabeledContent(String(localized: "License"), value: "MIT")
                Link(String(localized: "Source Code"),
                     destination: URL(string: "https://github.com/ken297/tattan")!)
                // Sparkle 手動チェック（要件 G-4）。Sparkle 側がバックオフ中は disabled
                Button(String(localized: "Check for Updates…")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            Section(String(localized: "Author")) {
                LabeledContent(String(localized: "Made by")) {
                    HStack(spacing: 8) {
                        Text("Ken")
                        // X 公式ロゴは SF Symbols に無いため 𝕏 文字で表現（Mac アプリの定番手法）
                        Link(destination: URL(string: "https://x.com/miz2403")!) {
                            Text("𝕏")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .help("X")
                    }
                }
                LabeledContent(String(localized: "Web")) {
                    Link("Khamsin", destination: URL(string: "https://khamsin.jp")!)
                }
            }

            // 謝辞は照れくさいので言語に関わらず英語で固定する（2026-06-30 Ken）
            Section {
                // ナラティブな謝辞・リンクなし（2026-06-12 Ken の意向)。
                // Clipy へは敬意の表明のみで、後継・移行先を名乗らない（J-3）
                Text(verbatim: """
                Tattan grew out of years of happily using Clipy, the clipboard manager \
                that showed how good a Mac clipboard tool can be. This app is an independent \
                project written from scratch, but it would not exist without that inspiration — \
                thank you.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                // 依存ライブラリのライセンス表記（MIT の義務 §13.3）
                LabeledContent("KeyboardShortcuts", value: "MIT © Sindre Sorhus")
            } header: {
                Text(verbatim: "Acknowledgements")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
