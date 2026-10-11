import Foundation

public enum ClipOperations {
    @discardableResult
    public static func add(_ entries: inout [ClipEntry], text: String, title: String = "",
                           favorite: Bool = false, now: Date = Date()) throws -> ClipEntry {
        try ClipValidation.entries(entries)
        try ClipValidation.text(text)
        try ClipValidation.text(title, allowEmpty: true)
        try ClipValidation.date(now)
        let key = ClipValidation.textKey(text)
        if let index = entries.firstIndex(where: { ClipValidation.textKey($0.text) == key }) {
            var existing = entries[index]
            existing.updatedAt = max(existing.updatedAt, now)
            // Recopying keeps the first exact text, title, favorite and identity.
            entries.remove(at: index)
            entries.insert(existing, at: 0)
            return existing
        }
        guard entries.count < ClipValidation.maximumClips else { throw ClipError.collectionFull }
        let existingIDs = Set(entries.map(\.id))
        var identifier = UUID()
        while existingIDs.contains(identifier) { identifier = UUID() }
        let entry = ClipEntry(id: identifier, title: title, text: text, favorite: favorite,
                              createdAt: now, updatedAt: now)
        entries.insert(entry, at: 0)
        return entry
    }

    public static func update(_ entries: inout [ClipEntry], id: UUID, title: String,
                              text: String, favorite: Bool, now: Date = Date()) throws {
        try ClipValidation.entries(entries)
        try ClipValidation.text(text)
        try ClipValidation.text(title, allowEmpty: true)
        try ClipValidation.date(now)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw ClipError.entryNotFound }
        let key = ClipValidation.textKey(text)
        guard !entries.contains(where: { $0.id != id && ClipValidation.textKey($0.text) == key }) else {
            throw ClipError.duplicateText
        }
        var updated = entries[index]
        updated.title = title
        updated.text = text
        updated.favorite = favorite
        updated.updatedAt = max(updated.updatedAt, now)
        entries[index] = updated
    }

    public static func toggleFavorite(_ entries: inout [ClipEntry], id: UUID,
                                      now: Date = Date()) throws {
        try ClipValidation.entries(entries)
        try ClipValidation.date(now)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw ClipError.entryNotFound }
        entries[index].favorite.toggle()
        entries[index].updatedAt = max(entries[index].updatedAt, now)
    }

    public static func delete(_ entries: inout [ClipEntry], id: UUID) throws {
        try ClipValidation.entries(entries)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw ClipError.entryNotFound }
        entries.remove(at: index)
    }
}

public enum ClipSearch {
    public static func filtered(_ entries: [ClipEntry], query: String = "",
                                favoritesOnly: Bool = false) -> [ClipEntry] {
        let words = folded(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { entry in
            guard !favoritesOnly || entry.favorite else { return false }
            let haystack = folded(entry.title + "\n" + entry.text)
            return words.allSatisfy { haystack.contains($0) }
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
