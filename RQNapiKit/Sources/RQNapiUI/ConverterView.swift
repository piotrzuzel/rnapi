import MediaInfo
import RQNapiCore
import SubtitleFormats
import SwiftUI
import UniformTypeIdentifiers

/// Standalone subtitle format converter (legacy frmConvert).
public struct ConverterView: View {
    @State private var sourceFile: URL?
    @State private var detectedFormat: String?
    @State private var targetFormat = "subrip"
    @State private var movieFile: URL?
    @State private var manualFPS = 23.976
    @State private var useMovieFPS = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    public init() {}

    public var body: some View {
        Form {
            Section("Source") {
                HStack {
                    Text(sourceFile?.lastPathComponent ?? String(localized: "No file selected"))
                        .foregroundStyle(sourceFile == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseSource() }
                }
                if let detectedFormat {
                    LabeledContent("Detected format:", value: detectedFormat)
                }
            }

            Section("Target") {
                Picker("Convert to:", selection: $targetFormat) {
                    Text("SubRip (.srt)").tag("subrip")
                    Text("MicroDVD (.sub)").tag("microdvd")
                    Text("MPL2 (.txt)").tag("mpl2")
                    Text("TMPlayer (.txt)").tag("tmplayer")
                }
            }

            Section("Frame rate (for frame-based formats)") {
                Toggle("Read frame rate from movie file", isOn: $useMovieFPS)
                if useMovieFPS {
                    HStack {
                        Text(movieFile?.lastPathComponent ?? String(localized: "No movie selected"))
                            .foregroundStyle(movieFile == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseMovie() }
                    }
                } else {
                    Picker("Frame rate:", selection: $manualFPS) {
                        Text("23.976").tag(23.976)
                        Text("24").tag(24.0)
                        Text("25").tag(25.0)
                        Text("29.97").tag(29.97)
                        Text("30").tag(30.0)
                    }
                }
            }

            HStack {
                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: statusIsError
                            ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(statusIsError ? .red : .green)
                }
                Spacer()
                Button("Convert") {
                    Task { await convert() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sourceFile == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 380)
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "srt") ?? .plainText,
                                     UTType(filenameExtension: "sub") ?? .plainText]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            sourceFile = url
            statusMessage = nil
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: TextEncodingDetector.detectEncoding(of: data))
            {
                let lines = text.components(separatedBy: .newlines)
                detectedFormat = SubtitleFormatsRegistry.detectFormat(lines: lines)?.name
                    ?? String(localized: "unknown")
            }
        }
    }

    private func chooseMovie() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        if panel.runModal() == .OK {
            movieFile = panel.url
        }
    }

    private func convert() async {
        guard let sourceFile else { return }

        var frameRate: Double? = manualFPS
        if useMovieFPS {
            guard let movieFile else {
                report(error: String(localized: "Choose a movie file first."))
                return
            }
            frameRate = await AVFoundationMovieInfoProvider().movieInfo(for: movieFile)?.frameRate
        }

        do {
            guard let data = try? Data(contentsOf: sourceFile) else {
                report(error: String(localized: "Could not read the subtitle file."))
                return
            }
            let encoding = TextEncodingDetector.detectEncoding(of: data)
            guard let text = String(data: data, encoding: encoding) else {
                report(error: String(localized: "Could not decode the subtitle file."))
                return
            }

            let rate = frameRate
            let converted = try SubtitleConverter().convert(
                lines: text.components(separatedBy: .newlines),
                to: targetFormat,
                frameRate: { rate })

            let targetExtension = SubtitleFormatsRegistry.format(named: targetFormat)?
                .defaultExtension ?? "srt"
            let target = sourceFile.deletingPathExtension().appendingPathExtension(targetExtension)
            let output = converted.joined(separator: "\n") + "\n"
            try output.data(using: encoding, allowLossyConversion: true)?.write(to: target)

            statusIsError = false
            statusMessage = String(localized: "Saved \(target.lastPathComponent)")
        } catch SubtitleConversionError.frameRateUnavailable {
            report(error: String(localized: "Frame rate needed for this conversion."))
        } catch {
            report(error: String(localized: "Conversion failed."))
        }
    }

    private func report(error: String) {
        statusIsError = true
        statusMessage = error
    }
}
