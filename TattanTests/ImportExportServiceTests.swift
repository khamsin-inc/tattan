import Foundation
import Testing
@testable import Tattan

@MainActor
struct ImportExportServiceTests {

    private struct Fixture {
        let settings: SettingsStore
        let persistence: PersistenceController
        let history: HistoryService
        let snippets: SnippetService
        let service: ImportExportService
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "ImportExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportExportTests-\(UUID().uuidString)", isDirectory: true)
        let persistence = try PersistenceController(directory: directory, cloudKitEnabled: false)
        let history = HistoryService(persistence: persistence, settings: settings)
        let snippets = SnippetService(persistence: persistence)
        let service = ImportExportService(history: history, snippets: snippets)
        return Fixture(settings: settings, persistence: persistence,
                       history: history, snippets: snippets, service: service)
    }

    private func textContent(_ text: String) -> ProcessedContent {
        ProcessedContent(content: CapturedContent(kind: .text, plainText: text))
    }

    @Test func roundTripSnippetsAndTags() async throws {
        let source = try makeFixture()
        let tag = source.snippets.tag(named: "mail")
        source.snippets.createSnippet(title: "greeting", content: "お世話になっております。", tags: [tag])

        let data = try source.service.exportData(includeHistory: false)

        let destination = try makeFixture()
        try await destination.service.importData(data)

        let imported = destination.snippets.fetchSnippets()
        #expect(imported.count == 1)
        #expect(imported.first?.title == "greeting")
        #expect((imported.first?.tags ?? []).map(\.name) == ["mail"])
    }

    @Test func historyRoundTripPreservesDates() async throws {
        let source = try makeFixture()
        source.history.apply(textContent("remember me"))
        let original = try #require(source.history.fetchHistory().first)

        let data = try source.service.exportData(includeHistory: true)

        let destination = try makeFixture()
        try await destination.service.importData(data)

        let imported = try #require(destination.history.fetchHistory().first)
        #expect(imported.plainText == "remember me")
        // ISO 8601 は秒精度なので 1 秒の誤差まで許容
        #expect(abs(imported.copiedAt.timeIntervalSince(original.copiedAt)) < 1.0)
    }

    /// O-2: クレカ検知項目は平文エクスポートに絶対に含めない
    @Test func creditCardHistoryIsNeverExported() throws {
        let source = try makeFixture()
        source.history.apply(textContent("カード: 4242 4242 4242 4242"))
        source.history.apply(textContent("normal text"))

        let data = try source.service.exportData(includeHistory: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ImportExportService.ExportFile.self, from: data)
        #expect(file.history?.count == 1)
        #expect(file.history?.first?.plainText == "normal text")
    }

    /// O-3: ConcealedType マーカー由来項目も平文エクスポートに含めない
    @Test func concealedHistoryIsNeverExported() throws {
        let source = try makeFixture()
        let concealed = ProcessedContent(content: CapturedContent(
            kind: .text, plainText: "secret-pass", hasConcealedMarker: true
        ))
        source.history.apply(concealed)
        source.history.apply(textContent("normal text"))

        let data = try source.service.exportData(includeHistory: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ImportExportService.ExportFile.self, from: data)
        #expect(file.history?.count == 1)
        #expect(file.history?.first?.plainText == "normal text")
    }

    @Test func importSkipsDuplicateSnippets() async throws {
        let fixture = try makeFixture()
        fixture.snippets.createSnippet(title: "dup", content: "same body")

        let data = try fixture.service.exportData(includeHistory: false)
        try await fixture.service.importData(data) // 同じストアに再インポート

        #expect(fixture.snippets.fetchSnippets().count == 1)
    }

    @Test func rejectsForeignJSON() async throws {
        let fixture = try makeFixture()
        let bogus = Data(#"{"hello": "world"}"#.utf8)
        await #expect(throws: ImportExportService.ImportError.self) {
            try await fixture.service.importData(bogus)
        }
    }
}
