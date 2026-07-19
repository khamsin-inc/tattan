import Foundation

/// 展開時の外部依存をすべて注入する（§9.2: レンダラーは純粋関数としてテスト可能に保つ）。
struct TemplateEnvironment: Sendable {
    var now: Date = Date()
    var calendar: Calendar = .current
    var locale: Locale = .current
    var timeZone: TimeZone = .current
    /// {{clipboard}} の値。ペーストボードを上書きする「前」に読んで渡すこと（§9.3）
    var clipboardText: String?
    var makeUUID: @Sendable () -> UUID = { UUID() }
}

struct RenderedTemplate: Equatable, Sendable {
    var text: String
    /// {{cursor}} 位置から末尾までの文字数 = ペースト後に送出する ← キーの回数（§9.4）。
    /// {{cursor}} が無ければ nil
    var cursorOffsetFromEnd: Int?
}

enum TemplateRenderer {

    /// - Parameter answers: interactive ノード（ask/choose）の回答。キーはノードの配列 index
    /// - Note: 変数種別ぶんの分岐を持つディスパッチ関数のため複雑度警告は抑制
    static func render( // swiftlint:disable:this cyclomatic_complexity
        _ nodes: [TemplateNode],
        answers: [Int: String] = [:],
        environment: TemplateEnvironment
    ) -> RenderedTemplate {
        var output = ""
        var cursorAt: Int?

        for (index, node) in nodes.enumerated() {
            switch node {
            case .text(let text):
                output += text
            case .date(let offsetDays, let format):
                let date = environment.calendar.date(
                    byAdding: .day, value: offsetDays, to: environment.now
                ) ?? environment.now
                output += formatted(date, pattern: format ?? "yyyy-MM-dd",
                                    fixedLocale: format == nil, environment: environment)
            case .day:
                output += formatted(environment.now, pattern: "EEEE",
                                    fixedLocale: false, environment: environment)
            case .time(let format):
                output += formatted(environment.now, pattern: format ?? "HH:mm",
                                    fixedLocale: format == nil, environment: environment)
            case .datetime(let format):
                output += formatted(environment.now, pattern: format ?? "yyyy-MM-dd HH:mm",
                                    fixedLocale: format == nil, environment: environment)
            case .ask(_, let defaultValue):
                output += answers[index] ?? defaultValue ?? ""
            case .choose(let options):
                output += answers[index] ?? options.first ?? ""
            case .clipboard:
                output += environment.clipboardText ?? ""
            case .cursor:
                // 複数あっても最初の 1 つだけ有効（§9.2）
                if cursorAt == nil { cursorAt = output.count }
            case .uuid:
                output += environment.makeUUID().uuidString
            }
        }
        return RenderedTemplate(
            text: output,
            cursorOffsetFromEnd: cursorAt.map { output.count - $0 }
        )
    }

    /// 既定書式（format 省略時）はロケール非依存の固定表記、ユーザー指定書式は環境ロケールで解釈（§9.5）
    private static func formatted(
        _ date: Date, pattern: String, fixedLocale: Bool, environment: TemplateEnvironment
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = environment.calendar
        formatter.timeZone = environment.timeZone
        formatter.locale = fixedLocale ? Locale(identifier: "en_US_POSIX") : environment.locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
