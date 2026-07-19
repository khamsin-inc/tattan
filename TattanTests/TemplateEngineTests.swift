import Foundation
import Testing
@testable import Tattan

/// テンプレート変数エンジン（D-3 / §9）の網羅テスト。日時・ロケール・UUID は注入。
struct TemplateEngineTests {

    private var environment: TemplateEnvironment {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.timeZone = timeZone
        let components = DateComponents(
            timeZone: timeZone, year: 2026, month: 6, day: 12, hour: 14, minute: 5, second: 30
        )
        return TemplateEnvironment(
            now: calendar.date(from: components) ?? Date(),
            calendar: calendar,
            locale: Locale(identifier: "ja_JP"),
            timeZone: timeZone,
            clipboardText: "CLIP",
            makeUUID: { UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID() }
        )
    }

    private func render(_ source: String, answers: [Int: String] = [:]) -> RenderedTemplate {
        TemplateRenderer.render(TemplateParser.parse(source), answers: answers, environment: environment)
    }

    @Test func plainTextPassesThrough() {
        #expect(render("hello world").text == "hello world")
    }

    @Test func dateVariants() {
        #expect(render("{{date}}").text == "2026-06-12")
        #expect(render("{{date+3}}").text == "2026-06-15")
        #expect(render("{{date-1}}").text == "2026-06-11")
        #expect(render("{{date:yyyy/M/d}}").text == "2026/6/12")
        #expect(render("{{date+1:M/d}}").text == "6/13")
    }

    @Test func timeDayAndDatetime() {
        #expect(render("{{time}}").text == "14:05")
        #expect(render("{{time:HH:mm:ss}}").text == "14:05:30")
        #expect(render("{{datetime}}").text == "2026-06-12 14:05")
        #expect(render("{{day}}").text == "金曜日") // ja_JP ロケールでの曜日名（Q-2）
    }

    @Test func askAndChoose() {
        #expect(render("{{ask:Subject}}").text.isEmpty)
        #expect(render("{{ask:Subject|MTG}}").text == "MTG")
        #expect(render("{{ask:Subject}}", answers: [0: "Hi"]).text == "Hi")
        #expect(render("{{choose:A|B|C}}").text == "A")
        #expect(render("{{choose:A|B|C}}", answers: [0: "B"]).text == "B")
    }

    @Test func clipboardAndUUID() {
        #expect(render("<{{clipboard}}>").text == "<CLIP>")
        #expect(render("{{uuid}}").text == "11111111-2222-3333-4444-555555555555")
    }

    @Test func cursorOffsetCountsFromEnd() {
        let rendered = render("Hello {{cursor}}World")
        #expect(rendered.text == "Hello World")
        #expect(rendered.cursorOffsetFromEnd == 5)

        #expect(render("no cursor").cursorOffsetFromEnd == nil)

        // 複数ある場合は最初の 1 つだけ有効（§9.2）
        let multi = render("a{{cursor}}b{{cursor}}c")
        #expect(multi.text == "abc")
        #expect(multi.cursorOffsetFromEnd == 2)
    }

    @Test func escapeAndInvalidTokensStayLiteral() {
        #expect(render(#"\{{date}}"#).text == "{{date}}")       // エスケープ
        #expect(render("{{foo}}").text == "{{foo}}")            // 未知のトークン
        #expect(render("{{ask}}").text == "{{ask}}")            // ラベル必須
        #expect(render("{{choose:A}}").text == "{{choose:A}}")  // 選択肢 2 個以上
        #expect(render("{{date").text == "{{date")              // 閉じ忘れ
        #expect(render("{ {date}}").text == "{ {date}}")        // トークンではない
    }

    @Test func mixedTemplate() {
        let source = "お世話になっております。{{date:M月d日}}の{{ask:件名|定例}}の件です。"
        #expect(render(source).text == "お世話になっております。6月12日の定例の件です。")
    }

    @Test func interactiveDetection() {
        let ask = TemplateParser.parse("{{ask:x}}").contains { $0.isInteractive }
        let choose = TemplateParser.parse("{{choose:a|b}}").contains { $0.isInteractive }
        let plain = TemplateParser.parse("{{date}}{{uuid}}").contains { $0.isInteractive }
        #expect(ask)
        #expect(choose)
        #expect(!plain)
    }
}
