import SwiftUI

/// ホットキーで呼ぶカーソル近くのポップアップ（F-2 / §10.3）の中身。
struct PopupRootView: View {
    @ObservedObject var model: PopupViewModel
    /// パネル再表示のたびに +1 される世代番号。モデル参照だけだと新旧 root が
    /// 同値と判定されて SwiftUI が再評価をスキップするため、これで変化を作る
    let generation: Int

    var body: some View {
        VStack(spacing: 0) {
            if model.showsSectionPicker {
                sectionPicker
            }
            if model.activeSection == .history {
                historyArea
            } else {
                snippetArea
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var sectionPicker: some View {
        Picker("", selection: Binding(
            get: { model.section },
            set: { model.switchSection($0) }
        )) {
            Text(String(localized: "History")).tag(PopupViewModel.Section.history)
            Text(String(localized: "Snippets")).tag(PopupViewModel.Section.snippets)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(10)
    }

    // MARK: - 履歴タブ

    private var historyArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    historyRows
                }
                .padding(8)
                // 個別削除時に行がスッと消えるアニメーション
                .animation(.default, value: model.historyItems.count)
            }
            .onChange(of: model.scrollTarget) { _, newValue in
                // キーボード操作のときだけ追従し、アンカー無し = 最小限の移動にする。
                // 行 identity は uuid なのでスクロール先も uuid で指定する
                guard let newValue, model.historyItems.indices.contains(newValue) else { return }
                proxy.scrollTo(model.historyItems[newValue].uuid)
            }
        }
    }

    @ViewBuilder private var historyRows: some View {
        if model.historyItems.isEmpty {
            emptyLabel(String(localized: "No history yet"))
        }
        ForEach(Array(model.historyItems.enumerated()), id: \.element.uuid) { index, item in
            PopupHistoryRow(
                item: item,
                index: index,
                isSelected: index == model.selectedIndex,
                previewLength: model.previewLength,
                fontScale: model.fontScale,
                onDelete: { model.deleteHistory(at: index) }
            )
            // 行の identity は項目固有の uuid（インデックスにすると削除・タブ切替で
            // 行ビューが誤って使い回される実機バグの温床になる）
            .id(item.uuid)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { model.hoverHistory(index) }
            }
            .onTapGesture { model.pasteHistory(at: index) }
            .contextMenu {
                Button(String(localized: "Paste")) { model.pasteHistory(at: index) }
                // スニペットはテキスト前提（D-3）なので、画像項目には出さない
                // （出すと空コンテンツのスニペットができる。2026-07-02 レビュー指摘 #13）
                if item.kind != .image {
                    Button(String(localized: "Save as Snippet…")) { model.onSaveAsSnippet?(item) }
                }
                Divider()
                Button(String(localized: "Delete"), role: .destructive) { model.deleteHistory(at: index) }
            }
        }
    }

    // MARK: - スニペットタブ（左: グループ / 右: 中身。メニューのサブメニュー展開と同じ操作感）

    private var snippetArea: some View {
        // グループ列はポップアップ幅の 42%（既定 360pt 時の 150pt と同じ比率）。
        // 幅の設定変更・手動リサイズでも比率を保つ（2026-06-12 Ken フィードバック）
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if model.snippetGroups.isEmpty {
                                emptyLabel(String(localized: "No snippets yet"))
                            }
                            ForEach(Array(model.snippetGroups.enumerated()), id: \.offset) { index, group in
                                PopupGroupRow(
                                    name: group.name ?? String(localized: "No Group"),
                                    iconName: group.iconName,
                                    count: group.snippets.count,
                                    isSelected: index == model.selectedGroupIndex,
                                    isFocusedColumn: !model.snippetColumnFocused,
                                    fontScale: model.fontScale
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { model.hoverGroup(index) }
                                }
                                .onTapGesture { model.hoverGroup(index) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.groupScrollTarget) { _, newValue in
                        // 履歴（scrollTarget）と同じ: キーボード操作のときだけ追従する
                        guard let newValue, model.snippetGroups.indices.contains(newValue) else { return }
                        proxy.scrollTo(newValue)
                    }
                }
                .frame(width: geometry.size.width * 0.42)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(
                                Array(model.currentGroupSnippets.enumerated()),
                                id: \.element.uuid
                            ) { index, snippet in
                                PopupSnippetRow(
                                    snippet: snippet,
                                    index: index,
                                    isSelected: index == model.snippetIndexInGroup && model.snippetColumnFocused,
                                    fontScale: model.fontScale
                                )
                                .id(snippet.uuid)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { model.hoverSnippet(index) }
                                }
                                .onTapGesture { model.pasteSnippet(at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.snippetScrollTarget) { _, newValue in
                        guard let newValue, model.currentGroupSnippets.indices.contains(newValue) else { return }
                        proxy.scrollTo(model.currentGroupSnippets[newValue].uuid)
                    }
                }
            }
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(24)
    }
}

