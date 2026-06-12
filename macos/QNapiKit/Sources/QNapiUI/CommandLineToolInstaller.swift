import AppKit
import Foundation

/// Symlinks the bundled qnapi-cli into /usr/local/bin. Falls back to an
/// admin-privileged AppleScript when the directory isn't user-writable.
@MainActor
enum CommandLineToolInstaller {
    static let linkPath = "/usr/local/bin/qnapi-cli"

    enum Status {
        case installed
        case notInstalled
        case bundledCLIMissing
    }

    static var bundledCLI: URL? {
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/qnapi-cli")
        return FileManager.default.fileExists(atPath: helper.path) ? helper : nil
    }

    static func status() -> Status {
        guard let cli = bundledCLI else { return .bundledCLIMissing }
        let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
        return existing == cli.path ? .installed : .notInstalled
    }

    /// Returns nil on success, otherwise a user-presentable error message.
    static func install() -> String? {
        guard let cli = bundledCLI else {
            return String(
                localized: "The command line tool is only bundled in release builds of QNapi.")
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: linkPath) {
                try fileManager.removeItem(atPath: linkPath)
            }
            try fileManager.createDirectory(
                atPath: "/usr/local/bin", withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(
                atPath: linkPath, withDestinationPath: cli.path)
            return nil
        } catch {
            return installWithPrivileges(cli: cli)
        }
    }

    private static func installWithPrivileges(cli: URL) -> String? {
        let script = """
            do shell script "mkdir -p /usr/local/bin && ln -sf \
            '\(cli.path)' '\(linkPath)'" with administrator privileges
            """
        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            return String(localized: "Installation was cancelled or failed.")
        }
        return nil
    }
}
