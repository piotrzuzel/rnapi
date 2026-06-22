import DownloadPipeline
import RQNapiCore
import RQNapiSettings
import SwiftUI

public struct RQNapiSettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            EnginesSettingsTab()
                .tabItem { Label("Engines", systemImage: "network") }
            PostProcessingSettingsTab()
                .tabItem { Label("Processing", systemImage: "wand.and.stars") }
        }
        .frame(width: 540)
        .padding(.bottom, 8)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let configuration = settings.configuration

        Form {
            Picker(
                "Subtitle language:",
                selection: binding(\.languageCode)
            ) {
                ForEach(SubtitleLanguage.all, id: \.twoLetter) { language in
                    Text(language.englishName).tag(language.twoLetter)
                }
            }

            Picker(
                "Backup language:",
                selection: Binding(
                    get: { configuration.backupLanguageCode ?? "" },
                    set: { newValue in
                        settings.update { $0.backupLanguageCode = newValue.isEmpty ? nil : newValue }
                    })
            ) {
                Text("None").tag("")
                ForEach(SubtitleLanguage.all, id: \.twoLetter) { language in
                    Text(language.englishName).tag(language.twoLetter)
                }
            }

            Divider()

            Picker("Search mode:", selection: binding(\.searchPolicy)) {
                Text("Stop at first engine with results").tag(SearchPolicy.breakIfFound)
                Text("Search all engines").tag(SearchPolicy.searchAll)
                Text("Search all engines, both languages").tag(SearchPolicy.searchAllWithBackupLanguage)
            }
            .pickerStyle(.radioGroup)

            Picker("Subtitle list:", selection: binding(\.downloadPolicy)) {
                Text("Always show").tag(DownloadPolicy.alwaysShowList)
                Text("Show when match is uncertain").tag(DownloadPolicy.showListIfNeeded)
                Text("Never show (pick best)").tag(DownloadPolicy.neverShowList)
            }
            .pickerStyle(.radioGroup)

            Divider()

            Toggle(
                "Change subtitle file permissions to:",
                isOn: Binding(
                    get: { configuration.changePermissionsTo != nil },
                    set: { enabled in
                        settings.update { $0.changePermissionsTo = enabled ? "644" : nil }
                    }))
            if configuration.changePermissionsTo != nil {
                TextField(
                    "Permissions (octal):",
                    text: Binding(
                        get: { configuration.changePermissionsTo ?? "644" },
                        set: { newValue in
                            let octal = newValue.filter("01234567".contains).prefix(3)
                            settings.update { $0.changePermissionsTo = String(octal) }
                        }))
                .frame(width: 220)
            }

            Divider()

            CommandLineToolRow()
        }
        .padding(20)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { settings.configuration[keyPath: keyPath] },
            set: { newValue in settings.update { $0[keyPath: keyPath] = newValue } })
    }

    private func binding(
        _ keyPath: WritableKeyPath<AppConfiguration, Bool>, inverted: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { inverted != settings.configuration[keyPath: keyPath] },
            set: { newValue in settings.update { $0[keyPath: keyPath] = inverted != newValue } })
    }
}

/// "Install command line tool" row: symlinks the bundled rqnapi-cli into
/// /usr/local/bin.
private struct CommandLineToolRow: View {
    @State private var status = CommandLineToolInstaller.status()
    @State private var errorMessage: String?

