import AppKit
import RQNapiSettings
import RQNapiUI
import SwiftUI

@main
struct RQNapiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        RQNapiScenes(settings: appDelegate.settings, session: appDelegate.session)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let session: DownloadSession

    private let launchDate = Date()

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.session = DownloadSession(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular windowed app: Dock icon + standard menu bar, no tray.
        NSApp.setActivationPolicy(.regular)
    }

    /// "Open with RQNapi" from Finder. Files arriving right after launch run
    /// in quiet batch mode: best match auto-picked, app quits when done
    /// (legacy behavior).
    func application(_ application: NSApplication, open urls: [URL]) {
        let movies = urls.filter(\.isFileURL)
        guard !movies.isEmpty else { return }

        let launchedJustNow = Date().timeIntervalSince(launchDate) < 1.0
        if launchedJustNow && settings.configuration.quietBatch {
            session.batchMode = true
            session.onBatchFinished = {
                NSApp.terminate(nil)
            }
        }
        session.enqueue(movies)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
