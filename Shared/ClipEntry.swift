import Foundation

public struct ClipEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var text: String
    public var favorite: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", text: String, favorite: Bool = false,
                createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public enum ClipError: Error, LocalizedError, Equatable {
    case invalidText
    case textTooLong
    case invalidDate
    case duplicateText
    case duplicateIdentifier
    case entryNotFound
    case collectionFull
    case invalidBackup
    case fileTooLarge
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidText: return "Der Text darf nicht leer sein."
        case .textTooLong: return "Text und Titel dürfen jeweils höchstens 200.000 Zeichen enthalten."
        case .invalidDate: return "Ein Datum ist ungültig."
        case .duplicateText: return "Dieser Text ist bereits gespeichert."
        case .duplicateIdentifier: return "Eine Kennung ist doppelt vorhanden."
        case .entryNotFound: return "Dieser Eintrag wurde nicht gefunden."
        case .collectionFull: return "Es sind höchstens 10.000 Einträge möglich."
        case .invalidBackup: return "Die Datei ist keine gültige Textablage-Sicherung (Version 1)."
        case .fileTooLarge: return "Die Datei darf höchstens 25 MB groß sein."
        case .unavailable(let detail): return "Die Sammlung ist nicht verfügbar. Vorhandene Texte wurden nicht gelöscht. \(detail)"
        }
    }
}

enum ClipValidation {
    static let maximumClips = 10_000
    static let maximumUTF16Length = 200_000
    static let maximumBytes = 25 * 1_024 * 1_024
    static let maximumMilliseconds = 8_640_000_000_000_000.0

    // Swift String equality folds canonical Unicode equivalence. The web app
    // does not, so UTF-8 bytes preserve that distinction and original content.
    static func textKey(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\r\n", with: "\n").utf8)
    }

    static func text(_ text: String, allowEmpty: Bool = false) throws {
        guard allowEmpty || !text.isEmpty else { throw ClipError.invalidText }
        guard text.utf16.count <= maximumUTF16Length else { throw ClipError.textTooLong }
    }

    static func date(_ date: Date) throws {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite, milliseconds >= 0,
              milliseconds <= maximumMilliseconds else { throw ClipError.invalidDate }
    }

    static func entries(_ entries: [ClipEntry]) throws {
        guard entries.count <= maximumClips else { throw ClipError.collectionFull }
        var identifiers = Set<UUID>()
        var texts = Set<Data>()
        for entry in entries {
            try text(entry.text)
            try text(entry.title, allowEmpty: true)
            try date(entry.createdAt)
            try date(entry.updatedAt)
            guard entry.updatedAt >= entry.createdAt else { throw ClipError.invalidDate }
            guard identifiers.insert(entry.id).inserted else { throw ClipError.duplicateIdentifier }
            guard texts.insert(textKey(entry.text)).inserted else { throw ClipError.duplicateText }
        }
    }
}
