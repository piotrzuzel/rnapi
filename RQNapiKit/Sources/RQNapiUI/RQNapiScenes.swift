import AppKit
import DownloadPipeline
import RQNapiSettings
import SwiftUI
import UniformTypeIdentifiers

/// All app scenes, bundled so the app target stays a thin shell. The app
/// creates the shared model objects and passes them in.
public struct RQNapiScenes: Scene {
    private let settings: AppSettings
    private let session: DownloadSession

    public init(settings: AppSettings, session: DownloadSession) {
        self.settings = settings
        self.session = session
    }

    public var body: some Scene {
        MenuBarExtra("RQNapi", systemImage: "captions.bubble") {
            MenuBarContent()
                .environment(settings)
                .environment(session)
        }

        Window("RQNapi Downloads", id: WindowID.downloads) {
            DownloadQueueView()
                .environment(settings)
                .environment(session)
        }
        .defaultSize(width: 560, height: 340)

        Window("Scan Directories", id: WindowID.scan) {
            ScanView()
                .environment(settings)
                .environment(session)
        }
        .defaultSize(width: 560, height: 460)

        Window("Convert Subtitles", id: WindowID.converter) {
            ConverterView()
        }
        .defaultSize(width: 480, height: 420)

        Settings {
            RQNapiSettingsView()
                .environment(settings)
        }
    }

    public enum WindowID {
        public static let downloads = "downloads"
        public static let scan = "scan"
        public static let converter = "converter"
    }
}

private struct MenuBarContent: View {
    @Environment(DownloadSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Download Subtitles…") {
            openWindow(id: RQNapiScenes.WindowID.downloads)
            NSApp.activate()
            addMovies()
        }

        Button("Scan Directories…") {
            openWindow(id: RQNapiScenes.WindowID.scan)
            NSApp.activate()
        }

        Button("Convert Subtitles…") {
            openWindow(id: RQNapiScenes.WindowID.converter)
            NSApp.activate()
        }

        Divider()

        Button("Show Downloads") {
            openWindow(id: RQNapiScenes.WindowID.downloads)
            NSApp.activate()
        }

        Divider()

        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }

        Button("About RQNapi") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "RQNapi",
                .credits: NSAttributedString(
                    string: String(
                        localized: "Subtitle downloader for macOS.\nEngines: NapiProjekt, OpenSubtitles, Napisy24."
                    ))
            ])
        }

        Divider()

        Button("Quit RQNapi") {
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

}
