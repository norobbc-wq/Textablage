#if canImport(Combine)
import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
public final class SharedClipStore: ObservableObject {
    @Published public private(set) var clips: [ClipEntry] = []
    @Published public private(set) var errorMessage: String?
    public var usesSharedContainer: Bool { repository.usesSharedContainer }
    private let repository: ClipRepository

    public init(repository: ClipRepository = ClipRepository()) {
        self.repository = repository
        reload()
    }

    public func reload() {
        do {
            clips = try repository.load()
            errorMessage = nil
        } catch {
            // A failed read preserves the last successfully loaded display.
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func add(text: String, title: String = "", favorite: Bool = false) throws -> ClipEntry {
        var added: ClipEntry?
        try commit { entries in added = try ClipOperations.add(&entries, text: text, title: title, favorite: favorite) }
        return added!
    }

    public func update(id: UUID, title: String, text: String, favorite: Bool) throws {
        try commit { entries in
            try ClipOperations.update(&entries, id: id, title: title, text: text, favorite: favorite)
        }
    }

    public func toggleFavorite(id: UUID) throws {
        try commit { entries in try ClipOperations.toggleFavorite(&entries, id: id) }
    }

    public func delete(id: UUID) throws {
        try commit { entries in try ClipOperations.delete(&entries, id: id) }
    }

    @discardableResult
    public func mergeBackupData(_ data: Data) throws -> Int {
        var count = 0
        try commit { entries in count = try BackupCodec.merge(data, into: &entries) }
        return count
    }

    public func backupData() throws -> Data {
        do {
            let current = try repository.load()
            let data = try BackupCodec.encode(current)
            clips = current
            errorMessage = nil
            return data
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func commit(_ operation: (inout [ClipEntry]) throws -> Void) throws {
        do {
            clips = try repository.mutate(operation)
            errorMessage = nil
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
#endif
