import CryptoKit
import Foundation

/// C-9（連続重複回避）の同一性判定に使うハッシュ（§5.3 [5]）。
/// kind を混ぜるのは「同じバイト列でも種別が違えば別物」として扱うため。
enum ContentHasher {
    static func hash(kind: ContentKind, payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
