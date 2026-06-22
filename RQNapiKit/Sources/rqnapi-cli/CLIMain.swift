import ArgumentParser
import DownloadPipeline
import Foundation
import RQNapiCore
import RQNapiSettings

@main
struct RQNapiCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rqnapi-cli",
        abstract: "Download subtitles for video files.",
        discussion: """
            Files are processed with the same engines and settings as the \
            RQNapi app. Directories are scanned recursively for video files.
            """)

    @Argument(
        help: "Video files or directories to download subtitles for.",
        completion: .file())
    var paths: [String] = []

    @Option(name: [.customShort("l"), .long], help: "Subtitle language (two-letter code).")
    var language: String?

    @Option(
        name: [.customLong("bl"), .long],
        help: "Backup subtitle language used when the primary finds nothing.")
    var backupLanguage: String?

    @Option(name: [.customShort("f"), .long], help: "Convert to format: subrip, microdvd, mpl2, tmplayer.")
    var format: String?

    @Option(name: [.customShort("e"), .long], help: "Force target subtitle file extension.")
    var `extension`: String?

    @Flag(name: [.customShort("q"), .long], help: "Quiet batch mode: auto-pick the best subtitle.")
    var quiet = false

    @Flag(help: "Always show the subtitle list prompt.")
    var showList = false

    @Flag(help: "Never show the subtitle list prompt.")
    var dontShowList = false

    @Option(help: "OpenSubtitles API key (overrides the stored setting).")
    var osApiKey: String?

    @Flag(help: "List supported subtitle languages and exit.")
    var listLanguages = false

    mutating func validate() throws {
        if listLanguages { return }
        guard !paths.isEmpty else {
            throw ValidationError("Provide at least one video file or directory.")
        }
        if showList && dontShowList {
            throw ValidationError("--show-list and --dont-show-list are mutually exclusive.")
        }
        if let language, SubtitleLanguage(language) == nil {
            throw ValidationError("Unknown language: \(language)")
        }
        if let backupLanguage, SubtitleLanguage(backupLanguage) == nil {
            throw ValidationError("Unknown backup language: \(backupLanguage)")
        }
        if let format, SubtitleFormatNames.all.contains(format) == false {
            throw ValidationError(
                "Unknown format: \(format). Use one of: \(SubtitleFormatNames.all.joined(separator: ", "))")
        }
    }

    func run() async throws {
        if listLanguages {
            for lang in SubtitleLanguage.all {
                print("\(lang.twoLetter)  \(lang.threeLetter)  \(lang.englishName)")
            }
            return
        }

        var stored = SettingsStore().load()
        applyOverrides(to: &stored)

        let movies = resolveMovies(scan: stored.scan)
        guard !movies.isEmpty else {
            throw ValidationError("No video files found in the given paths.")
        }

        let credentialStore = KeychainCredentialStore()
        let engines = EngineFactory.makeEngines(
            order: stored.engineOrder,
            enabled: stored.enabledEngines,
            credentials: { credentialStore.credentials(forEngine: $0) },
            openSubtitlesApiKey: stored.openSubtitlesApiKey)

        guard !engines.isEmpty else {
            throw ValidationError(
                "No subtitle engines available. Check engine settings (an OpenSubtitles API key may be required).")
        }

        let pipelineConfiguration = PipelineConfiguration(
            language: SubtitleLanguage(stored.languageCode) ?? SubtitleLanguage("pl")!,
            backupLanguage: stored.backupLanguageCode.flatMap(SubtitleLanguage.init),
            searchPolicy: stored.searchPolicy,
            downloadPolicy: stored.downloadPolicy,
            postProcessing: stored.postProcessing,
            changePermissionsTo: stored.changePermissionsTo)

        let pipeline = SubtitleDownloadPipeline(
            engines: engines,
            selector: stored.downloadPolicy == .neverShowList
                ? BestMatchSelector() : StdinSubtitleSelector(),
            configuration: pipelineConfiguration)

        var summary = PipelineSummary()
        for await event in pipeline.run(movies: movies) {
            printEvent(event, summary: &summary)
        }

        print("\nDone: \(summary.succeeded.count) ok, \(summary.failed.count) failed.")
        if !summary.failed.isEmpty {
            throw ExitCode(1)
        }
    }

    // MARK: - Helpers

    private func applyOverrides(to configuration: inout AppConfiguration) {
        if let language { configuration.languageCode = language }
        if let backupLanguage { configuration.backupLanguageCode = backupLanguage }
        if let osApiKey { configuration.openSubtitlesApiKey = osApiKey }
        if let format {
            configuration.postProcessing.enabled = true
            configuration.postProcessing.targetFormatName = format
        }
        if let ext = `extension` {
            configuration.postProcessing.enabled = true
            configuration.postProcessing.targetExtension = ext
        }
        if quiet || dontShowList {
            configuration.downloadPolicy = .neverShowList
        } else if showList {
            configuration.downloadPolicy = .alwaysShowList
        }
    }

    private func resolveMovies(scan: ScanSettings) -> [URL] {
        var movies: [URL] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            else {
                FileHandle.standardError.write(Data("Skipping missing path: \(path)\n".utf8))
                continue
            }
            if isDirectory.boolValue {
                movies.append(
                    contentsOf: DirectoryScanner().scan(
                        directory: url,
                        movieExtensions: scan.filters,
                        skipIfSubtitlesExist: scan.skipIfSubtitlesExist,
                        followSymlinks: scan.followSymlinks))
            } else {
                movies.append(url)
            }
        }
        return movies
    }

    private func printEvent(_ event: PipelineEvent, summary: inout PipelineSummary) {
        switch event {
        case .fileStarted(let movie):
            print("→ \(movie.lastPathComponent)")
        case .hashing:
            break
        case .searching(_, let engineID, let language):
            print("  searching \(engineID) (\(language.twoLetter))...")
        case .resultsFound(_, let subtitles):
            print("  found \(subtitles.count) subtitle(s)")
        case .awaitingSelection:
            break
        case .downloading(_, let subtitle):
            print("  downloading from \(subtitle.engineID): \(subtitle.title)")
        case .postProcessing:
            print("  post-processing...")
        case .fileCompleted(let movie, let subtitle):
            print("  ✓ \(subtitle.lastPathComponent)")
            summary.succeeded.append(movie)
        case .fileFailed(let movie, let failure):
            print("  ✗ \(describe(failure))")
            summary.failed.append((movie, failure))
        }
    }

    private func describe(_ failure: PipelineFailure) -> String {
        switch failure {
        case .hashingFailed: "could not read the file"
        case .noSubtitlesFound: "no subtitles found"
        case .selectionCancelled: "selection cancelled"
        case .downloadFailed(let reason): "download failed: \(reason)"
        case .matchFailed(let reason): "could not write subtitles: \(reason)"
        }
    }
}

/// Format names accepted by `-f`.
enum SubtitleFormatNames {
    static let all = ["subrip", "microdvd", "mpl2", "tmplayer"]
}

/// Prompts on stdin when several subtitles are available.
struct StdinSubtitleSelector: SubtitleSelector {
    func choose(from subtitles: [FoundSubtitle], movie: URL) async -> FoundSubtitle? {
        print("  Multiple subtitles for \(movie.lastPathComponent):")
        for (index, subtitle) in subtitles.enumerated() {
            let marker = subtitle.resolution == .good ? "*" : " "
            print("   [\(index + 1)]\(marker) \(subtitle.engineID): \(subtitle.title) \(subtitle.comment)")
        }
        print("  Choose [1-\(subtitles.count)], empty = best, 0 = skip: ", terminator: "")

        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return bestMatch(in: subtitles)
        }
        if line.isEmpty { return bestMatch(in: subtitles) }
        guard let number = Int(line) else { return bestMatch(in: subtitles) }
        if number == 0 { return nil }
        guard (1...subtitles.count).contains(number) else { return bestMatch(in: subtitles) }
        return subtitles[number - 1]
    }
}