private struct PopupHistoryRow: View {
    let item: ClipHistoryItem
    let index: Int
    let isSelected: Bool
    let previewLength: Int
    let fontScale: Double
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            indexBadge(index)
            // 種類を表すアイコンは左端に統一（2026-06-12 Ken 要望）
            if let data = item.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                leadingTypeIcon
                TruncatingText(
                    displayed: singleLinePreview,
                    fullText: tooltipContent,
                    font: .system(size: 13 * fontScale)
                )
            }
            Spacer(minLength: 0)
            // ゴミ箱は右端。常にレイアウトに置いて透明度だけ切り替える
            // （ホバー時に挿入すると行の高さが揺れてリスト全体がムニュムニュ動くため）
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .help(String(localized: "Delete this item"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    /// 左端の種類アイコン: クレカ / Concealed（鍵） / ファイル / カラーコード（該当時のみ）
    @ViewBuilder private var leadingTypeIcon: some View {
        if item.sensitivity == .creditCard {
            Image(systemName: "creditcard")
                .foregroundStyle(.secondary)
                .help(String(localized: "Stored locally only"))
        } else if item.sensitivity == .concealed {
            Image(systemName: "key")
                .foregroundStyle(.secondary)
                .help(String(localized: "Concealed content — stored locally only"))
        } else if item.kind == .fileReference {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        } else if let hex = HexColorParser.firstColor(in: item.previewText) {
            Circle()
                .fill(Color(red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
        }
    }

    private var singleLinePreview: String {
        String(item.previewText.prefix(previewLength))
            .replacingOccurrences(of: "\n", with: " ")
    }

    private var tooltipContent: String? {
        TruncationHeuristic.fullText(
            kind: item.kind,
            sensitivity: item.sensitivity,
            plainText: item.plainText,
            previewText: item.previewText
        )
    }
}

/// 左カラムのグループ行。選択中はフォーカスのあるカラム側を濃く塗る
private struct PopupGroupRow: View {
    let name: String
    let iconName: String?
    let count: Int
    let isSelected: Bool
    let isFocusedColumn: Bool
    let fontScale: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName ?? "folder")
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 13 * fontScale))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 10 * fontScale, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9 * fontScale))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(highlightStyle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var highlightStyle: AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(.clear) }
        return isFocusedColumn
            ? AnyShapeStyle(Color.accentColor.opacity(0.25))
            : AnyShapeStyle(Color.secondary.opacity(0.15))
    }
}

private struct PopupSnippetRow: View {
    let snippet: Snippet
    let index: Int
    let isSelected: Bool
    let fontScale: Double

    var body: some View {
        HStack(spacing: 8) {
            indexBadge(index)
            if let hex = HexColorParser.firstColor(in: snippet.content) {
                Circle()
                    .fill(Color(red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.title.isEmpty ? String(localized: "Untitled") : snippet.title)
                    .font(.system(size: 13 * fontScale, weight: .medium))
                    .lineLimit(1)
                Text(snippet.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

/// 1〜9 と 0（＝10 件目）は数字キーで即ペーストできることを示すバッジ（F-3）
@ViewBuilder
private func indexBadge(_ index: Int) -> some View {
    if index < 10 {
        Text(index == 9 ? "0" : "\(index + 1)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 14)
    } else {
        Spacer().frame(width: 14)
    }
}
