import RNapiCore
import SwiftUI
import UniformTypeIdentifiers

/// The download window: queue of movies with live status, drop target for
/// video files.
public struct DownloadQueueView: View {
    @Environment(DownloadSession.self) private var session

    public init() {}

    public var body: some View {
        @Bindable var session = session

        Group {
            if session.items.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .frame(minWidth: 480, minHeight: 280)
        .toolbar {
            ToolbarItem {
                Button("Add Movies…", systemImage: "plus") {
                    addMovies()
                }
            }
            ToolbarItem {
                Button("Clear Finished", systemImage: "trash") {
                    session.clearFinished()
                }
                .disabled(!session.items.contains(where: \.state.isFinished))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { $0.isFileURL }
            guard !files.isEmpty else { return false }
            session.enqueue(files)
            return true
        }
        .sheet(item: $session.pendingSelection) { selection in
            SubtitleSelectionSheet(selection: selection) {
                session.pendingSelection = nil
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Downloads", systemImage: "captions.bubble")
        } description: {
            Text("Drop video files here or click Add Movies to download subtitles.")
        } actions: {
            Button("Add Movies…") { addMovies() }
        }
    }

    private var queueList: some View {
        List(session.items) { item in
            HStack(spacing: 12) {
                statusIcon(for: item.state)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.movie.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusText(for: item.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .completed(let subtitle) = item.state {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([subtitle])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func statusIcon(for state: DownloadSession.ItemState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .awaitingSelection:
            Image(systemName: "questionmark.circle").foregroundStyle(.orange)
        default:
            ProgressView().controlSize(.small)
        }
    }

    private func statusText(for state: DownloadSession.ItemState) -> String {
        switch state {
        case .queued: String(localized: "Waiting…")
        case .hashing: String(localized: "Analyzing file…")
        case .searching(let engine): String(localized: "Searching \(engine)…")
        case .awaitingSelection: String(localized: "Choose subtitles…")
        case .downloading: String(localized: "Downloading…")
        case .postProcessing: String(localized: "Processing…")
        case .completed(let subtitle): subtitle.lastPathComponent
        case .failed(let message): message
        }
    }

    private func addMovies() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .avi, .quickTimeMovie]
        panel.message = String(localized: "Choose video files to download subtitles for")
        if panel.runModal() == .OK {
            session.enqueue(panel.urls)
        }
    }
}

/// Modal list of found subtitles; resolves the pipeline's continuation.
struct SubtitleSelectionSheet: View {
    let selection: PendingSelection
    let dismiss: () -> Void

    @State private var picked: FoundSubtitle.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitles for \(selection.movie.lastPathComponent)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Table(selection.subtitles, selection: $picked) {
                TableColumn("") { subtitle in
                    if subtitle.resolution == .good {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }
                .width(20)
                TableColumn("Title", value: \.title)
                TableColumn("Engine", value: \.engineID).width(110)
                TableColumn("Language") { subtitle in
                    Text(subtitle.language.englishName)
                }
                .width(90)
                TableColumn("Details", value: \.comment)
            }
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Do Not Download") {
                    selection.resolve(nil)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Download") {
                    let chosen = selection.subtitles.first { $0.id == picked }
                        ?? selection.subtitles.first
                    selection.resolve(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.subtitles.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560)
        .onAppear {
            picked = selection.subtitles.first(where: { $0.resolution == .good })?.id
                ?? selection.subtitles.first?.id
        }
    }
}

extension UTType {
    static let avi = UTType(filenameExtension: "avi") ?? .movie
}
