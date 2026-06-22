import RQNapiSettings
import SwiftUI

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
        // First scene → the main window shown at launch.
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
