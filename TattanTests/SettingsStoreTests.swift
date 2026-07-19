import Foundation
import Testing
@testable import Tattan

@MainActor
struct SettingsStoreTests {

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    /// デフォルト値が要件の確定値（N-1〜N-4 / N-2 / E-1 / O-3 / F-5）と一致していることの番犬
    @Test func defaultsMatchRequirements() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        #expect(store.historyLimit == 100)          // N-1
        #expect(store.autoDeleteEnabled == false)   // N-2
        #expect(store.autoDeleteDays == 30)         // N-2
        #expect(store.previewLength == 50)          // N-3
        #expect(store.syncSizeThresholdMB == 10)    // E-1
        #expect(store.uiScale == 1.0)               // N-4（100%）
        #expect(store.syncDecision == .undecided)   // E-5
        #expect(store.skipConcealedContent == true) // O-3（既定 ON = 記録しない）
        #expect(store.appearance == .system)        // F-5（既定 = OS 追従）
    }

    @Test func skipConcealedContentPersists() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.skipConcealedContent = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.skipConcealedContent == false)
    }

    @Test func appearancePersists() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appearance = .dark

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.appearance == .dark)
    }

    @Test func appearanceRawValuesAreStable() throws {
        // UserDefaults に書かれる raw 文字列が後で変わると、ユーザーの選択がリセットされる
        #expect(AppearancePreference.system.rawValue == "system")
        #expect(AppearancePreference.light.rawValue == "light")
        #expect(AppearancePreference.dark.rawValue == "dark")
    }

    @Test func valuesPersistAcrossInstances() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.historyLimit = 300
        store.syncDecision = .enabled
        store.excludedBundleIdentifiers = ["com.example.app"]

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.historyLimit == 300)
        #expect(reloaded.syncDecision == .enabled)
        #expect(reloaded.excludedBundleIdentifiers == ["com.example.app"])
    }
}
