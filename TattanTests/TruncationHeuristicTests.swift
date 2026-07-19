import Testing
@testable import Tattan

/// TruncatingText の tooltip 出し分け判定（2026-07-10 追加、履歴の 1 行プレビューで
/// 切れてる長文だけホバーで全文を出す機能）の境界値テスト。
struct TruncationHeuristicTests {

    // MARK: - fullText の欠如系

    /// 画像・機密アイテムは `fullText = nil` で呼ばれる → 絶対にツールチップを出さない
    @Test func returnsNilWhenFullTextIsNil() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "some preview",
            fullText: nil,
            visibleWidth: 40,
            idealWidth: 200
        ) == nil)
    }

    /// 空文字の全文にはツールチップを出す意味がない
    @Test func returnsNilWhenFullTextIsEmpty() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "",
            fullText: "",
            visibleWidth: 100,
            idealWidth: 100
        ) == nil)
    }

    // MARK: - 切れてない = ツールチップ不要

    /// 表示 = 全文で、幅にも収まっている → 全部見えてる、ツールチップ不要
    @Test func returnsNilWhenFullyVisible() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "hello",
            fullText: "hello",
            visibleWidth: 100,
            idealWidth: 40
        ) == nil)
    }

    /// 初回描画で幅が両方 0 のとき: 内容欠損が無ければツールチップは出さない
    @Test func returnsNilWhenWidthsAreZeroAndContentMatches() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "hello",
            fullText: "hello",
            visibleWidth: 0,
            idealWidth: 0
        ) == nil)
    }

    /// visibleWidth と idealWidth の差が 0.5pt 以内 → 端数の丸め誤差扱い、ツールチップ出さない
    @Test func toleratesSubpixelDifference() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "hello",
            fullText: "hello",
            visibleWidth: 100,
            idealWidth: 100.3
        ) == nil)
    }

    // MARK: - 内容欠損（表示 != 全文）

    /// previewLength で切られた → displayed が短くなる → ツールチップに全文
    @Test func returnsFullTextWhenContentIsPrefixCut() {
        let full = String(repeating: "a", count: 200)
        let displayed = String(full.prefix(50))
        #expect(TruncationHeuristic.tooltip(
            displayed: displayed,
            fullText: full,
            visibleWidth: 300,
            idealWidth: 250
        ) == full)
    }

    /// 改行がスペース置換された → displayed != fullText → ツールチップに改行込みの全文
    @Test func returnsFullTextWhenNewlineReplaced() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "line1 line2",
            fullText: "line1\nline2",
            visibleWidth: 300,
            idealWidth: 100
        ) == "line1\nline2")
    }

    /// 幅計測がまだ届いていなくても、内容欠損があれば即ツールチップを出す
    @Test func showsTooltipOnContentTruncationEvenWithoutWidths() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "abc",
            fullText: "abcdef",
            visibleWidth: 0,
            idealWidth: 0
        ) == "abcdef")
    }

    // MARK: - 視覚 truncate（幅で切れてる）

    /// 内容は同じでも、幅で描き切れてない → ツールチップに全文
    @Test func returnsFullTextWhenVisuallyTruncated() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "hello",
            fullText: "hello",
            visibleWidth: 30,
            idealWidth: 60
        ) == "hello")
    }

    // MARK: - 複合ケース

    /// 内容も違うし幅でも切れてる → ツールチップに全文（重複判定でも OK）
    @Test func returnsFullTextWhenBothTruncationsApply() {
        #expect(TruncationHeuristic.tooltip(
            displayed: "hello wor",
            fullText: "hello world of clipboard",
            visibleWidth: 40,
            idealWidth: 200
        ) == "hello world of clipboard")
    }

    // MARK: - fullText(kind:sensitivity:plainText:previewText:)

    /// テキスト & Sensitivity.none & plainText あり → plainText を優先
    @Test func fullTextPrefersPlainTextForNormalItem() {
        #expect(TruncationHeuristic.fullText(
            kind: .text,
            sensitivity: .none,
            plainText: "line1\nline2",
            previewText: "line1 line2"
        ) == "line1\nline2")
    }

    /// plainText が nil → previewText にフォールバック（fileReference 等）
    @Test func fullTextFallsBackToPreviewWhenPlainTextIsNil() {
        #expect(TruncationHeuristic.fullText(
            kind: .fileReference,
            sensitivity: .none,
            plainText: nil,
            previewText: "/tmp/foo.txt"
        ) == "/tmp/foo.txt")
    }

    /// 画像アイテムは絶対に全文を出さない（サムネイル分岐から到達しない防御でもある）
    @Test func fullTextReturnsNilForImage() {
        #expect(TruncationHeuristic.fullText(
            kind: .image,
            sensitivity: .none,
            plainText: "some ocr text maybe",
            previewText: "some ocr text maybe"
        ) == nil)
    }

    /// クレカ番号は plainText にマスク前の生値が残る可能性 → 絶対にツールチップに出さない
    @Test func fullTextReturnsNilForCreditCard() {
        #expect(TruncationHeuristic.fullText(
            kind: .text,
            sensitivity: .creditCard,
            plainText: "4111-1111-1111-1111",
            previewText: "**** **** **** 1111"
        ) == nil)
    }

    /// Concealed（パスワード等）も同じく plainText を漏らさない
    @Test func fullTextReturnsNilForConcealed() {
        #expect(TruncationHeuristic.fullText(
            kind: .text,
            sensitivity: .concealed,
            plainText: "supersecret",
            previewText: "***********"
        ) == nil)
    }
}
