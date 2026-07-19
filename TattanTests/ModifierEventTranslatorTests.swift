import Testing
@testable import Tattan

/// flagsChanged → DoubleTapDetector 入力変換のテスト。
/// 特にキーリマッパー（⌘英かな・Karabiner 等）環境の回帰を固定する。
struct ModifierEventTranslatorTests {

    private struct FlagsEvent {
        let keyCode: UInt16
        let flags: UInt
        let time: Double
    }

    private let cmdFlag: UInt = 1 << 20
    private let shiftFlag: UInt = 1 << 17

    /// イベント列を右⌘の検出器に流し、どこかで発火したかを返す
    private func runSequence(_ events: [FlagsEvent]) -> Bool {
        var detector = DoubleTapDetector(window: 0.3)
        var fired = false
        for event in events {
            guard let input = ModifierEventTranslator.input(
                for: .rightCommand, keyCode: event.keyCode, rawFlags: event.flags, timestamp: event.time
            ) else { continue }
            if detector.process(input) { fired = true }
        }
        return fired
    }

    @Test func vanillaPressAndRelease() {
        let down = ModifierEventTranslator.input(
            for: .rightCommand, keyCode: 54, rawFlags: cmdFlag, timestamp: 0
        )
        let up = ModifierEventTranslator.input(
            for: .rightCommand, keyCode: 54, rawFlags: 0, timestamp: 0.1
        )
        #expect(down == .targetDown(0))
        #expect(up == .targetUp(0.1))
    }

    /// 2026-06-12 Ken 実機ログの回帰テスト:
    /// リマッパーが右⌘の解放イベントを keyCode=104（JIS かな）に書き換えて送ってくる環境でも
    /// ダブルタップが成立すること
    @Test func remappedReleaseKeyCodeStillFires() {
        let fired = runSequence([
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.00), // 1 回目押下
            FlagsEvent(keyCode: 104, flags: 0, time: 0.06),      // 解放（keyCode 書き換え済み）
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.15)  // 2 回目押下 → 発火
        ])
        #expect(fired)
    }

    /// モニタの二重登録などで同一イベントが重複して届いても誤動作しないこと
    @Test func duplicateEventsDoNotBreakDetection() {
        let fired = runSequence([
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.00),
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.00),
            FlagsEvent(keyCode: 104, flags: 0, time: 0.06),
            FlagsEvent(keyCode: 104, flags: 0, time: 0.06),
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.15),
            FlagsEvent(keyCode: 54, flags: cmdFlag, time: 0.15)
        ])
        #expect(fired)
    }

    @Test func otherModifierPressIsInterruption() {
        // 右⌘待ち中に左⇧が押された（⌘は押しっぱなし）→ コンボ利用 = キャンセル
        let input = ModifierEventTranslator.input(
            for: .rightCommand, keyCode: 56, rawFlags: cmdFlag | shiftFlag, timestamp: 0
        )
        #expect(input == .interruption)
    }

    @Test func unrelatedKeyWhileTargetHeldIsIgnored() {
        // 対象クラスが押下中のままの無関係イベントは nil（検出器に流さない）
        let input = ModifierEventTranslator.input(
            for: .rightCommand, keyCode: 104, rawFlags: cmdFlag, timestamp: 0
        )
        #expect(input == nil)
    }

    @Test func strayReleaseWhileWaitingDoesNotReset() {
        var detector = DoubleTapDetector(window: 0.3)
        _ = detector.process(.targetDown(0))
        _ = detector.process(.targetUp(0.05))
        _ = detector.process(.targetUp(0.08)) // リマッパー由来の重複解放情報
        let fired = detector.process(.targetDown(0.15))
        #expect(fired)
    }
}
