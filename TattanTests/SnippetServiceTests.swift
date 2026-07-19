import Foundation
import SwiftData
import Testing
@testable import Tattan

@MainActor
struct SnippetServiceTests {

    private func makeFixture() throws -> (service: SnippetService, persistence: PersistenceController) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetServiceTests-\(UUID().uuidString)", isDirectory: true)
        let persistence = try PersistenceController(directory: directory, cloudKitEnabled: false)
        return (SnippetService(persistence: persistence), persistence)
    }

    @Test func createAssignsIncrementingSortOrder() throws {
        let (service, _) = try makeFixture()
        let first = service.createSnippet(title: "a")
        let second = service.createSnippet(title: "b")
        #expect(second.sortOrder == first.sortOrder + 1)
        #expect(service.fetchSnippets().map(\.title) == ["a", "b"])
    }

    @Test func tagNamedIsCaseInsensitiveFindOrCreate() throws {
        let (service, _) = try makeFixture()
        let first = service.tag(named: "Mail")
        let second = service.tag(named: "mail")
        #expect(first === second)
        #expect(service.fetchTags().count == 1)
    }

    /// LWW 同期マージで同名タグが二重化したケースの起動時リペア（§2.4）
    @Test func mergeDuplicateTagsUnifies() throws {
        let (service, persistence) = try makeFixture()
        let context = persistence.mainContainer.mainContext

        let tag1 = Tattan.Tag()
        tag1.name = "work"
        context.insert(tag1)
        let tag2 = Tattan.Tag()
        tag2.name = "Work"
        context.insert(tag2)

        let snippet = Snippet()
        snippet.title = "s"
        context.insert(snippet)
        snippet.tags = [tag2]
        try context.save()

        service.mergeDuplicateTags()

        #expect(service.fetchTags().count == 1)
        #expect((service.fetchSnippets().first?.tags ?? []).count == 1)
    }

    @Test func promoteCreatesSnippetFromHistoryItem() throws {
        let (service, _) = try makeFixture()
        let item = ClipHistoryItem()
        item.plainText = "Line one\nLine two"

        let snippet = service.promote(item)

        #expect(snippet.title == "Line one")
        #expect(snippet.content == "Line one\nLine two")
        #expect(service.fetchSnippets().count == 1)
    }

    @Test func deleteRemovesSnippet() throws {
        let (service, _) = try makeFixture()
        let snippet = service.createSnippet(title: "gone")
        service.delete(snippet)
        #expect(service.fetchSnippets().isEmpty)
    }

    @Test func renameTagChangesName() throws {
        let (service, _) = try makeFixture()
        let tag = service.tag(named: "mali")
        service.renameTag(tag, to: "mail")
        #expect(service.fetchTags().map(\.name) == ["mail"])
    }

    /// 既存グループと同名への改名は統合される（スニペットは統合先グループに残る）
    @Test func renameTagToExistingNameMerges() throws {
        let (service, _) = try makeFixture()
        let mail = service.tag(named: "mail")
        let temp = service.tag(named: "temp")
        let snippet = service.createSnippet(title: "s", content: "c", tags: [temp])

        service.renameTag(temp, to: "mail")

        #expect(service.fetchTags().count == 1)
        #expect(service.fetchTags().first === mail || service.fetchTags().first?.name == "mail")
        #expect((snippet.tags ?? []).map(\.name) == ["mail"])
    }

    @Test func moveTagsReordersGroups() throws {
        let (service, _) = try makeFixture()
        _ = service.tag(named: "alpha")
        _ = service.tag(named: "beta")
        _ = service.tag(named: "gamma")

        // gamma（index 2）を先頭へ
        service.moveTags(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(service.fetchTags().map(\.name) == ["gamma", "alpha", "beta"])
    }

    /// グループ削除はスニペットを消さず「グループ無し」にする
    @Test func deleteTagLeavesSnippetsUngrouped() throws {
        let (service, _) = try makeFixture()
        let tag = service.tag(named: "doomed")
        let snippet = service.createSnippet(title: "stays", content: "c", tags: [tag])

        service.deleteTag(tag)

        #expect(service.fetchTags().isEmpty)
        #expect(service.fetchSnippets().count == 1)
        #expect((snippet.tags ?? []).isEmpty)
    }
}
