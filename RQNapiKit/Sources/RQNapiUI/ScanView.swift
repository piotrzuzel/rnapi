import DownloadPipeline
import RQNapiSettings
import SwiftUI

/// Scan-directories window (legacy frmScan): pick a folder, tune filters,
/// review the found movies and enqueue the selected ones.
public struct ScanView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadSession.self) private var session
    @Environment(\.openWindow) private var openWindow

    @State private var directory: URL?
    @State private var filtersText = ""
    @State private var skipIfSubtitlesExist = false
    @State private var followSymlinks = false
    @State private var foundMovies: [URL] = []
    @State private var selected: Set<URL> = []
    @State private var isScanning = false
    @State private var hasScanned = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            directoryRow
            optionsRows
            resultsList
            bottomBar
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 420)
        .onAppear(perform: loadDefaults)
    }

    private var directoryRow: some View {
        HStack {
            Text("Directory:")
            Text(directory?.path ?? String(localized: "None selected"))
                .foregroundStyle(directory == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Choose…") { chooseDirectory() }
        }
    }

    private var optionsRows: some View {
        Group {
            TextField(
                "File types:", text: $filtersText,
                prompt: Text("space-separated extensions, e.g. mkv avi mp4"))
            HStack(spacing: 16) {
                Toggle("Skip movies with existing subtitles", isOn: $skipIfSubtitlesExist)
                Toggle("Follow symbolic links", isOn: $followSymlinks)
            }
        }
    }

    private var resultsList: some View {
        Group {
            if isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if foundMovies.isEmpty {
                ContentUnavailableView {
                    Label(
                        hasScanned ? "No Movies Found" : "No Scan Yet",
                        systemImage: "film.stack")
                } description: {
                    Text(
                        hasScanned
                            ? "No matching video files in the chosen directory."
                            : "Choose a directory and click Scan.")
                }
            } else {
                List(foundMovies, id: \.self) { movie in
                    Toggle(isOn: binding(for: movie)) {
                        Text(relativePath(of: movie))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Select All") { selected = Set(foundMovies) }
                .disabled(foundMovies.isEmpty)
            Button("Select None") { selected = [] }
                .disabled(foundMovies.isEmpty)
            Button("Invert") { selected = Set(foundMovies).symmetricDifference(selected) }
                .disabled(foundMovies.isEmpty)
            Spacer()
            Button("Scan") { scan() }
                .disabled(directory == nil || isScanning)
            Button("Download Subtitles") {
                session.enqueue(foundMovies.filter(selected.contains))
                openWindow(id: RQNapiScenes.WindowID.downloads)
                NSApp.activate()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
    }

    // MARK: - Actions

    private func loadDefaults() {
        guard filtersText.isEmpty else { return }
        let scan = settings.configuration.scan
        filtersText = scan.filters.joined(separator: " ")
        skipIfSubtitlesExist = scan.skipIfSubtitlesExist
        followSymlinks = scan.followSymlinks
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = String(localized: "Choose a directory to scan for video files")
        if panel.runModal() == .OK {
            directory = panel.url
        }
    }

    private func scan() {
        guard let directory else { return }

        let filters = filtersText
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*.")) }
            .filter { !$0.isEmpty }
        let skip = skipIfSubtitlesExist
        let symlinks = followSymlinks

        settings.update {
            $0.scan.filters = filters
            $0.scan.skipIfSubtitlesExist = skip
            $0.scan.followSymlinks = symlinks
        }

        isScanning = true
        Task.detached {
            let movies = DirectoryScanner().scan(
                directory: directory,
                movieExtensions: filters,
                skipIfSubtitlesExist: skip,
                followSymlinks: symlinks)
            await MainActor.run {
                foundMovies = movies
                selected = Set(movies)
                isScanning = false
                hasScanned = true
            }
        }
    }

    private func binding(for movie: URL) -> Binding<Bool> {
        Binding(
            get: { selected.contains(movie) },
            set: { isOn in
                if isOn { selected.insert(movie) } else { selected.remove(movie) }
            })
    }

    private func relativePath(of movie: URL) -> String {
        guard let directory else { return movie.lastPathComponent }
        let prefix = directory.path + "/"
        return movie.path.hasPrefix(prefix)
            ? String(movie.path.dropFirst(prefix.count)) : movie.path
    }
}
