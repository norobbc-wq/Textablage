import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class ClipRepository {
    public let directory: URL
    public let usesSharedContainer: Bool
    public var storageURL: URL { directory.appendingPathComponent("clips.json") }
    private var lockURL: URL { directory.appendingPathComponent("clips.lock") }

    public init(sharedAccess: Bool = true) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        if sharedAccess,
           let group = Bundle.main.object(forInfoDictionaryKey: "TextablageAppGroup") as? String,
           !group.isEmpty,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            directory = container.appendingPathComponent("Textablage", isDirectory: true)
            usesSharedContainer = true
            return
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".textablage", isDirectory: true)
        directory = support.appendingPathComponent("Textablage", isDirectory: true)
        usesSharedContainer = false
    }

    public init(directory: URL) {
        self.directory = directory
        usesSharedContainer = false
    }

    public func load() throws -> [ClipEntry] {
        try withLock { try readUnlocked() }
    }

    @discardableResult
    public func mutate(_ transform: (inout [ClipEntry]) throws -> Void) throws -> [ClipEntry] {
        try withLock {
            var entries = try readUnlocked()
            try transform(&entries)
            try ClipValidation.entries(entries)
            let data = try BackupCodec.encode(entries)
            do {
                #if os(iOS) || os(tvOS) || os(watchOS)
                try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: storageURL, options: .atomic)
                #endif
            } catch {
                throw ClipError.unavailable(error.localizedDescription)
            }
            return entries
        }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS) || os(tvOS) || os(watchOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: directory.path)
            #endif
        } catch {
            throw ClipError.unavailable(error.localizedDescription)
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw ClipError.unavailable("Der Speicher konnte nicht gesperrt werden.") }
        defer { close(descriptor) }
        var result: Int32
        repeat { result = flock(descriptor, LOCK_EX) } while result == -1 && errno == EINTR
        guard result == 0 else { throw ClipError.unavailable("Der Speicher konnte nicht gesperrt werden.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func readUnlocked() throws -> [ClipEntry] {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw ClipError.unavailable("Die Speicherdatei ist ungültig.")
            }
            if let size = attributes[.size] as? NSNumber, size.int64Value > ClipValidation.maximumBytes {
                throw ClipError.fileTooLarge
            }
            let data = try Data(contentsOf: storageURL)
            return try BackupCodec.decode(data, requireNativeIdentifiers: true)
        } catch let error as ClipError {
            throw error
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileReadNoSuchFileError {
                return []
            }
            throw ClipError.unavailable(error.localizedDescription)
        }
    }
}
