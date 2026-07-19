import Foundation
import SwiftData

/// スニペット（architecture.md §2.4）。
/// `content` はテンプレート変数トークンを含む展開前の生テキスト（D-3。展開はペースト時）。
/// CloudKit 互換のためリレーションは optional（§2.1）。
@Model
final class Snippet {
    var uuid: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var createdAt: Date = Date()
    /// LWW 同期（E-3）の観測・デバッグ用
    var updatedAt: Date = Date()
    /// 一覧の手動並び順（D-2 左ペイン）
    var sortOrder: Int = 0
    /// HotkeyBinding の JSON エンコード（D-5）。レコードに載せることで Mac 間で同期される（§8.4）
    var hotkeyData: Data?
    var tags: [Tag]? = []

    init() {}
}
