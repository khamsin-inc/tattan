import Testing
@testable import Tattan

/// カラーコード検出（D-6）のテスト。
struct HexColorParserTests {

    @Test func parsesSixDigitHexOnly() {
        #expect(HexColorParser.parse("ff0000") == HexColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(HexColorParser.parse("00ff00") == HexColor(red: 0, green: 1, blue: 0, alpha: 1))
    }

    /// 住所・部屋番号等の誤検知対策（2026-06-12）: 6 桁ちょうど以外は色として扱わない
    @Test func rejectsNonSixDigitForms() {
        #expect(HexColorParser.parse("f00") == nil)      // 3 桁短縮形も対象外
        #expect(HexColorParser.parse("f00f") == nil)     // 4 桁
        #expect(HexColorParser.parse("ff000080") == nil) // 8 桁アルファ付き
        #expect(HexColorParser.parse("zzz") == nil)
        #expect(HexColorParser.parse("12345") == nil)
        #expect(HexColorParser.parse("") == nil)
    }

    @Test func findsFirstColorInText() {
        let color = HexColorParser.firstColor(in: "brand color: #ffaaff (light pink)")
        #expect(color != nil)
        #expect(HexColorParser.firstColor(in: "no color here") == nil)
        #expect(HexColorParser.firstColor(in: "#zzz then #00ff00") ==
                HexColor(red: 0, green: 1, blue: 0, alpha: 1))
    }

    /// 「#数字」を含む住所等で色スウォッチが出ないこと
    @Test func ignoresAddressLikeHashNumbers() {
        #expect(HexColorParser.firstColor(in: "123 Main St #101, Seattle") == nil)
        #expect(HexColorParser.firstColor(in: "Apt #2345") == nil)
        #expect(HexColorParser.firstColor(in: "order #1234567") == nil) // 7 桁は対象外
    }
}
