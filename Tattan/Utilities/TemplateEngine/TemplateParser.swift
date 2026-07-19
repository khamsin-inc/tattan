import Foundation

/// `{{...}}` トークンのパーサー（§9.1 の文法）。
/// 不正・未知のトークンはエラーにせずリテラルのまま残す — コードスニペットに
/// `{{ }}` が含まれていてもペーストが壊れないことを最優先する。
enum TemplateParser {

    static func parse(_ source: String) -> [TemplateNode] {
        var nodes: [TemplateNode] = []
        var literal = ""
        var index = source.startIndex

        func flushLiteral() {
            if !literal.isEmpty {
                nodes.append(.text(literal))
                literal = ""
            }
        }

        while index < source.endIndex {
            // エスケープ: \{{ → リテラル "{{"
            if source[index] == "\\", source[source.index(after: index)...].hasPrefix("{{") {
                literal += "{{"
                index = source.index(index, offsetBy: 3)
                continue
            }
            if source[index...].hasPrefix("{{"),
               let closeRange = source.range(
                   of: "}}",
                   range: source.index(index, offsetBy: 2)..<source.endIndex
               ) {
                let body = String(source[source.index(index, offsetBy: 2)..<closeRange.lowerBound])
                if let node = parseToken(body) {
                    flushLiteral()
                    nodes.append(node)
                } else {
                    literal += source[index..<closeRange.upperBound]
                }
                index = closeRange.upperBound
                continue
            }
            literal.append(source[index])
            index = source.index(after: index)
        }
        flushLiteral()
        return nodes
    }

    /// body（"{{" と "}}" の内側）を 1 ノードに解釈する。解釈できなければ nil（→ リテラル扱い）。
    /// 変数種別ぶんの分岐を持つディスパッチ関数のため複雑度警告は抑制。
    private static func parseToken(_ body: String) -> TemplateNode? { // swiftlint:disable:this cyclomatic_complexity
        let name: String
        let arg: String?
        if let colon = body.firstIndex(of: ":") {
            name = String(body[..<colon])
            arg = String(body[body.index(after: colon)...])
        } else {
            name = body
            arg = nil
        }

        switch name {
        case "day":
            return arg == nil ? .day : nil
        case "time":
            return .time(format: arg)
        case "datetime":
            return .datetime(format: arg)
        case "clipboard":
            return arg == nil ? .clipboard : nil
        case "cursor":
            return arg == nil ? .cursor : nil
        case "uuid":
            return arg == nil ? .uuid : nil
        case "ask":
            guard let arg, !arg.isEmpty else { return nil }
            if let pipe = arg.firstIndex(of: "|") {
                let label = String(arg[..<pipe])
                let defaultValue = String(arg[arg.index(after: pipe)...])
                return label.isEmpty ? nil : .ask(label: label, defaultValue: defaultValue)
            }
            return .ask(label: arg, defaultValue: nil)
        case "choose":
            guard let arg else { return nil }
            let options = arg.components(separatedBy: "|").filter { !$0.isEmpty }
            return options.count >= 2 ? .choose(options: options) : nil
        default:
            // date / date+N / date-N（offset と :書式 の併用可 §9.1）
            if name == "date" {
                return .date(offsetDays: 0, format: arg)
            }
            if name.hasPrefix("date"), let offset = Int(name.dropFirst(4)),
               name.dropFirst(4).first == "+" || name.dropFirst(4).first == "-" {
                return .date(offsetDays: offset, format: arg)
            }
            return nil
        }
    }
}
