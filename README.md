<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://gist.githubusercontent.com/piotrzuzel/2b0dee4363caf66bcb54f59871c26b6a/raw/b3b1055d8f747105edd25a28c1bc58a663323854/rqnapi-dark.svg">
    <img src="https://gist.githubusercontent.com/piotrzuzel/ad187a7c7c8358861a4494857addff45/raw/d9352a3259a258de35ef1c65ef35db72738613e1/rqnapi.svg" alt="RQNapi" height="80">
  </picture>
</p>

RQNapi is an automatic movie-subtitle downloader for macOS — a native Swift 6 +
SwiftUI rewrite of [QNapi](https://github.com/QNapi/qnapi).

It identifies each video by a content **hash** (not its filename), looks that
hash up across NapiProjekt, OpenSubtitles and Napisy24, and drops the
best-matching subtitle right next to the movie. It runs as a Mac app and
ships a `rqnapi-cli` for the terminal — point it at a single file or a whole
folder and it works through them in the background. No account or API key
required.

## Features

- **Hash-based matching** — finds subtitles for the exact release, regardless of
  how the file is named.
- **Three sources** — NapiProjekt, OpenSubtitles and Napisy24, searched in a
  configurable order with a primary and a backup language.
- **Menu bar app + CLI** — drag-and-drop in the app, or `rqnapi-cli` for
  scripting and batch jobs.
- **Folder scanning** — recursively finds videos and can skip ones that already
  have subtitles.
- **Post-processing** — optional conversion between SubRip / MicroDVD / MPL2 /
  TMPlayer and subtitle text-encoding normalization.
- **Native & self-contained** — Swift 6 / SwiftUI, works out of the box with no
  required API keys.

Requires macOS 15+. Building requires Xcode 26+.

## Layout

```
.
├── RQNapi.xcodeproj/     # Xcode project (tracked)
├── RQNapi/               # app shell: @main, AppDelegate, Info.plist
├── RQNapiKit/            # all logic, one SPM package with 9 targets
│   └── Sources/
│       ├── RQNapiCore/       # domain models, file hashes, languages, encodings
│       ├── SubtitleFormats/ # SRT/MicroDVD/MPL2/TMPlayer codecs + conversion
│       ├── MediaInfo/       # frame-rate detection (AVFoundation)
│       ├── SevenZip/        # 7z extraction (PLzmaSDK, AES support)
│       ├── Engines/         # service clients behind SubtitleEngine protocol
│       ├── DownloadPipeline/# orchestration: hash→search→select→download→match
│       ├── RQNapiSettings/   # UserDefaults config + Keychain credentials
│       ├── RQNapiUI/         # SwiftUI scenes and observable session models
│       └── rqnapi-cli/       # command-line interface
├── Vendor/PLzmaSDK/     # vendored (SwiftPM forbids unsafe flags in remote deps)
└── scripts/             # release build + notarization
```

## Build & test

```sh
cd RQNapiKit
swift build          # everything except the .app
swift test           # 70+ tests, no network needed

cd ..                # repo root
xcodebuild -project RQNapi.xcodeproj -scheme RQNapi build
```

CLI during development:

```sh
cd RQNapiKit && swift run rqnapi-cli -l pl Movie.mkv
```

## Release

```sh
# from the repo root
CODE_SIGN_IDENTITY="Developer ID Application: ..." scripts/build-release.sh
scripts/notarize.sh build/RQNapi.app
```

The CLI ships inside the bundle at `RQNapi.app/Contents/Helpers/rqnapi-cli`;
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

## Origin & license

RQNapi is a ground-up Swift 6 + SwiftUI rewrite of
[QNapi](https://github.com/QNapi/qnapi) — the long-running C++/Qt subtitle
downloader for Windows, macOS and Linux. It reuses QNapi's service behavior and
file-hashing logic (including NapiProjekt's `npFDigest` and the OpenSubtitles
hash). Thanks to the QNapi authors and contributors for the original project.

Licensed under **GPL-2.0**, inherited from QNapi.
