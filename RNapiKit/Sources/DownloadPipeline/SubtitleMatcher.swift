import Foundation
import RNapiCore
import SubtitleFormats

public enum MatchError: Error, Sendable {
    case subtitleMissing
    case targetNotWritable(String)
    case copyFailed(String)
}

/// Places a downloaded subtitle next to its movie. The single place in the
/// app that mutates the movie's directory (backup, write, chmod) — keep it
/// that way so a future sandboxed build has one seam to adapt.
/// Port of legacy `subtitlematcher.cpp`.
public struct SubtitleMatcher: Sendable {
    public struct Configuration: Sendable {
        /// When false, an existing subtitle is renamed to "<name>_copy.<ext>".
        public var noBackup: Bool
        public var postProcessingEnabled: Bool
        public var targetFormatName: String?
        public var targetExtension: String?
        /// Octal permission string like "644"; nil leaves permissions alone.
        public var changePermissionsTo: String?

        public init(
            noBackup: Bool = false,
            postProcessingEnabled: Bool = false,
            targetFormatName: String? = nil,
            targetExtension: String? = nil,
            changePermissionsTo: String? = nil
        ) {
            self.noBackup = noBackup
            self.postProcessingEnabled = postProcessingEnabled
            self.targetFormatName = targetFormatName
            self.targetExtension = targetExtension
            self.changePermissionsTo = changePermissionsTo
        }
    }

    private let configuration: Configuration
    private var fileManager: FileManager { .default }

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Copies `subtitle` next to `movie` and returns the final URL.
    @discardableResult
    public func match(subtitle: URL, movie: URL) throws -> URL {
        guard fileManager.fileExists(atPath: subtitle.path) else {
            throw MatchError.subtitleMissing
        }

        let targetExtension = selectTargetExtension(source: subtitle)
        let target = subtitlePath(for: movie, extension: targetExtension)

        let directory = target.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw MatchError.targetNotWritable(directory.path)
        }

        try backupOrRemoveExisting(target: target, movie: movie)

        do {
            try fileManager.copyItem(at: subtitle, to: target)
        } catch {
            throw MatchError.copyFailed(error.localizedDescription)
        }

        if let mode = configuration.changePermissionsTo,
           let permissions = Int(mode, radix: 8)
        {
            try? fileManager.setAttributes(
                [.posixPermissions: permissions], ofItemAtPath: target.path)
        }

        return target
    }

    func selectTargetExtension(source: URL) -> String {
        var targetExtension = source.pathExtension
        if configuration.postProcessingEnabled {
            if let formatName = configuration.targetFormatName,
               configuration.targetExtension == nil,
               let format = SubtitleFormatsRegistry.format(named: formatName)
            {
                targetExtension = format.defaultExtension
            } else if let forced = configuration.targetExtension {
                targetExtension = forced
            }
        }
        return targetExtension
    }

    private func subtitlePath(for movie: URL, extension ext: String, suffix: String = "") -> URL {
        movie.deletingLastPathComponent()
            .appendingPathComponent(
                movie.deletingPathExtension().lastPathComponent + suffix + "." + ext)
    }

    private func backupOrRemoveExisting(target: URL, movie: URL) throws {
        guard fileManager.fileExists(atPath: target.path) else { return }

        if configuration.noBackup {
            try fileManager.removeItem(at: target)
        } else {
            let backup = subtitlePath(
                for: movie, extension: target.pathExtension, suffix: "_copy")
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.moveItem(at: target, to: backup)
        }
    }
}
