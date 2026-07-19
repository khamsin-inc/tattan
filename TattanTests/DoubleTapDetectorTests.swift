import Testing
@testable import Tattan

/// 修飾キーダブルタップ判定（§8.2 / N-5: 300ms 窓）の状態遷移テスト。
/// #expect マクロ内では mutating メソッドを呼べないため、結果を変数に受けてから検証する。
struct DoubleTapDetectorTests {

    @Test func firesWithinWindow() {
        var detector = DoubleTapDetector(window: 0.3)
        let down1 = detector.process(.targetDown(0.0))
        let up1 = detector.process(.targetUp(0.1))
        let down2 = detector.process(.targetDown(0.25))
        #expect(!down1)
        #expect(!up1)
        #expect(down2)
    }

    @Test func exactWindowBoundaryFires() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.targetUp(0.1))
        let fired = detector.process(.targetDown(0.3)) // 1 回目押下から 300ms ちょうどは成立（N-5）
        #expect(fired)
    }

    @Test func beyondWindowRearmsAsFirstPress() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.targetUp(0.1))
        let late = detector.process(.targetDown(0.5)) // 窓超え → 新しい 1 回目扱い
        _ = detector.process(.targetUp(0.6))
        let fired = detector.process(.targetDown(0.7)) // 仕切り直しから成立
        #expect(!late)
        #expect(fired)
    }

    @Test func comboUsageCancels() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.interruption)            // ⌘C 等のコンボ利用
        let upAfterCombo = detector.process(.targetUp(0.1))
        let downAfterCombo = detector.process(.targetDown(0.15)) // 新しい 1 回目
        _ = detector.process(.targetUp(0.2))
        let fired = detector.process(.targetDown(0.3))
        #expect(!upAfterCombo)
        #expect(!downAfterCombo)
        #expect(fired)
    }

    @Test func interruptionWhileWaitingResets() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.targetUp(0.05))
        _ = detector.process(.interruption)            // 他の修飾キー押下
        let fired = detector.process(.targetDown(0.1)) // リセット済み → 1 回目
        #expect(!fired)
    }

    @Test func tripleTapFiresOnceThenRearms() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.targetUp(0.05))
        let second = detector.process(.targetDown(0.1)) // 2 回目で発火
        _ = detector.process(.targetUp(0.15))
        let third = detector.process(.targetDown(0.2))  // 3 打目は次サイクルの 1 回目
        #expect(second)
        #expect(!third)
    }

    @Test func modifierKeyCodeMapping() {
        #expect(DoubleTapModifier.from(keyCode: 54) == .rightCommand)
        #expect(DoubleTapModifier.from(keyCode: 55) == .leftCommand)
        #expect(DoubleTapModifier.from(keyCode: 1) == nil)
    }
}
