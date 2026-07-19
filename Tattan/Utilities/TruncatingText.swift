import SwiftUI

/// 1 行 Text を表示し、内容欠損 or 視覚的な truncate が起きているときだけ
/// OS ネイティブのツールチップ（`.help(_:)`）で全文を出す View。
///
/// 使いどころ: 履歴・スニペットの 1 行プレビューで、prefix が同じ長文が並ぶと
/// 区別できなくなる問題（2026-07-10 Ken 要望）を、切れてない行にはツールチップを
/// 出さない形で解決する。
struct TruncatingText: View {
    /// 実際に描画するテキスト（表示用に既に短縮・改行置換されている想定）
    let displayed: String
    /// ツールチップに出す全文。`nil` のときは絶対にツールチップを出さない
    /// （画像アイテムや機密アイテムでの全文漏洩防止）
    let fullText: String?
    let font: Font

    @State private var visibleWidth: CGFloat = 0
    @State private var idealWidth: CGFloat = 0

    var body: some View {
        Text(displayed)
            .font(font)
            .lineLimit(1)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { newValue in
                visibleWidth = newValue
            }
            .background(alignment: .leading) {
                // 制限なしで描画したときの ideal 幅を測る。`.hidden()` + `.background`
                // は本体レイアウトに影響しないので、表示上は透明で幅計算にだけ寄与する
                Text(displayed)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { newValue in
                        idealWidth = newValue
                    }
            }
            .help(tooltip)
    }

    /// `.help("")` は AppKit の toolTip="" と同じで、実機ではツールチップが出ない挙動なので
    /// 条件付き文字列で切り替えれば View の identity を壊さずに済む
    private var tooltip: String {
        TruncationHeuristic.tooltip(
            displayed: displayed,
            fullText: fullText,
            visibleWidth: visibleWidth,
            idealWidth: idealWidth
        ) ?? ""
    }
}

/// TruncatingText / NSMenuItem.toolTip の出し分け判定を純関数として切り出したもの。
/// SwiftUI レイアウトを走らせずに Unit Test できる。
enum TruncationHeuristic {
    /// 描画中の Text にホバーしたときに出すべきツールチップ文字列を返す。
    /// ツールチップを出すべきでないときは `nil`。
    ///
    /// - Parameters:
    ///   - displayed: 実際に画面に描かれているテキスト
    ///   - fullText: 全文（nil の場合は絶対にツールチップを出さない）
    ///   - visibleWidth: 画面に実際に描画された Text の幅
    ///   - idealWidth: 制限なしで描画したときの ideal 幅
    static func tooltip(
        displayed: String,
        fullText: String?,
        visibleWidth: CGFloat,
        idealWidth: CGFloat
    ) -> String? {
        guard let fullText, !fullText.isEmpty else { return nil }

        // 内容が既に切られている（500 文字カット / previewLength カット / 改行スペース置換）
        let contentTruncated = displayed != fullText

        // 幅で更に切られている。初回描画で幅がまだ 0 のときは判定不能として扱う。
        // 端数の丸め誤差で誤発火しないよう 0.5pt の閾値を持たせる
        let widthsKnown = visibleWidth > 0 && idealWidth > 0
        let visuallyTruncated = widthsKnown && idealWidth > visibleWidth + 0.5

        guard contentTruncated || visuallyTruncated else { return nil }
        return fullText
    }

    /// ホバー時のツールチップに出す全文の元ネタ。画像・機密（クレカ / concealed）は絶対に nil を返す。
    /// `previewText` はマスク済みでも `plainText` はマスク前の生値が残る可能性があり、ホバーで漏らさない。
    static func fullText(
        kind: ContentKind,
        sensitivity: Sensitivity,
        plainText: String?,
        previewText: String
    ) -> String? {
        if kind == .image { return nil }
        if sensitivity != .none { return nil }
        return plainText ?? previewText
    }
}
