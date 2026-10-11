import Foundation
import CoreFoundation

public enum BackupCodec {
    public static func encode(_ entries: [ClipEntry], now: Date = Date()) throws -> Data {
        try ClipValidation.entries(entries)
        try ClipValidation.date(now)
        let clips: [[String: Any]] = entries.map { entry in
            ["id": entry.id.uuidString,
             "title": entry.title,
             "text": entry.text,
             "favorite": entry.favorite,
             "createdAt": milliseconds(entry.createdAt),
             "updatedAt": milliseconds(entry.updatedAt)]
        }
        let envelope: [String: Any] = ["app": "textablage", "version": 1,
                                       "exportedAt": milliseconds(now), "clips": clips]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        guard data.count <= ClipValidation.maximumBytes else { throw ClipError.fileTooLarge }
        return data
    }

    @discardableResult
    public static func merge(_ data: Data, into entries: inout [ClipEntry]) throws -> Int {
        try ClipValidation.entries(entries)
        let imported = try decode(data)
        var candidate = entries
        var identifiers = Set(candidate.map(\.id))
        var keys = Set(candidate.map { ClipValidation.textKey($0.text) })
        var added = 0
        for var source in imported {
            let key = ClipValidation.textKey(source.text)
            guard !keys.contains(key) else { continue }
            guard candidate.count < ClipValidation.maximumClips else { throw ClipError.collectionFull }
            while identifiers.contains(source.id) { source.id = UUID() }
            identifiers.insert(source.id)
            keys.insert(key)
            candidate.append(source)
            added += 1
        }
        try ClipValidation.entries(candidate)
        // Validate the combined byte limit before touching the caller's array.
        _ = try encode(candidate)
        entries = ClipSearch.filtered(candidate)
        return added
    }

    static func decode(_ data: Data, requireNativeIdentifiers: Bool = false) throws -> [ClipEntry] {
        guard data.count <= ClipValidation.maximumBytes else { throw ClipError.fileTooLarge }
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) }
        catch { throw ClipError.invalidBackup }
        guard let envelope = parsed as? [String: Any],
              envelope["app"] as? String == "textablage",
              let version = integer(envelope["version"]), version == 1,
              integer(envelope["exportedAt"]) != nil,
              let clips = envelope["clips"] as? [[String: Any]] else { throw ClipError.invalidBackup }
        guard clips.count <= ClipValidation.maximumClips else { throw ClipError.collectionFull }
        var rawIDs = Set<Data>()
        var nativeIDs = Set<UUID>()
        var textKeys = Set<Data>()
        var result: [ClipEntry] = []
        result.reserveCapacity(clips.count)
        for clip in clips {
            guard let rawID = clip["id"] as? String, safeIdentifier(rawID),
                  let title = clip["title"] as? String,
                  let text = clip["text"] as? String,
                  let favorite = boolean(clip["favorite"]),
                  let created = integer(clip["createdAt"]),
                  let updated = integer(clip["updatedAt"]), updated >= created else {
                throw ClipError.invalidBackup
            }
            try ClipValidation.text(text)
            try ClipValidation.text(title, allowEmpty: true)
            guard rawIDs.insert(Data(rawID.utf8)).inserted else { throw ClipError.duplicateIdentifier }
            guard textKeys.insert(ClipValidation.textKey(text)).inserted else { throw ClipError.duplicateText }
            let parsedID = UUID(uuidString: rawID)
            if requireNativeIdentifiers && (parsedID == nil || nativeIDs.contains(parsedID!)) {
                throw ClipError.invalidBackup
            }
            var identifier = parsedID ?? UUID()
            while nativeIDs.contains(identifier) { identifier = UUID() }
            nativeIDs.insert(identifier)
            result.append(ClipEntry(id: identifier, title: title, text: text, favorite: favorite,
                                    createdAt: Date(timeIntervalSince1970: created / 1_000),
                                    updatedAt: Date(timeIntervalSince1970: updated / 1_000)))
        }
        try ClipValidation.entries(result)
        return result
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func integer(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= ClipValidation.maximumMilliseconds,
              value.rounded(.towardZero) == value else { return nil }
        return value
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func safeIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...128).contains(bytes.count) && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
