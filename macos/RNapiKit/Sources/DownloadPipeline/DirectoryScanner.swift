import Foundation

/// Recursive movie-file discovery for "scan directories" (GUI) and
/// directory arguments (CLI).
public struct DirectoryScanner: Sendable {
    public init() {}

    /// Subtitle extensions checked for `skipIfSubtitlesExist`.
    private static let subtitleExtensions = ["srt", "sub", "txt"]

    public func scan(
        directory: URL,
        movieExtensions: [String],
        skipIfSubtitlesExist: Bool = false,
        followSymlinks: Bool = false
    ) -> [URL] {
        let lowered = Set(movieExtensions.map { $0.lowercased() })
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !followSymlinks {
            options.insert(.skipsPackageDescendants)
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options)
        else {
            return []
        }

        var movies: [URL] = []
        for case let url as URL in enumerator {
            guard lowered.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            if skipIfSubtitlesExist && hasExistingSubtitles(movie: url) {
                continue
            }
            movies.append(url)
        }
        return movies.sorted { $0.path < $1.path }
    }

    private func hasExistingSubtitles(movie: URL) -> Bool {
        let base = movie.deletingPathExtension()
        return Self.subtitleExtensions.contains { ext in
            FileManager.default.fileExists(atPath: base.appendingPathExtension(ext).path)
        }
    }
}
