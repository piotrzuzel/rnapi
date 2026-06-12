import AppKit
import DownloadPipeline
import QNapiSettings
import SwiftUI
import UniformTypeIdentifiers

/// All app scenes, bundled so the app target stays a thin shell. The app
/// creates the shared model objects and passes them in.
public struct QNapiScenes: Scene {
    private let settings: AppSettings
    private let session: DownloadSession

    public init(settings: AppSettings, session: DownloadSession) {
        self.settings = settings
        self.session = session
    }

    public var body: some Scene {
        MenuBarExtra("QNapi", systemImage: "captions.bubble") {
            MenuBarContent()
                .environment(settings)
                .environment(session)
        }

        Window("QNapi Downloads", id: WindowID.downloads) {
            DownloadQueueView()
                .environment(settings)
                .environment(session)
        }
        .defaultSize(width: 560, height: 340)

        Window("Convert Subtitles", id: WindowID.converter) {
            ConverterView()
        }
        .defaultSize(width: 480, height: 420)

        Settings {
            QNapiSettingsView()
                .environment(settings)
        }
    }

    public enum WindowID {
        public static let downloads = "downloads"
        public static let converter = "converter"
    }
}

private struct MenuBarContent: View {
    @Environment(DownloadSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Download Subtitles…") {
            openWindow(id: QNapiScenes.WindowID.downloads)
            NSApp.activate()
            addMovies()
        }

        Button("Scan Directory…") {
            scanDirectory()
        }

        Button("Convert Subtitles…") {
            openWindow(id: QNapiScenes.WindowID.converter)
            NSApp.activate()
        }

        Divider()

        Button("Show Downloads") {
            openWindow(id: QNapiScenes.WindowID.downloads)
            NSApp.activate()
        }

        Divider()

        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }

        Button("About QNapi") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "QNapi",
                .credits: NSAttributedString(
                    string: String(
                        localized: "Subtitle downloader for macOS.\nEngines: NapiProjekt, OpenSubtitles, Napisy24."
                    ))
            ])
        }

        Divider()

        Button("Quit QNapi") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func addMovies() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Choose video files to download subtitles for")
        if panel.runModal() == .OK {
            session.enqueue(panel.urls)
        }
    }

    private func scanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = String(localized: "Choose a directory to scan for video files")
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        openWindow(id: QNapiScenes.WindowID.downloads)
        NSApp.activate()

        let scanSettings = session.scanSettings
        let session = self.session
        Task.detached {
            let movies = DirectoryScanner().scan(
                directory: directory,
                movieExtensions: scanSettings.filters,
                skipIfSubtitlesExist: scanSettings.skipIfSubtitlesExist,
                followSymlinks: scanSettings.followSymlinks)
            await MainActor.run {
                session.enqueue(movies)
            }
        }
    }
}
