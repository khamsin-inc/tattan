import AppKit
import Foundation
import Observation

/// アプリ設定（UserDefaults バック）。設定は端末ローカルで iCloud 同期しない（§4.2）。
/// デフォルト値は要件 N-1〜N-3・E-1 で確定した値。
@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    /// 履歴保存上限（C-2 / N-1: 既定 100。設定 UI では 1〜1000 にクランプする）
    var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    /// 自動削除（C-7 / N-2: 既定 OFF）
    var autoDeleteEnabled: Bool {
        didSet { defaults.set(autoDeleteEnabled, forKey: Keys.autoDeleteEnabled) }
    }

    /// 自動削除の保持日数（N-2: 有効化時の初期値 30 日）
    var autoDeleteDays: Int {
        didSet { defaults.set(autoDeleteDays, forKey: Keys.autoDeleteDays) }
    }

    /// 履歴プレビューの表示文字数（F-9 / N-3: 既定 50。previewText は 500 文字保存済みなので表示側で切る）
    var previewLength: Int {
        didSet { defaults.set(previewLength, forKey: Keys.previewLength) }
    }

    /// iCloud 同期から除外するサイズ閾値 MB（E-1: 既定 10。判定はキャプチャ時のみ・遡及なし）
    var syncSizeThresholdMB: Int {
        didSet { defaults.set(syncSizeThresholdMB, forKey: Keys.syncSizeThresholdMB) }
    }

    /// 履歴に残さないアプリの bundle identifier（C-6 / H-5）
    var excludedBundleIdentifiers: [String] {
        didSet { defaults.set(excludedBundleIdentifiers, forKey: Keys.excludedBundleIdentifiers) }
    }

    /// UI 拡大率（F-7 / N-4: 0.7〜2.0 = 70〜200%）。ポップアップ・エディタの文字とアイコンに
    /// 適用、ネイティブ NSMenu はシステム標準のまま（2026-06-12 裁定 #6）。
    /// 2026-06-15 に 4 段階 enum からスライダー連続値へ変更
    var uiScale: Double {
        didSet { defaults.set(uiScale, forKey: Keys.uiScale) }
    }

    /// ポップアップの幅 pt（F-8 の補完。パネルの手動リサイズとも双方向で同期する）
    var popupWidth: Int {
        didSet { defaults.set(popupWidth, forKey: Keys.popupWidth) }
    }

    /// iCloud 同期の選択状態（E-5: 初回ダイアログで決定、設定画面で変更可能。
    /// 反映は再起動方式 = 起動時に一度だけ読まれる）
    var syncDecision: SyncDecision {
        didSet { defaults.set(syncDecision.rawValue, forKey: Keys.syncDecision) }
    }

    /// ConcealedType マーカー付き項目を履歴に保存しないか（O-3: 既定 ON = 保存しない）。
    /// OFF にするとユーザー責任でローカル履歴に保存（同期は引き続き除外）
    var skipConcealedContent: Bool {
        didSet { defaults.set(skipConcealedContent, forKey: Keys.skipConcealedContent) }
    }

    /// 外観（F-5）。System / Light / Dark を `NSApp.appearance` 経由で一括同期。
    /// didSet で即時反映するので Picker 切替の瞬間にウィンドウとポップアップが切り替わる
    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            appearance.applyToApp()
        }
    }

    /// UI 言語。既定は英語（システム言語に追従しない、Tattan の方針）。
    /// 変更は `AppleLanguages` への上書きで反映、即時には反映されないので再起動が必要
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            language.applyAsAppleLanguagesOverride()
        }
    }

    /// changeCount ポーリング間隔（§5.1: 既定 0.5 秒）。隠し設定（UI なし、defaults 直編集のみ）
    let pollingInterval: TimeInterval

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        historyLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 100
        autoDeleteEnabled = defaults.object(forKey: Keys.autoDeleteEnabled) as? Bool ?? false
        autoDeleteDays = defaults.object(forKey: Keys.autoDeleteDays) as? Int ?? 30
        previewLength = defaults.object(forKey: Keys.previewLength) as? Int ?? 50
        syncSizeThresholdMB = defaults.object(forKey: Keys.syncSizeThresholdMB) as? Int ?? 10
        excludedBundleIdentifiers = defaults.stringArray(forKey: Keys.excludedBundleIdentifiers) ?? []
        uiScale = (defaults.object(forKey: Keys.uiScale) as? Double).map { min(max($0, 0.7), 2.0) } ?? 1.0
        popupWidth = defaults.object(forKey: Keys.popupWidth) as? Int ?? 360
        syncDecision = (defaults.string(forKey: Keys.syncDecision)).flatMap(SyncDecision.init(rawValue:))
            ?? .undecided
        skipConcealedContent = defaults.object(forKey: Keys.skipConcealedContent) as? Bool ?? true
        appearance = (defaults.string(forKey: Keys.appearance)).flatMap(AppearancePreference.init(rawValue:))
            ?? .system
        language = (defaults.string(forKey: Keys.language)).flatMap(AppLanguage.init(rawValue:))
            ?? .english
        pollingInterval = defaults.object(forKey: Keys.pollingInterval) as? TimeInterval ?? 0.5
    }

    private enum Keys {
        static let historyLimit = "historyLimit"
        static let autoDeleteEnabled = "autoDeleteEnabled"
        static let autoDeleteDays = "autoDeleteDays"
        static let previewLength = "previewLength"
        static let syncSizeThresholdMB = "syncSizeThresholdMB"
        static let excludedBundleIdentifiers = "excludedBundleIdentifiers"
        static let uiScale = "uiScale"
        static let popupWidth = "popupWidth"
        static let syncDecision = "syncDecision"
        static let skipConcealedContent = "skipConcealedContent"
        static let appearance = "appearance"
        static let language = "language"
        static let pollingInterval = "pollingInterval"
    }
}

/// iCloud 同期の 3 状態（E-5）。undecided の間だけ初回ダイアログが出る
enum SyncDecision: String, Sendable {
    case undecided
    case enabled
    case disabled
}

/// 外観プリファレンス（F-5）。
/// `NSApp.appearance` 経由で SwiftUI ルート（Settings / Editor / SettingsWindow / Popup）と
/// AppKit（NSMenu / NSPanel）を一括同期する。`.system` は OS の外観に追従
enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

extension AppearancePreference {
    /// NSApp に反映する。`.system` のときは nil = OS の外観に追従。
    /// AppDependencies.bootstrap() の冒頭で 1 回 + SettingsStore.appearance.didSet で都度呼ぶ
    @MainActor func applyToApp() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// UI 言語（2026-06-30 追加）。Tattan は既定で英語、ユーザーが選んだら `AppleLanguages` に
/// 書き込んでシステム言語の優先順位を上書きする。Picker のラベルは「現地表記」で表示
/// （日本語なら "日本語"、中国語なら "简体中文"）
enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    /// 設定 Picker に出すラベル。各言語の母語話者がそれと分かる表記
    var nativeName: String {
        switch self {
        case .english:  return "English"
        case .japanese: return "日本語"
        }
    }
}

extension AppLanguage {
    /// `AppleLanguages` を [rawValue] で固定する。Bundle のリソース解決で
    /// この値が最優先になるため、次回起動から UI 言語が切り替わる。
    /// AppDependencies.bootstrap() の最初期 + SettingsStore.language.didSet で呼ぶ
    func applyAsAppleLanguagesOverride() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
    }
}
