<p align="center">
  <img src="docs/images/icon.png" width="128" alt="HangDry icon">
</p>

<h1 align="center">HangDry</h1>

<p align="center">
  A clothesline for your files, hanging at the top of your Mac's screen.<br>
  Pin scattered files while you work, drag them anywhere, then <b>bring them all in</b> to one tidy folder when the project is done.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="#install">Install</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="LICENSE">MIT License</a>
</p>

![The clothesline with files hanging on it](docs/images/rope.png)

## Why

I make AI music videos, and every project ends with files scattered everywhere: generated clips in one folder, renders in another, voice takes on the desktop, cover references in Downloads, lyrics and subtitles somewhere else. Finding them while working is a chore, and tidying up afterwards is worse.

HangDry was inspired by [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján, which hangs every screenshot on a line at the top of the screen. I loved the idea and wanted the same line for every kind of file, plus a way to file it all away when the project is done. HangDry gives your files one place to live while you work, and one click to put them away.

- **Hang** files by dragging them to the top of the screen, or just copy them (⌘C, “Copy Image” in a browser, screenshots) and they hang themselves.
- **Use** them from the line: drag a card into Finder, a browser upload box, Premiere, DaVinci, or any app.
- **Bring in** when the project is done: every file on the line is moved into a folder of your choice, sorted into `Videos/ Audio/ Images/ Documents/ Projects/ …`, with a JSON log of where each file came from.

Hanging a file only stores a link. Originals stay where they are until you bring them in.

## Features

| | |
|---|---|
| **Drag to hang** | Drag files or images toward the top of the screen. A shelf slides out; a dashed slot opens where the card will land and the rope dips under it. |
| **Copy to hang** | Anything you copy as a file or image, in any app, is hung automatically. Text is ignored, and so are password-manager clipboard entries. |
| **Watch folders** | Point HangDry at a download or render-output folder; new files are hung once they finish writing. |
| **Rearrange** | Drag cards along the line to reorder them, or sort by type, date created, date modified or name. |
| **Rename** | Give a card a display name without touching the file. Optionally use those names when bringing files in. |
| **Take off / delete** | Remove just the link, move the real file to the Trash, or take everything down at once, with 5 seconds to undo. |
| **Bring in** | Move everything into one folder, sorted by type. Name clashes get a number suffix; a log records each original path. |
| **Global shortcuts** | ⌃⌥H keep open · ⌃⌥K bring in · ⌃⌥⌫ take all down · ⌃⌥1–4 sort |
| **Physics** | The rope sags with weight, ripples when something lands, and cards swing on their pins. Animation stops completely when nothing moves (≈0.3% CPU at rest). |
| **Languages** | English, 简体中文, 繁體中文, 日本語 |

<p align="center">
  <img src="docs/images/rope-drop.png" alt="Dragging two files onto the line opens a slot between cards">
</p>

## Install

Requires macOS 14 Sonoma or later.

Download the latest `HangDry-x.y.z.dmg` from [Releases](https://github.com/ansonsiva/HangDry/releases/latest), open it, and drag HangDry into Applications. The app is signed with a Developer ID and notarized by Apple, so it opens normally.

HangDry lives in the menu bar (👕); there's no Dock icon. Turn on **Open at Login** in its menu to keep it running.

You can also [build it from source](#build-from-source).

The first time something is copied as a file or image, macOS asks whether HangDry may read the clipboard. Set it to **Always Allow** in *System Settings → Privacy & Security → Paste* to stop the prompts.

## Usage

| Action | Result |
|---|---|
| Drag files toward the top of the screen | A “Drag here to hang” tab drops down; inside the top ~44 pt the shelf opens. Release anywhere on it. |
| Hold ⌥ while dropping | Hang a copy (stored inside the app) instead of a link |
| Copy a file or image anywhere | Hung automatically (toggle in the menu) |
| Hover the thin line under the menu bar | The line opens; it closes again when the pointer leaves |
| Drag a card along the line | Move it; select several with ⌘/⇧ to move them together |
| Drag a card off the line | Copy the file to wherever you drop it (hold ⌘ to move) |
| Double-click a card | Open the file |
| Right-click a card | Open, Show in Finder, Rename, Take Off the Line, Delete File, Sort, Bring In |
| **Take All Down** (left end of the line) | Remove every link; originals untouched; undo within 5 s |
| **Bring In** (right end of the line) | Choose a folder; files are moved into typed subfolders |

The coloured hem on each card shows the file type: purple video, orange audio, green image, blue document, pink project file. Cards follow files that are renamed or moved; missing files turn grey.

## Build from source

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ansonsiva/HangDry.git
cd HangDry
xcodegen generate          # regenerates HangDry.xcodeproj from project.yml
open HangDry.xcodeproj     # then Run (⌘R)
```

Command line:

```bash
xcodebuild -project HangDry.xcodeproj -scheme HangDry -configuration Release -derivedDataPath build/DerivedData build
cp -R build/DerivedData/Build/Products/Release/HangDry.app /Applications/
```

The project signs to run locally by default. To ship your own build, set your bundle ID and `DEVELOPMENT_TEAM` in `project.yml` and remove `CODE_SIGN_IDENTITY: "-"`.

### Tests

```bash
xcodebuild -project HangDry.xcodeproj -scheme HangDry -derivedDataPath build/DerivedData test
```

About 60 tests cover classification, bringing in, storage, layout, sorting, drag payloads, clipboard detection, file promises and the physics. The test target compiles the app sources directly (no host app), so it runs outside the sandbox.

Render the UI to PNGs without launching the app:

```bash
TEST_RUNNER_HANGDRY_SNAPSHOT_IN=path/to/sample/files TEST_RUNNER_HANGDRY_SNAPSHOT_OUT=build/Snapshots \
  xcodebuild -project HangDry.xcodeproj -scheme HangDry -derivedDataPath build/DerivedData test
```

### Project layout

```
HangDry/
  App/        HangDryApp (menu bar entry), AppModel (state and every user action)
  Model/      HungItem, FileKind (type detection), RopeStore (bookmarks, sandbox access, persistence, sorting)
  Services/   Collector (bring in), FolderWatcher, ClipboardWatcher, DropLoader / ImageClip (dragged and copied content),
              HotKeyCenter (global shortcuts), ThumbnailCache (Quick Look)
  Window/     RopePanel (transparent floating panel), RopePanelController (open/close, shelf, pointer polling),
              RopeContainerView (shelf background, AppKit drop target)
  Views/      RopeView (scene), RopeSimulation (springs, pendulums, ripples), RopeDrawing (rope and clothespins),
              ClothesView, ClothesInteraction (drag source, context menu), MenuBarContent
  Resources/  Localizable.xcstrings, PrivacyInfo.xcprivacy, app icon
HangDryTests/ unit tests and snapshot rendering
Scripts/      make_icon.swift (draws the app icon)
```

### Things learned the hard way

These are written up in comments where they matter, but worth knowing before you change anything:

- **WindowServer load.** Anything redrawn every frame (swinging cards, the dashed drop slot, the hint tab) is rasterised in-process with `drawingGroup()`. Without it, WindowServer re-rasterises shapes, text and shadows every frame and the whole Mac stutters during a drag. A full-width live blur behind the shelf had the same effect, so the shelf uses a plain translucent fill.
- **Drop targets and transparency.** macOS routes a drag by pixel alpha. A mostly transparent window lets drags flicker between it and the app underneath, so the shelf is opaque while a drag is over it.
- **Swift 6 isolation.** A closure written inside `@MainActor` code and handed to an AppKit API that calls back on a background queue crashes in `_dispatch_assert_queue_fail`. Build such callbacks in a `nonisolated` function and mark them `@Sendable` (see `DropLoader.makeReader`).
- **File promises** (images dragged from browsers, Photos, chat apps) can only be received synchronously inside `performDragOperation`.
- **Clipboard privacy** (macOS 15.4+): reading `changeCount` and `types` is silent; reading contents prompts the user. HangDry only reads contents when the types contain a file or an image.

Release: `Scripts/make_release.sh` builds a Developer ID–signed, notarized DMG (needs your certificate and an App Store Connect API key; see the header of the script).

Debug-only launch arguments for checking performance: `-demoAnimation` (open/close every few seconds) and `-demoShelf` (simulates a file held over the line).

## Sandboxing and privacy

HangDry runs in the App Sandbox. Every file it touches comes from something you did: a drag, a copy, or a folder you picked. Access is kept with security-scoped bookmarks. It collects no data and makes no network requests. Entitlements: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`.

## Roadmap

- Several lines, one per project
- Stack cards into piles when the line gets crowded
- Restore files from a bring-in log
- Quick Look preview with Space, multiple displays
- Custom archive templates and naming rules
- Customisable shortcuts

## Contributing

Issues and pull requests are welcome. Please run the tests before opening a PR. New UI text goes through `String(localized:)` (or a SwiftUI literal) so it lands in `Localizable.xcstrings`.

## Acknowledgements

- [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján, the screenshot clothesline that inspired HangDry. HangDry is an independent implementation and shares no code with it.

## License

[MIT](LICENSE) © 2026 junzheng
