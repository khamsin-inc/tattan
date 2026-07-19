import Foundation
import SwiftData

/// クリップボード履歴の種別（C-1: テキスト・画像・RTF・ファイルパス）。
/// CloudKit ミラーリングは enum を直接永続化できないため、モデルには rawValue を保存する（§2.1）。
enum ContentKind: String, Codable, Sendable {
    case text
    case richText
    case image
    case fileReference
}

/// 機微情報の種別（O-1/O-2/O-3）。`.concealed` は ConcealedType マーカー由来で、
/// 設定 `skipConcealedContent = false` のときだけ履歴に到達する（既定は到達しない）。
enum Sensitivity: String, Codable, Sendable {
    case none
    case creditCard
    case concealed
}

/// クリップボード履歴 1 件（architecture.md §2.3）。
///
/// CloudKit ミラーリング互換の制約（§2.1）に従う:
/// - 全プロパティがデフォルト値を持つ
/// - `@Attribute(.unique)` は使わない（一意性は `uuid` とアプリロジックで担保）
///
/// 同一型を mainContainer / localContainer の両方に登録して使う（§2.2 の 2 コンテナ戦略）。
@Model
final class ClipHistoryItem {
    // copiedAt: 履歴一覧のソートで毎回触る。
    // contentHash: 履歴全体での完全マッチ検索（apply の双子検出）が高頻度で走る
    #Index<ClipHistoryItem>([\.copiedAt], [\.contentHash])

    /// アプリレベルの一意識別子
    var uuid: UUID = UUID()
    /// 初回キャプチャ時刻
    var createdAt: Date = Date()
    /// 最後にペーストボードに載った時刻。一覧のソートキー（履歴からのペーストで先頭に浮上する）
    var copiedAt: Date = Date()
    /// ContentKind の rawValue
    var kindRaw: String = ContentKind.text.rawValue
    /// 一覧表示専用の事前計算テキスト（先頭 500 文字, F-9）。クレカ項目はマスク済み文字列を入れる（§6.3）
    var previewText: String = ""
    /// 画像のみ: 一覧表示用サムネイル（長辺 200px / JPEG / 目標 50KB 以下）
    var thumbnailData: Data?
    /// text / richText のプレーンテキスト実体
    var plainText: String?
    /// richText の RTF 実体（ペースト時のみロード）
    @Attribute(.externalStorage) var rtfData: Data?
    /// image の原本（ペースト時のみロード）
    @Attribute(.externalStorage) var binaryData: Data?
    /// fileReference: 改行区切りのフルパス列
    var filePathsJoined: String?
    /// 正規化済み実体の SHA-256（C-9 連続重複判定）
    var contentHash: String = ""
    /// 実体のバイト数（E-1 同期サイズ閾値の判定記録）
    var byteSize: Int = 0
    /// Sensitivity の rawValue
    var sensitivityRaw: String = Sensitivity.none.rawValue

    init() {}
}

extension ClipHistoryItem {
    var kind: ContentKind {
        get { ContentKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: sensitivityRaw) ?? .none }
        set { sensitivityRaw = newValue.rawValue }
    }
}
