import Foundation
import SwiftData

/// スニペット分類用タグ（D-1: フォルダではなくタグ、多対多）。
/// タグ名の一意制約は CloudKit 互換のため DB では張れず、作成時にアプリロジックで
/// 重複チェックする。同期マージで生じうる同名タグは起動時に自動統合する（§2.4, Phase 2.6）。
@Model
final class Tag {
    var uuid: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    /// グループのアイコン（SF Symbol 名）。nil なら既定の folder。optional で CloudKit 非破壊（§2.4）
    var iconName: String?
    @Relationship(inverse: \Snippet.tags)
    var snippets: [Snippet]? = []

    init() {}
}

extension Tag: Identifiable {
    var id: UUID { uuid }
}
