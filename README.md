# RNapi

RNapi — native macOS rewrite of [QNapi](https://github.com/QNapi/qnapi) in
Swift 6 + SwiftUI. A menu bar app and CLI that download movie subtitles from
NapiProjekt, OpenSubtitles and Napisy24.

Requires macOS 15+, Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

The app lives under [`macos/`](macos/); all commands below are run from the
repo root.

## Layout

```
macos/
├── project.yml          # xcodegen manifest — RNapi.xcodeproj is generated
├── RNapi/               # app shell: @main, AppDelegate, Info.plist
├── RNapiKit/            # all logic, one SPM package with 9 targets
│   └── Sources/
│       ├── RNapiCore/       # domain models, file hashes, languages, encodings
│       ├── SubtitleFormats/ # SRT/MicroDVD/MPL2/TMPlayer codecs + conversion
│       ├── MediaInfo/       # frame-rate detection (AVFoundation)
│       ├── SevenZip/        # 7z extraction (PLzmaSDK, AES support)
│       ├── Engines/         # service clients behind SubtitleEngine protocol
│       ├── DownloadPipeline/# orchestration: hash→search→select→download→match
│       ├── RNapiSettings/   # UserDefaults config + Keychain credentials
│       ├── RNapiUI/         # SwiftUI scenes and observable session models
│       └── rnapi-cli/       # command-line interface
├── Vendor/PLzmaSDK/     # vendored (SwiftPM forbids unsafe flags in remote deps)
└── scripts/             # release build + notarization
```

## Build & test

```sh
cd macos/RNapiKit
swift build          # everything except the .app
swift test           # 70+ tests, no network needed

cd ..
xcodegen generate    # creates RNapi.xcodeproj (gitignored)
xcodebuild -project RNapi.xcodeproj -scheme RNapi build
```

CLI during development:

```sh
cd macos/RNapiKit && swift run rnapi-cli -l pl Movie.mkv
```

## Release

```sh
cd macos
CODE_SIGN_IDENTITY="Developer ID Application: ..." scripts/build-release.sh
scripts/notarize.sh build/RNapi.app
```

The CLI ships inside the bundle at `RNapi.app/Contents/Helpers/rnapi-cli`;
symlink it into your `PATH`.

## Subtitle engines

By default every enabled engine is consulted (search policy "search all
engines"); this is configurable in Settings.

- **NapiProjekt** — hash-addressed lookup via the `api3` endpoint, which
  returns the subtitle text directly. No credentials required.
- **OpenSubtitles** — works out of the box. With an API key it uses the REST
  API (`api.opensubtitles.com`); without one it falls back to the anonymous
  legacy XML-RPC API (`api.opensubtitles.org/xml-rpc`). A key is optional and
  mainly raises download quotas — create a free consumer key at
  opensubtitles.com (Profile → API consumers) and paste it in
  Settings → Engines, or pass `--os-api-key` to the CLI.
- **Napisy24** — Polish subtitles only.

## Notes

- App Sandbox is intentionally off: the app's core job is writing subtitle
  files next to arbitrary movies and scanning directories. Distribution is
  Developer ID + notarization (hardened runtime enabled).
- All filesystem mutations go through `SubtitleMatcher` — the single seam to
  adapt if sandboxing is ever needed.
- Plain-HTTP exceptions for napiprojekt.pl and napisy24.pl live in the app's
  Info.plist (`NSAppTransportSecurity`); both services are HTTP-only.

## Legacy

The original QNapi C++/Qt sources (`cli/`, `gui/`, `libqnapi/`, and related
top-level directories) remain in the repository for reference only. They are
not part of the RNapi build.
