import Combine
import Foundation

/// ポップアップの表示状態とキーボード操作（F-3）の解釈。
/// AppKit イベント（keyCode）→ 操作への変換をここに集め、View は描画に専念させる。
///
/// 注意: @Observable ではなく Combine の ObservableObject を使う。
/// nonactivating な borderless パネル内の NSHostingView では Observation 框組みの
/// 更新通知が届かない（2026-06-12 実機で確認: データ更新も選択ハイライトも反映されない）。
/// @Published + @ObservedObject の経路は同構成でも機能する。
@MainActor
final class PopupViewModel: ObservableObject {

    enum Section {
        case history
        case snippets
    }

    /// スニペットタブの 2 カラム表示単位（メニューバーメニューのグループ構造と対応）
    struct SnippetGroup {
        let name: String? // nil = グループ無し
        let iconName: String? // グループのアイコン（SF Symbol）。nil = folder
        let snippets: [Snippet]
    }

    @Published private(set) var mode: PopupMode = .unified
    @Published var section: Section = .history

    // 履歴タブ
    @Published private(set) var historyItems: [ClipHistoryItem] = []
    @Published var selectedIndex = 0
    /// キーボード操作による選択移動だけが設定する自動スクロール先。
    /// マウスホバーの選択変更でスクロールすると、スクロールでカーソル下の行が変わって
    /// また発火する連鎖（実機で「ギュイン」と暴れる）が起きるため分離している
    @Published private(set) var scrollTarget: Int?

    // スニペットタブ（左: グループ / 右: 選択グループの中身）
    @Published private(set) var snippetGroups: [SnippetGroup] = []
    @Published var selectedGroupIndex = 0
    @Published var snippetIndexInGroup = 0
    /// true = 右カラム（スニペット側）にキーボードフォーカスがある
    @Published var snippetColumnFocused = false
    /// スニペットタブの自動スクロール先（左: グループ列 / 右: スニペット列）。
    /// scrollTarget と同じ理由でキーボード操作だけが設定する（ホバーで動かすと暴れる）
    @Published private(set) var groupScrollTarget: Int?
    @Published private(set) var snippetScrollTarget: Int?

    @Published private(set) var previewLength = 50
    @Published private(set) var fontScale = 1.0

    var onPasteHistory: ((ClipHistoryItem) -> Void)?
    var onPasteSnippet: ((Snippet) -> Void)?
    var onSaveAsSnippet: ((ClipHistoryItem) -> Void)?
    var onDeleteHistory: ((ClipHistoryItem) -> Void)?
    var onDismiss: (() -> Void)?

    var activeSection: Section {
        switch mode {
        case .unified: section
        case .historyOnly: .history
        case .snippetsOnly: .snippets
        }
    }

    var showsSectionPicker: Bool { mode == .unified }

    var currentGroupSnippets: [Snippet] {
        guard snippetGroups.indices.contains(selectedGroupIndex) else { return [] }
        return snippetGroups[selectedGroupIndex].snippets
    }

    func configure(
        mode: PopupMode,
        historyItems: [ClipHistoryItem],
        snippetGroups: [SnippetGroup],
        previewLength: Int,
        fontScale: Double
    ) {
        self.mode = mode
        self.historyItems = historyItems
        self.snippetGroups = snippetGroups
        self.previewLength = previewLength
        self.fontScale = fontScale
        section = mode == .snippetsOnly ? .snippets : .history
        selectedIndex = 0
        scrollTarget = nil
        selectedGroupIndex = 0
        snippetIndexInGroup = 0
        snippetColumnFocused = false
        groupScrollTarget = nil
        snippetScrollTarget = nil
    }

    // MARK: - マウス操作・セクション切替
    //
    // onHover / Picker はビュー更新の最中に発火することがある（タブ切替でカーソル下に
    // 新しい行が来た瞬間など）。その場で @Published を書き換えると
    // "Publishing changes from within view updates" の未定義動作警告になるため、
    // これらの変更は必ず次のメインアクタージョブへ先送りする

    func hoverHistory(_ index: Int) {
        deferred { model in
            guard model.historyItems.indices.contains(index) else { return }
            model.selectedIndex = index
        }
    }

    func hoverGroup(_ index: Int) {
        deferred { model in
            guard model.snippetGroups.indices.contains(index) else { return }
            model.selectedGroupIndex = index
            model.snippetIndexInGroup = 0
            model.snippetColumnFocused = false
        }
    }

