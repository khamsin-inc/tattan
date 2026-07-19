import Foundation

/// `#ffaaff` 等のカラーコード検出（D-6）。保存はせず表示時に派生させる（§2.4）。
struct HexColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum HexColorParser {

    /// テキスト中の最初のカラーコードを返す（スニペット一覧・編集画面のスウォッチ用）
    static func firstColor(in text: String) -> HexColor? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "#" {
                let start = text.index(after: index)
                var end = start
                while end < text.endIndex, text[end].isHexDigit { end = text.index(after: end) }
                if let color = parse(String(text[start..<end])) {
                    return color
                }
                index = end
            } else {
                index = text.index(after: index)
            }
        }
        return nil
    }

    /// "#" を除いた 6 桁ちょうどの hex のみ解釈する（#RRGGBB）。
    /// 3/4/8 桁を対象外にするのは、住所・部屋番号等の「#数字」（#101 など）への
    /// 誤検知を避けるため（2026-06-12 Ken 実機フィードバック）
    static func parse(_ hex: String) -> HexColor? {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }

        func component(_ offset: Int) -> Double? {
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            guard let value = UInt8(hex[start..<end], radix: 16) else { return nil }
            return Double(value) / 255
        }

        guard let red = component(0), let green = component(2), let blue = component(4) else {
            return nil
        }
        return HexColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
