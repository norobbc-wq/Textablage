import Foundation
import XCTest
@testable import TextablageCore

final class TextablageCoreTests: XCTestCase {
    private let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let secondDate = Date(timeIntervalSince1970: 1_700_000_050)

    private func temporaryRepository() throws -> ClipRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ClipRepository(directory: directory)
    }

    private func wireClip(id: String = "web_clip_1", text: String = "Text", title: String = "",
                          favorite: Bool = false, created: Double = 1_700_000_000_000,
                          updated: Double = 1_700_000_050_000) -> [String: Any] {
        ["id": id, "text": text, "title": title, "favorite": favorite,
         "createdAt": created, "updatedAt": updated]
    }

    private func backup(_ clips: [[String: Any]], exportedAt: Any = 1_700_000_060_000) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["app": "textablage", "version": 1,
                                                    "exportedAt": exportedAt, "clips": clips])
    }

    func testMissingCollectionIsEmptyAndDoesNotClaimSharedAccess() throws {
        let repository = try temporaryRepository()
        XCTAssertFalse(repository.usesSharedContainer)
        XCTAssertEqual(try repository.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.storageURL.path))
    }

    func testRepositoryRoundTripPreservesFullUnicodeAndWhitespace() throws {
        let repository = try temporaryRepository()
        let text = "  مرحباً 👨‍👩‍👧‍👦\r\n\tCafe\u{301} — Ende  \n"
        let saved = try repository.mutate {
            try ClipOperations.add(&$0, text: text, title: "  العنوان  ", favorite: true, now: firstDate)
        }
        let loaded = try ClipRepository(directory: repository.directory).load()
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(Data(loaded[0].text.utf8), Data(text.utf8))
        XCTAssertTrue(loaded[0].favorite)
    }

    func testMutationsRereadAnotherRepositorysCommit() throws {
        let one = try temporaryRepository()
        let two = ClipRepository(directory: one.directory)
        try one.mutate { try ClipOperations.add(&$0, text: "eins", now: firstDate) }
        try two.mutate { try ClipOperations.add(&$0, text: "zwei", now: firstDate) }
        try one.mutate { try ClipOperations.add(&$0, text: "drei", now: firstDate) }
        XCTAssertEqual(Set(try two.load().map(\.text)), Set(["eins", "zwei", "drei"]))
    }

    func testConcurrentRepositoriesDoNotLoseAdds() throws {
        let one = try temporaryRepository()
        let two = ClipRepository(directory: one.directory)
        let errors = ErrorCollector()
        let now = firstDate
        DispatchQueue.concurrentPerform(iterations: 60) { index in
            do {
                let repository = index.isMultiple(of: 2) ? one : two
                try repository.mutate { try ClipOperations.add(&$0, text: "Text \(index)", now: now) }
            } catch { errors.append(error) }
        }
        XCTAssertEqual(errors.count, 0)
        let clips = try one.load()
        XCTAssertEqual(clips.count, 60)
        XCTAssertEqual(Set(clips.map(\.text)).count, 60)
    }

    func testCorruptFileCannotBeOverwrittenByMutation() throws {
        let repository = try temporaryRepository()
        let original = Data("{broken but irreplaceable".utf8)
        try original.write(to: repository.storageURL)
        XCTAssertThrowsError(try repository.load())
        var wasCalled = false
        XCTAssertThrowsError(try repository.mutate {
            wasCalled = true
            try ClipOperations.add(&$0, text: "replacement", now: firstDate)
        })
        XCTAssertFalse(wasCalled)
        XCTAssertEqual(try Data(contentsOf: repository.storageURL), original)
    }

    func testAbortedTransformLeavesFileBytesUnchanged() throws {
        let repository = try temporaryRepository()
        try repository.mutate { try ClipOperations.add(&$0, text: "vorhanden", now: firstDate) }
        let original = try Data(contentsOf: repository.storageURL)
        XCTAssertThrowsError(try repository.mutate {
            try ClipOperations.add(&$0, text: "abgebrochen", now: secondDate)
            throw ClipError.entryNotFound
        })
        XCTAssertEqual(try Data(contentsOf: repository.storageURL), original)
        XCTAssertEqual(try repository.load().map(\.text), ["vorhanden"])
    }

    func testInvalidTransformedCollectionLeavesFileBytesUnchanged() throws {
        let repository = try temporaryRepository()
        try repository.mutate { try ClipOperations.add(&$0, text: "original", now: firstDate) }
        let original = try Data(contentsOf: repository.storageURL)
        XCTAssertThrowsError(try repository.mutate { entries in entries.append(entries[0]) })
        XCTAssertEqual(try Data(contentsOf: repository.storageURL), original)
    }

    func testDirectoryAtStoragePathIsAnErrorWithoutDeletion() throws {
        let repository = try temporaryRepository()
        try FileManager.default.createDirectory(at: repository.storageURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.mutate { try ClipOperations.add(&$0, text: "a", now: firstDate) })
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.storageURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testNonUUIDIdentifierInNativeStoreIsRejectedWithoutReset() throws {
        let repository = try temporaryRepository()
        let original = try backup([wireClip()])
        try original.write(to: repository.storageURL)
        XCTAssertThrowsError(try repository.mutate { $0.removeAll() })
        XCTAssertEqual(try Data(contentsOf: repository.storageURL), original)
    }

    func testCRLFDeduplicationPreservesFirstTextAndMetadata() throws {
        var clips: [ClipEntry] = []
        let original = try ClipOperations.add(&clips, text: "  eins\r\nzwei  ", title: "Titel",
                                              favorite: true, now: firstDate)
        let recopy = try ClipOperations.add(&clips, text: "  eins\nzwei  ", title: "Anderer Titel",
                                            favorite: false, now: secondDate)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(recopy.id, original.id)
        XCTAssertEqual(Data(recopy.text.utf8), Data(original.text.utf8))
        XCTAssertEqual(recopy.title, "Titel")
        XCTAssertTrue(recopy.favorite)
        XCTAssertEqual(recopy.createdAt, firstDate)
        XCTAssertEqual(recopy.updatedAt, secondDate)
    }

    func testDifferentUnicodeEncodingsAreDistinctAndPreserved() throws {
        var clips: [ClipEntry] = []
        try ClipOperations.add(&clips, text: "caf\u{e9}", now: firstDate)
        try ClipOperations.add(&clips, text: "cafe\u{301}", now: firstDate)
        XCTAssertEqual(clips.count, 2)
        let encoded = try BackupCodec.encode(clips)
        var decoded: [ClipEntry] = []
        XCTAssertEqual(try BackupCodec.merge(encoded, into: &decoded), 2)
        XCTAssertEqual(Set(clips.map { Data($0.text.utf8) }), Set(decoded.map { Data($0.text.utf8) }))
    }

    func testRecopyNeverMovesUpdatedDateBackward() throws {
        var clips: [ClipEntry] = []
        try ClipOperations.add(&clips, text: "Text", now: secondDate)
        let updated = try ClipOperations.add(&clips, text: "Text", now: firstDate)
        XCTAssertEqual(updated.updatedAt, secondDate)
    }

    func testUpdateConflictIsAtomicAndFavoriteToggleKeepsText() throws {
        var clips: [ClipEntry] = []
        let one = try ClipOperations.add(&clips, text: "eins\r\nzwei", now: firstDate)
        let two = try ClipOperations.add(&clips, text: "anderer Text", now: firstDate)
        let before = clips
        XCTAssertThrowsError(try ClipOperations.update(&clips, id: two.id, title: "neu", text: "eins\nzwei",
                                                       favorite: true, now: secondDate))
        XCTAssertEqual(clips, before)
        try ClipOperations.toggleFavorite(&clips, id: one.id, now: secondDate)
        let changed = try XCTUnwrap(clips.first { $0.id == one.id })
        XCTAssertTrue(changed.favorite)
        XCTAssertEqual(Data(changed.text.utf8), Data(one.text.utf8))
        XCTAssertEqual(changed.updatedAt, secondDate)
        try ClipOperations.delete(&clips, id: one.id)
        XCTAssertEqual(clips.map(\.id), [two.id])
    }

    func testSearchFindsEveryWordAcrossTitleAndEntireText() throws {
        let matching = ClipEntry(title: "CAFÉ", text: "Anfang\n" + String(repeating: "lang ", count: 1_000) + " العربية Ende",
                                 favorite: true, createdAt: firstDate, updatedAt: secondDate)
        let wrong = ClipEntry(title: "Café", text: "kein Treffer", createdAt: firstDate)
        XCTAssertEqual(ClipSearch.filtered([wrong, matching], query: "cafe ENDE العربية"), [matching])
        XCTAssertEqual(ClipSearch.filtered([wrong, matching], favoritesOnly: true), [matching])
        XCTAssertEqual(ClipSearch.filtered([wrong, matching]).first?.id, matching.id)
    }

    func testWebBackupImportsSafeNonUUIDIdentifiersWithoutTextLoss() throws {
        let text = " \tالعربية\r\n👩🏽‍💻\nCafe\u{301}  "
        let data = try backup([wireClip(id: "legacy_123-A", text: text, title: " عنوان ", favorite: true)])
        var clips: [ClipEntry] = []
        XCTAssertEqual(try BackupCodec.merge(data, into: &clips), 1)
        XCTAssertEqual(Data(clips[0].text.utf8), Data(text.utf8))
        XCTAssertEqual(clips[0].title, " عنوان ")
        XCTAssertTrue(clips[0].favorite)
        XCTAssertEqual(clips[0].createdAt, firstDate)
        XCTAssertEqual(clips[0].updatedAt, secondDate)
        let encoded = try BackupCodec.encode(clips, now: secondDate)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["app"] as? String, "textablage")
        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertEqual((envelope["exportedAt"] as? NSNumber)?.int64Value, 1_700_000_050_000)
        var roundTrip: [ClipEntry] = []
        try BackupCodec.merge(encoded, into: &roundTrip)
        XCTAssertEqual(roundTrip, clips)
    }

    func testUUIDCollisionRemapsIdentifierWithoutLosingEitherText() throws {
        let existing = ClipEntry(text: "vorhanden", createdAt: firstDate)
        var clips = [existing]
        let data = try backup([wireClip(id: existing.id.uuidString, text: "importiert")])
        XCTAssertEqual(try BackupCodec.merge(data, into: &clips), 1)
        XCTAssertEqual(Set(clips.map(\.id)).count, 2)
        XCTAssertEqual(Set(clips.map(\.text)), Set(["vorhanden", "importiert"]))
        XCTAssertEqual(clips.first { $0.text == "vorhanden" }?.id, existing.id)
    }

    func testUUIDCaseCollisionWithinBackupRemapsWithoutLoss() throws {
        let id = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        var clips: [ClipEntry] = []
        XCTAssertEqual(try BackupCodec.merge(backup([wireClip(id: id, text: "A"),
                                                     wireClip(id: id.lowercased(), text: "B")]), into: &clips), 2)
        XCTAssertEqual(Set(clips.map(\.id)).count, 2)
    }

    func testImportDuplicateAgainstCollectionPreservesOriginal() throws {
        let existing = ClipEntry(title: "Original", text: "eins\r\nzwei", favorite: true, createdAt: firstDate)
        var clips = [existing]
        XCTAssertEqual(try BackupCodec.merge(backup([wireClip(text: "eins\nzwei", title: "Import")]), into: &clips), 0)
        XCTAssertEqual(clips, [existing])
    }

    func testMalformedBackupNeverPartiallyMutatesCollection() throws {
        let existing = ClipEntry(text: "vorhanden", createdAt: firstDate)
        var clips = [existing]
        var malformed = wireClip(id: "bad", text: "kaputt")
        malformed["favorite"] = 1
        XCTAssertThrowsError(try BackupCodec.merge(backup([wireClip(text: "gültig"), malformed]), into: &clips))
        XCTAssertEqual(clips, [existing])
    }

    func testDuplicateRawIdentifiersAndNormalizedTextsRejectWholeBackup() throws {
        let existing = ClipEntry(text: "vorhanden", createdAt: firstDate)
        for imported in [[wireClip(id: "same", text: "A"), wireClip(id: "same", text: "B")],
                         [wireClip(id: "a", text: "A\r\nB"), wireClip(id: "b", text: "A\nB")]] {
            var clips = [existing]
            XCTAssertThrowsError(try BackupCodec.merge(backup(imported), into: &clips))
            XCTAssertEqual(clips, [existing])
        }
    }

    func testInvalidDatesAndIdentifiersAreRejected() throws {
        let badDates: [Double] = [-1, 1.5, 8_640_000_000_000_001]
        for date in badDates {
            var clips: [ClipEntry] = []
            XCTAssertThrowsError(try BackupCodec.merge(backup([wireClip(created: date)]), into: &clips))
            XCTAssertTrue(clips.isEmpty)
        }
        for identifier in ["", "spaces are invalid", "الاسم", String(repeating: "a", count: 129)] {
            var clips: [ClipEntry] = []
            XCTAssertThrowsError(try BackupCodec.merge(backup([wireClip(id: identifier)]), into: &clips))
        }
        var clips: [ClipEntry] = []
        XCTAssertThrowsError(try BackupCodec.merge(backup([wireClip(created: 100, updated: 99)]), into: &clips))
        XCTAssertThrowsError(try BackupCodec.merge(backup([wireClip()], exportedAt: true), into: &clips))
        XCTAssertThrowsError(try ClipOperations.add(&clips, text: "A", now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertTrue(clips.isEmpty)
    }

    func testUTF16LimitCountsEmojiAsTwoUnitsAndDoesNotTrimWhitespace() throws {
        var clips: [ClipEntry] = []
        try ClipOperations.add(&clips, text: String(repeating: "😀", count: 100_000), now: firstDate)
        XCTAssertThrowsError(try ClipOperations.add(&clips, text: String(repeating: "😀", count: 100_001), now: firstDate))
        XCTAssertThrowsError(try ClipOperations.add(&clips, text: "", now: firstDate))
        try ClipOperations.add(&clips, text: "  \n ", now: firstDate)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].text, "  \n ")
    }

    func testOversizedBackupAndCombinedCollectionAreRejectedAtomically() throws {
        let existing = ClipEntry(text: "vorhanden", createdAt: firstDate)
        var clips = [existing]
        XCTAssertThrowsError(try BackupCodec.merge(Data(repeating: 32, count: 25 * 1_024 * 1_024 + 1), into: &clips))
        XCTAssertEqual(clips, [existing])
        let largeTitle = String(repeating: "a", count: 200_000)
        let candidate = (0..<132).map {
            ClipEntry(title: largeTitle, text: "Text \($0)", createdAt: firstDate)
        }
        XCTAssertThrowsError(try BackupCodec.encode(candidate))
        let repository = try temporaryRepository()
        try repository.mutate { $0 = [existing] }
        let before = try Data(contentsOf: repository.storageURL)
        XCTAssertThrowsError(try repository.mutate { $0 = candidate })
        XCTAssertEqual(try Data(contentsOf: repository.storageURL), before)
    }

    func testCollectionCountLimitIsEnforced() throws {
        var clips = (0..<10_000).map { ClipEntry(text: "\($0)", createdAt: firstDate) }
        XCTAssertThrowsError(try ClipOperations.add(&clips, text: "zusätzlich", now: firstDate))
        XCTAssertEqual(clips.count, 10_000)
        clips.append(ClipEntry(text: "zusätzlich", createdAt: firstDate))
        XCTAssertThrowsError(try BackupCodec.encode(clips))
    }
}

private final class ErrorCollector {
    private let lock = NSLock()
    private var errors: [Error] = []
    func append(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return errors.count
    }
}
