import Testing
@testable import Tattan

struct SensitiveContentClassifierTests {

    // MARK: - 検知（真陽性）

    @Test func detectsMajorBrandTestNumbers() {
        // 各ブランドの公開テスト番号（実在カードではない）
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "4242424242424242"))        // Visa 16
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "4222222222222"))           // Visa 13
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "5555555555554444"))        // Mastercard
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "2223003122003222"))        // Mastercard 2 系
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "378282246310005"))         // Amex 15
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "3530111333300000"))        // JCB
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "6011111111111117"))        // Discover
    }

    @Test func detectsSeparatedAndEmbeddedNumbers() {
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "4242 4242 4242 4242"))
        #expect(SensitiveContentClassifier.containsCreditCardNumber(in: "5555-5555-5555-4444"))
        #expect(SensitiveContentClassifier.containsCreditCardNumber(
            in: "カード番号は 4242 4242 4242 4242 です。よろしく"
        ))
    }

    // MARK: - 非検知（偽陽性の防止）

    @Test func ignoresNonCardDigitSequences() {
        // 電話番号（桁数が範囲外）
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "090-1234-5678"))
        // Luhn チェック不合格
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "4242424242424241"))
        // 既知の IIN に該当しない 16 桁
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "1234567812345670"))
        // 長すぎる数字列（タイムスタンプ等）は 1 ランとして桁数超過で弾く
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "20260612140500001234"))
        // 桁不足
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "注文番号 4242-4242"))
        // 区切りの連続はランを分割する
        #expect(!SensitiveContentClassifier.containsCreditCardNumber(in: "4242  4242  4242  4242"))
    }

    // MARK: - マスク（C-8 / §6.3）

    @Test func masksDigitsKeepingLastFour() {
        let masked = SensitiveContentClassifier.maskingCardNumbers(in: "card: 4242 4242 4242 4242 です")
        #expect(masked == "card: •••• •••• •••• 4242 です")
    }

    @Test func masksOnlyCardRuns() {
        let masked = SensitiveContentClassifier.maskingCardNumbers(
            in: "TEL 090-1234-5678 / 5555-5555-5555-4444"
        )
        #expect(masked.contains("090-1234-5678"))          // 電話番号はそのまま
        #expect(masked.contains("••••-••••-••••-4444"))    // カードだけマスク
    }

    @Test func maskingLeavesPlainTextUntouched() {
        let text = "カード番号を含まない普通のテキスト 12345"
        #expect(SensitiveContentClassifier.maskingCardNumbers(in: text) == text)
    }
}
