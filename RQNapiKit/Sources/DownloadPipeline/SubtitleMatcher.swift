import Foundation
import RQNapiCore
import SubtitleFormats

public enum MatchError: Error, Sendable {
    case subtitleMissing
    case targetNotWritable(String)
    case copyFailed(String)
}

/// Places a downloaded subtitle next to its movie. The single place in the
/// app that mutates the movie's directory (clear old subtitles, write, chmod)
/// — keep it that way so a future sandboxed build has one seam to adapt.
/// Port of legacy `subtitlematcher.cpp`.
public struct SubtitleMatcher: Sendable {
    /// Subtitle file extensions the matcher recognizes when clearing a
    /// movie's previous subtitles.
    static let subtitleExtensions: Set<String> = ["srt", "sub", "txt"]

    public struct Configuration: Sendable {
        public var postProcessingEnabled: Bool
        public var targetFormatName: String?
        public var targetExtension: String?
        /// Octal permission string like "644"; nil leaves permissions alone.
        public var changePermissionsTo: String?

        public init(
            postProcessingEnabled: Bool = false,
            targetFormatName: String? = nil,
            targetExtension: String? = nil,
            changePermissionsTo: String? = nil
        ) {
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

        // Leave exactly one subtitle file per movie: clear any previous ones
        // (including a different extension, or a legacy "<name>_copy.<ext>").
        try removeExistingSubtitles(for: movie)

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

    private func subtitlePath(for movie: URL, extension ext: String) -> URL {
        movie.deletingLastPathComponent()
            .appendingPathComponent(
                movie.deletingPathExtension().lastPathComponent + "." + ext)
    }

    /// Removes every existing subtitle file belonging to `movie` so that only
    /// the freshly downloaded one remains. Matches the movie's base name with
    /// any recognized subtitle extension, plus the legacy "<base>_copy" backup
    /// names earlier versions produced.
    private func removeExistingSubtitles(for movie: URL) throws {
        let directory = movie.deletingLastPathComponent()
        let base = movie.deletingPathExtension().lastPathComponent

        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            guard Self.subtitleExtensions.contains(entry.pathExtension.lowercased()) else {
                continue
            }
            let entryBase = entry.deletingPathExtension().lastPathComponent
            if entryBase == base || entryBase == base + "_copy" {
                try fileManager.removeItem(at: entry)
            }
        }
    }
}
