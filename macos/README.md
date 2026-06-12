# QNapi for macOS

Native macOS rewrite of QNapi in Swift 6 + SwiftUI. Menu bar app + CLI that
download movie subtitles from NapiProjekt, OpenSubtitles (REST API) and
Napisy24.

Requires macOS 15+, Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

## Layout

```
macos/
├── project.yml          # xcodegen manifest — QNapi.xcodeproj is generated
├── QNapi/               # app shell: @main, AppDelegate, Info.plist
├── QNapiKit/            # all logic, one SPM package with 9 targets
│   └── Sources/
│       ├── QNapiCore/       # domain models, file hashes, languages, encodings
│       ├── SubtitleFormats/ # SRT/MicroDVD/MPL2/TMPlayer codecs + conversion
│       ├── MediaInfo/       # frame-rate detection (AVFoundation)
│       ├── SevenZip/        # 7z extraction (PLzmaSDK, AES support)
│       ├── Engines/         # service clients behind SubtitleEngine protocol
│       ├── DownloadPipeline/# orchestration: hash→search→select→download→match
│       ├── QNapiSettings/   # UserDefaults config + Keychain credentials
│       ├── QNapiUI/         # SwiftUI scenes and observable session models
│       └── qnapi-cli/       # command-line interface
├── Vendor/PLzmaSDK/     # vendored (SwiftPM forbids unsafe flags in remote deps)
└── scripts/             # release build + notarization
```

## Build & test

```sh
cd QNapiKit
swift build          # everything except the .app
swift test           # 70+ tests, no network needed

cd ..
xcodegen generate    # creates QNapi.xcodeproj (gitignored)
xcodebuild -project QNapi.xcodeproj -scheme QNapi build
```

CLI during development: `cd QNapiKit && swift run qnapi-cli -l pl Movie.mkv`

## Release

```sh
CODE_SIGN_IDENTITY="Developer ID Application: ..." scripts/build-release.sh
scripts/notarize.sh build/QNapi.app
```

The CLI ships inside the bundle at `QNapi.app/Contents/Helpers/qnapi-cli`;
symlink it into your `PATH`.

## OpenSubtitles API key

The OpenSubtitles engine uses the REST API (api.opensubtitles.com) and needs
an API key — the legacy XML-RPC endpoint is deprecated. Create a free
consumer key at opensubtitles.com (Profile → API consumers) and paste it in
Settings → Engines, or pass `--os-api-key` to the CLI. Without a key the
engine is skipped; NapiProjekt and Napisy24 work without configuration.

## Notes

- App Sandbox is intentionally off: the app's core job is writing subtitle
  files next to arbitrary movies and scanning directories. Distribution is
  Developer ID + notarization (hardened runtime enabled).
- All filesystem mutations go through `SubtitleMatcher` — the single seam to
  adapt if sandboxing is ever needed.
- Plain-HTTP exceptions for napiprojekt.pl and napisy24.pl live in the app's
  Info.plist (`NSAppTransportSecurity`); both services are HTTP-only.