    var body: some View {
        LabeledContent("Command line tool:") {
            VStack(alignment: .leading, spacing: 4) {
                switch status {
                case .installed:
                    Label("Installed at \(CommandLineToolInstaller.linkPath)",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case .notInstalled:
                    Button("Install Command Line Tool…") {
                        errorMessage = CommandLineToolInstaller.install()
                        status = CommandLineToolInstaller.status()
                    }
                case .bundledCLIMissing:
                    Text("Available in release builds of RQNapi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Engines

private struct EnginesSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @State private var editingEngine: String?

    var body: some View {
        let configuration = settings.configuration

        Form {
            Section {
                List {
                    ForEach(configuration.engineOrder, id: \.self) { engineID in
                        HStack {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { configuration.enabledEngines.contains(engineID) },
                                    set: { enabled in
                                        settings.update {
                                            if enabled {
                                                $0.enabledEngines.insert(engineID)
                                            } else {
                                                $0.enabledEngines.remove(engineID)
                                            }
                                        }
                                    }))
                            .labelsHidden()
                            Text(engineID)
                            Spacer()
                            Button("Account…") { editingEngine = engineID }
                                .buttonStyle(.link)
                        }
                    }
                    .onMove { source, destination in
                        settings.update { $0.engineOrder.move(fromOffsets: source, toOffset: destination) }
                    }
                }
                .frame(minHeight: 120)
            } header: {
                Text("Engines are searched in this order (drag to reorder):")
            }

            Section {
                TextField(
                    "OpenSubtitles API key:",
                    text: Binding(
                        get: { configuration.openSubtitlesApiKey ?? "" },
                        set: { newValue in
                            settings.update {
                                $0.openSubtitlesApiKey = newValue.isEmpty ? nil : newValue
                            }
                        }))
                Text("Required for OpenSubtitles. Create one for free at opensubtitles.com → API consumers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(item: $editingEngine) { engineID in
            EngineCredentialsSheet(engineID: engineID)
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

private struct EngineCredentialsSheet: View {
    let engineID: String

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(engineID) account")
                .font(.headline)
            Form {
                TextField("Username:", text: $username)
                SecureField("Password:", text: $password)
            }
            Text("Stored in your Keychain. Leave empty to use the service anonymously.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let credentials = username.isEmpty
                        ? nil : EngineCredentials(username: username, password: password)
                    settings.credentialStore.setCredentials(credentials, forEngine: engineID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if let existing = settings.credentialStore.credentials(forEngine: engineID) {
                username = existing.username
                password = existing.password
            }
        }
    }
}

// MARK: - Post-processing

private struct PostProcessingSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let postProcessing = settings.configuration.postProcessing

        Form {
            Toggle("Enable post-processing", isOn: binding(\.enabled))

            Group {
                Picker("Character encoding:", selection: binding(\.encodingChangeMethod)) {
                    Text("Keep original").tag(EncodingChangeMethod.original)
                    Text("Convert").tag(EncodingChangeMethod.change)
                    Text("Remove diacritics (ASCII)").tag(EncodingChangeMethod.replaceDiacritics)
                }

                if postProcessing.encodingChangeMethod == .change {
                    Picker("Convert to:", selection: binding(\.encodingTo)) {
                        ForEach(TextEncodingName.supported, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Picker(
                    "Convert format:",
                    selection: Binding(
                        get: { postProcessing.targetFormatName ?? "" },
                        set: { newValue in
                            settings.update {
                                $0.postProcessing.targetFormatName = newValue.isEmpty ? nil : newValue
                            }
                        })
                ) {
                    Text("Keep original").tag("")
                    Text("SubRip (.srt)").tag("subrip")
                    Text("MicroDVD (.sub)").tag("microdvd")
                    Text("MPL2 (.txt)").tag("mpl2")
                    Text("TMPlayer (.txt)").tag("tmplayer")
                }

                TextField(
                    "Remove lines containing:",
                    text: Binding(
                        get: { postProcessing.removeLinesWords.joined(separator: ", ") },
                        set: { newValue in
                            settings.update {
                                $0.postProcessing.removeLinesWords = newValue
                                    .components(separatedBy: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        }),
                    prompt: Text("comma-separated words"))
            }
            .disabled(!postProcessing.enabled)
        }
        .padding(20)
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<PostProcessingSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings.configuration.postProcessing[keyPath: keyPath] },
            set: { newValue in settings.update { $0.postProcessing[keyPath: keyPath] = newValue } })
    }
}
