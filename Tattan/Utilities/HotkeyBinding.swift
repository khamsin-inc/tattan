import Foundation

/// 「普通のキーコンボ」と「修飾キーダブルタップ」を 1 つで表す統一バインディング型（§8.1）。
/// レコーダー UI（P-1）・3 スロット（P-2）・スニペット個別（D-5）すべてこの型で保存する。
/// combo は Carbon 形式の生値で持ち、KeyboardShortcuts への変換はサービス層で行う
/// （Utilities をライブラリ非依存に保つ）。
enum HotkeyBinding: Codable, Equatable, Sendable {
    case combo(carbonKeyCode: Int, carbonModifiers: Int)
    case doubleTap(DoubleTapModifier)

    var encoded: Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data?) -> HotkeyBinding? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