    func hoverSnippet(_ index: Int) {
        deferred { model in
            guard model.currentGroupSnippets.indices.contains(index) else { return }
            model.snippetIndexInGroup = index
            model.snippetColumnFocused = true
        }
    }

    func switchSection(_ newSection: Section) {
        deferred { model in
            model.section = newSection
            model.selectedIndex = 0
            model.selectedGroupIndex = 0
            model.snippetIndexInGroup = 0
            model.snippetColumnFocused = false
        }
    }

    private func deferred(_ change: @escaping @MainActor (PopupViewModel) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            change(self)
        }
    }

    // MARK: - キーボード操作（F-3 の確定動線）

    /// true = イベント消費。1〜9 即ペースト / ↑↓ 移動 / →← グループ出入り /
    /// Enter 確定 / Esc 閉じる / Tab セクション切替。
    /// キー種別ぶんの分岐を持つディスパッチ関数のため複雑度警告は抑制。
    func handleKey(keyCode: UInt16, characters: String?) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        switch keyCode {
        case 53: // Esc
            onDismiss?()
            return true
        case 36, 76: // Return / Enter
            confirmSelection()
            return true
        case 125: // ↓
            moveVertical(1)
            return true
        case 126: // ↑
            moveVertical(-1)
            return true
        case 124: // →: グループの中身へ（メニューのサブメニュー展開と同じ感覚）
            guard activeSection == .snippets, !snippetGroups.isEmpty else { return false }
            snippetColumnFocused = true
            return true
        case 123: // ←: グループ一覧へ戻る
            guard activeSection == .snippets, snippetColumnFocused else { return false }
            snippetColumnFocused = false
            return true
        case 48: // Tab: 統合モードのセクション切替
            guard showsSectionPicker else { return false }
            section = section == .history ? .snippets : .history
            selectedIndex = 0
            scrollTarget = 0
            selectedGroupIndex = 0
            snippetIndexInGroup = 0
            snippetColumnFocused = false
            return true
        default:
            if let characters, characters.count == 1, let digit = Int(characters) {
                // 1〜9 はその順位、0 は 10 件目（キーボードで 9 の右隣＝10 番目）
                if (1...9).contains(digit) {
                    pasteCurrent(at: digit - 1)
                    return true
                } else if digit == 0 {
                    pasteCurrent(at: 9)
                    return true
                }
            }
            return false
        }
    }

    func confirmSelection() {
        switch activeSection {
        case .history:
            pasteHistory(at: selectedIndex)
        case .snippets:
            if snippetColumnFocused {
                pasteSnippet(at: snippetIndexInGroup)
            } else {
                snippetColumnFocused = true // グループ上で Enter = 開く
            }
        }
    }

    func pasteCurrent(at index: Int) {
        switch activeSection {
        case .history:
            pasteHistory(at: index)
        case .snippets:
            pasteSnippet(at: index)
        }
    }

    func pasteHistory(at index: Int) {
        guard historyItems.indices.contains(index) else { return }
        onPasteHistory?(historyItems[index])
    }

    /// ゴミ箱アイコン・コンテキストメニューからの個別削除。ポップアップは開いたままにして
    /// 連続削除できるようにする（2026-06-12 Ken 要望）
    func deleteHistory(at index: Int) {
        guard historyItems.indices.contains(index) else { return }
        let item = historyItems.remove(at: index)
        if selectedIndex >= historyItems.count {
            selectedIndex = max(0, historyItems.count - 1)
        }
        onDeleteHistory?(item)
    }

    func pasteSnippet(at index: Int) {
        guard currentGroupSnippets.indices.contains(index) else { return }
        onPasteSnippet?(currentGroupSnippets[index])
    }

    private func moveVertical(_ delta: Int) {
        switch activeSection {
        case .history:
            guard !historyItems.isEmpty else { return }
            selectedIndex = min(max(selectedIndex + delta, 0), historyItems.count - 1)
            scrollTarget = selectedIndex
        case .snippets:
            if snippetColumnFocused {
                let count = currentGroupSnippets.count
                guard count > 0 else { return }
                snippetIndexInGroup = min(max(snippetIndexInGroup + delta, 0), count - 1)
                snippetScrollTarget = snippetIndexInGroup
            } else {
                guard !snippetGroups.isEmpty else { return }
                selectedGroupIndex = min(max(selectedGroupIndex + delta, 0), snippetGroups.count - 1)
                snippetIndexInGroup = 0
                groupScrollTarget = selectedGroupIndex
                // グループが替わると右カラムの中身ごと入れ替わるので先頭へ戻す
                snippetScrollTarget = 0
            }
        }
    }
}
