import Foundation

/// 修飾キー単体ダブルタップの判定状態機械（G-3 / §8.2）。
/// NSEvent に依存しない純粋ロジック — イベント変換は HotkeyService 側で行う。
/// 判定窓 W は「1 回目の押下から 2 回目の押下まで」≤ 300ms（N-5）。
struct DoubleTapDetector {

    enum Input: Equatable {
        case targetDown(TimeInterval)
        case targetUp(TimeInterval)
        /// 他のキー・他の修飾キーの押下（コンボ利用 = ダブルタップではない）
        case interruption
    }

    private enum State {
        case idle
        case armed(firstDown: TimeInterval)        // 1 回目押下中
        case comboUsed                             // 押下中に他キーが押された（⌘C 等）
        case waitingSecond(firstDown: TimeInterval) // 1 回目解放済み・2 回目待ち
    }

    private var state: State = .idle
    let window: TimeInterval

    init(window: TimeInterval = 0.3) {
        self.window = window
    }

    /// 発火（ダブルタップ成立）したら true。
    /// 状態 × 入力の遷移表そのものなので複雑度警告は抑制。
    mutating func process(_ input: Input) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        switch (state, input) {
        case (.idle, .targetDown(let time)):
            state = .armed(firstDown: time)
        case (.idle, _):
            break // 押していないキーの解放情報・割り込みは無視
        case (.armed, .interruption):
            state = .comboUsed
        case (.armed(let firstDown), .targetUp):
            state = .waitingSecond(firstDown: firstDown)
        case (.armed, .targetDown):
            break // 重複した押下イベント（モニタ二重登録等）は無視
        case (.comboUsed, .targetUp):
            state = .idle
        case (.comboUsed, _):
            break // 押しっぱなしでのコンボ連打は無視
        case (.waitingSecond(let firstDown), .targetDown(let time)):
            if time - firstDown <= window {
                state = .idle
                return true
            }
            // 窓を超えていたら「新しい 1 回目」として仕切り直す
            state = .armed(firstDown: time)
        case (.waitingSecond, .targetUp):
            break // 解放済みキーへの重複解放情報（リマッパー由来等）は無視
        case (.waitingSecond, .interruption):
            state = .idle
        }
        return false
    }
}

/// flagsChanged イベントを DoubleTapDetector の入力へ変換する共通ロジック
/// （HotkeyService とレコーダー UI で共用）。
///
/// ⌘英かな・Karabiner 等のキーリマッパーは「⌘単体タップ＝英数/かな」を実現するため、
/// 修飾キー解放イベントの keyCode を書き換えることがある（2026-06-12 Ken の実機ログで
/// 右⌘の解放が keyCode=104=かな として届くのを確認）。そのため解放の判定は keyCode に
/// 依存せず「対象クラスのフラグビットの消失」で行う。
enum ModifierEventTranslator {

    /// nil = この検出対象には無関係なイベント
    static func input(
        for target: DoubleTapModifier,
        keyCode: UInt16,
        rawFlags: UInt,
        timestamp: TimeInterval
    ) -> DoubleTapDetector.Input? {
        let classIsDown = rawFlags & target.classFlagMask != 0

        if keyCode == target.keyCode {
            return classIsDown ? .targetDown(timestamp) : .targetUp(timestamp)
        }
        // 他の修飾キーの押下はコンボ利用とみなしてキャンセル（§8.2）
        if let other = DoubleTapModifier.from(keyCode: keyCode),
           other.classFlagMask != target.classFlagMask,
           rawFlags & other.classFlagMask != 0 {
            return .interruption
        }
        // keyCode が書き換えられていても、対象クラスのフラグが消えていれば解放とみなす
        if !classIsDown {
            return .targetUp(timestamp)
        }
        return nil
    }
}

extension DoubleTapModifier {
    /// NSEvent.ModifierFlags の device-independent ビット（AppKit 非依存で持つ）
    var classFlagMask: UInt {
        switch self {
        case .leftCommand, .rightCommand: 1 << 20  // .command
        case .leftShift, .rightShift: 1 << 17      // .shift
        case .leftOption, .rightOption: 1 << 19    // .option
        case .leftControl, .rightControl: 1 << 18  // .control
        }
    }
}

/// ダブルタップ対象にできる修飾キー（左右を keyCode で区別する）
enum DoubleTapModifier: String, Codable, CaseIterable, Equatable, Sendable {
    case leftCommand
    case rightCommand
    case leftOption
    case rightOption
    case leftControl
    case rightControl
    case leftShift
    case rightShift

    var keyCode: UInt16 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        }
    }

    static func from(keyCode: UInt16) -> DoubleTapModifier? {
        allCases.first { $0.keyCode == keyCode }
    }

    var displayName: String {
        switch self {
        case .leftCommand: String(localized: "Left ⌘ double-tap")
        case .rightCommand: String(localized: "Right ⌘ double-tap")
        case .leftOption: String(localized: "Left ⌥ double-tap")
        case .rightOption: String(localized: "Right ⌥ double-tap")
        case .leftControl: String(localized: "Left ⌃ double-tap")
        case .rightControl: String(localized: "Right ⌃ double-tap")
        case .leftShift: String(localized: "Left ⇧ double-tap")
        case .rightShift: String(localized: "Right ⇧ double-tap")
        }
    }
}
