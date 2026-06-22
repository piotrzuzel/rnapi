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
        Form {
            Section("Source") {
                LabeledContent("Directory") {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(directory?.path ?? String(localized: "None selected"))
                            .foregroundStyle(directory == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…") { chooseDirectory() }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        "File types", text: $filtersText,
                        prompt: Text("mkv avi mp4 …"))
                    Text("Space-separated file extensions to include.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Options") {
                Toggle("Skip movies with existing subtitles", isOn: $skipIfSubtitlesExist)
                Toggle("Follow symbolic links", isOn: $followSymlinks)
            }

            Section {
                resultsContent
            } header: {
                HStack(spacing: 8) {
                    Text("Movies")
                    Spacer()
                    if !foundMovies.isEmpty {
                        Text("\(foundMovies.count) found · \(selected.count) selected")
                            .foregroundStyle(.secondary)
                        Menu("Select") {
                            Button("All") { selected = Set(foundMovies) }
                            Button("None") { selected = [] }
                            Button("Invert") {
                                selected = Set(foundMovies).symmetricDifference(selected)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 460)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear(perform: loadDefaults)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if isScanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
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
            .frame(maxWidth: .infinity)
        } else {
            ForEach(foundMovies, id: \.self) { movie in
                Toggle(isOn: binding(for: movie)) {
                    Label(relativePath(of: movie), systemImage: "film")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button("Scan", systemImage: "magnifyingglass") { scan() }
                    .disabled(directory == nil || isScanning)
                Button("Download Subtitles") {
                    session.enqueue(foundMovies.filter(selected.contains))
                    openWindow(id: RQNapiScenes.WindowID.downloads)
                    NSApp.activate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
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
