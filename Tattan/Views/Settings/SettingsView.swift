import SwiftUI

/// 設定画面のルート（H 系 / §10.5）。
/// macOS の「システム設定」と同じサイドバー型（2026-06-12 Ken の意向でタブ型から変更）。
struct SettingsView: View {

    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case history
        case shortcuts
        case excludedApps
        case data
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .history: String(localized: "History")
            case .shortcuts: String(localized: "Shortcuts")
            case .excludedApps: String(localized: "Excluded Apps")
            case .data: String(localized: "Data")
            case .about: String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .history: "clock.arrow.circlepath"
            case .shortcuts: "keyboard.fill"
            case .excludedApps: "hand.raised.fill"
            case .data: "externaldrive.fill"
            case .about: "info"
            }
        }

        /// システム設定風の色付き角丸スクエアアイコン用
        var iconColor: Color {
            switch self {
            case .general: .gray
            case .history: .orange
            case .shortcuts: .purple
            case .excludedApps: .red
            case .data: .blue
            case .about: .gray
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(Pane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(pane.iconColor.gradient, in: RoundedRectangle(cornerRadius: 5))
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detailView
        }
        // サイドバーは常時表示（システム設定と同じ。折りたたみトグルは出さない）
        .toolbar(removing: .sidebarToggle)
        // 中身の高さ揺れで窓が潰れないよう固定サイズ（macOS の設定ウィンドウの作法）。
        // About はアイコンヘッダー分で縦に長いため、システム設定と同じくペインごとに高さを変える
        .frame(width: 700, height: selection == .about ? 710 : 460)
    }

    @ViewBuilder private var detailView: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .history: HistorySettingsView()
        case .shortcuts: ShortcutSettingsView()
        case .excludedApps: ExcludedAppsSettingsView()
        case .data: DataSettingsView()
        case .about: AboutSettingsView()
        }
    }
}
