import Foundation

/// クレジットカード番号の内容検知（O-1: 数字パターン + IIN + Luhn チェック）。
///
/// パスワードは内容からは推測しない — `org.nspasteboard.ConcealedType` マーカーで
/// 上流（ClipboardMonitor）が破棄する（O-1/O-2）。
///
/// 誤検知のコストは「同期されない + 表示マスク」だけでペーストは通常どおり可能なため、
/// 取りこぼしより安全側（検知寄り）に倒す（§6.1）。
enum SensitiveContentClassifier {

    /// スキャン対象の上限（文字数）。巨大テキストの全文スキャンはしない（§6.1）。
    /// `prefix` は Character 単位なので「バイト」ではなく「文字数」の上限
    private static let scanCharacterLimit = 64 * 1024

    static func containsCreditCardNumber(in text: String) -> Bool {
        let target = String(text.prefix(scanCharacterLimit))
        return candidateRuns(in: target).contains(where: isCardNumber)
    }

    /// 表示マスク（§6.3）: カード番号の数字を • に置換し、末尾 4 桁だけ残す。区切り文字は保持。
    /// previewText には必ず「マスク → 先頭 N 文字切り出し」の順で適用すること
    /// （逆だと途中で切れた番号がマスクをすり抜ける）。
    static func maskingCardNumbers(in text: String) -> String {
        var result = text
        // 後ろのランから置換すれば、置換で前方のインデックスが無効化されない
        for run in candidateRuns(in: result).reversed() where isCardNumber(run) {
            result.replaceSubrange(run.startIndex..<run.endIndex, with: mask(run))
        }
        return result
    }

    // MARK: - 判定

    private static func isCardNumber(_ run: Substring) -> Bool {
        let digits = String(run.filter(\.isWholeNumber))
        return (13...19).contains(digits.count) && hasKnownIIN(digits) && passesLuhn(digits)
    }

    /// 主要ブランドの IIN（先頭番号帯）+ 桁数の整合チェック。
    /// 電話番号・追跡番号など「Luhn を偶然通る数字列」の誤検知をここで間引く。
    private static func hasKnownIIN(_ digits: String) -> Bool {
        let count = digits.count
        let prefix2 = Int(digits.prefix(2)) ?? -1
        let prefix3 = Int(digits.prefix(3)) ?? -1
        let prefix4 = Int(digits.prefix(4)) ?? -1

        switch true {
        case digits.hasPrefix("4"):                                      // Visa
            return [13, 16, 19].contains(count)
        case (51...55).contains(prefix2), (2221...2720).contains(prefix4): // Mastercard
            return count == 16
        case prefix2 == 34, prefix2 == 37:                               // Amex
            return count == 15
        case prefix2 == 35:                                              // JCB
            return (16...19).contains(count)
        case prefix4 == 6011, prefix2 == 65, (644...649).contains(prefix3): // Discover
            return (16...19).contains(count)
        default:
            return false
        }
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard let digit = char.wholeNumberValue else { return false }
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    // MARK: - 数字ランの走査

    /// 「ASCII 数字が空白/ハイフン 1 文字区切りで連なる」最大ランを列挙する。
    /// 正規表現でなく手書き走査なのは、lookbehind 非依存でテストしやすくするため。
    private static func candidateRuns(in text: String) -> [Substring] {
        var runs: [Substring] = []
        var runStart: String.Index?
        var lastDigit: String.Index?
        var index = text.startIndex

        func closeRun() {
            if let start = runStart, let end = lastDigit {
                runs.append(text[start...end])
            }
            runStart = nil
            lastDigit = nil
        }

        while index < text.endIndex {
            let char = text[index]
            if char.isWholeNumber, char.isASCII {
                if runStart == nil { runStart = index }
                lastDigit = index
            } else if char == " " || char == "-",
                      let last = lastDigit, text.index(after: last) == index {
                // 数字直後の区切り 1 文字だけ許容（区切りが連続したらランを閉じる）
            } else {
                closeRun()
            }
            index = text.index(after: index)
        }
        closeRun()
        return runs
    }

    private static func mask(_ run: Substring) -> String {
        let digitCount = run.filter(\.isWholeNumber).count
        var seen = 0
        let masked = run.map { char -> Character in
            guard char.isWholeNumber else { return char }
            seen += 1
            return seen > digitCount - 4 ? char : "•"
        }
        return String(masked)
    }
}
