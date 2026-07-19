import SwiftUI

struct TattanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            // dependencies は applicationDidFinishLaunching で構築済み
            // （Settings シーンの body はウィンドウを開いた時に評価される）
            if let deps = appDelegate.dependencies {
                // 注入リストは SettingsWindowController 側と完全に揃えること。
                // 片方だけに足すと、もう片方の入口から開いたペインで
                // @Environment 解決に失敗してクラッシュする（2026-07-02 レビュー指摘 #1）
                SettingsView()
                    .environment(deps.settings)
                    .environment(deps.launchAtLogin)
                    .environment(deps.hotkeyService)
                    .environment(deps.permissions)
                    .environment(deps.historyService)
                    .environment(deps.importExport)
                    .environment(deps.syncCoordinator)
                    .environment(deps.syncReset)
                    .environment(deps.updater)
            }
        }
    }
}

/// プロセスの最初期に AppleLanguages を確定させてから SwiftUI を起動する @main。
/// SwiftUI の `App.init()` や AppDelegate より前に走るので、初回起動で macOS の
/// システム言語が混ざる問題が起きない（2026-06-30 修正: 「画面は日本語なのに
/// 設定ピッカーは English」状態の原因）
@main
struct TattanLauncher {
    static func main() {
        // UserDefaults に保存された言語選択を、Bundle が一度でも参照する前に
        // AppleLanguages へ反映する。未設定なら既定の English
        let stored = UserDefaults.standard.string(forKey: "language")
            ?? AppLanguage.english.rawValue
        UserDefaults.standard.set([stored], forKey: "AppleLanguages")
        TattanApp.main()
    }
}
