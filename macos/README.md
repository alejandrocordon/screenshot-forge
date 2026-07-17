# ScreenshotForge for macOS (MVP scaffold)

A native macOS app to manage **all your apps** and their App Store assets —
screenshots and app preview videos — in one place, and export every required
Apple size in a click. It reuses the exact *scale-to-cover + center-crop*
behaviour of the Python CLI and the `crop_apple_video.sh` script, but natively:
**CoreGraphics** for images and **AVFoundation** for video (no ffmpeg binary to
bundle or notarize).

> **Status:** this is a scaffold, not a finished app. It was written to build in
> Xcode on a Mac — it has **not** been compiled here (the build box is Linux with
> no Swift toolchain or Apple frameworks). The pure geometry is covered by unit
> tests you can run; the AVFoundation transform is the part to validate on device
> (see *Caveats*).

## Layout

```
macos/
  ForgeCore/                 # Swift Package — reusable, UI-free engine
    Sources/ForgeCore/
      PixelSize.swift
      CropGeometry.swift     # pure scale-to-cover + center-crop math (tested)
      AppleSizes.swift       # App Store size registry (ported from sizes.py)
      SupportedTypes.swift
      ForgeError.swift
      ImageCropper.swift     # CoreGraphics  (#if canImport(CoreGraphics))
      VideoCropper.swift     # AVFoundation  (#if canImport(AVFoundation))
      BatchEngine.swift      # orchestration + progress (actor)
    Tests/ForgeCoreTests/    # CropGeometry + AppleSizes tests
  App/                       # SwiftUI app (sidebar of apps → assets → export)
    ScreenshotForgeApp.swift # @main + SwiftData model container
    Models.swift             # SwiftData @Model: AppProject, Asset (persisted)
    BookmarkStore.swift      # security-scoped file bookmarks
    ContentView.swift
    AppDetailView.swift
  project.yml                # XcodeGen spec (optional, generates the .xcodeproj)
```

`ForgeCore` has **no dependency on the UI** — the same engine could back a CLI,
a menu-bar app, or a Fastlane plugin later.

## Build & run

**Option A — XcodeGen (reproducible):**

```bash
brew install xcodegen
cd macos
xcodegen generate
open ScreenshotForge.xcodeproj
```

**Option B — manual Xcode:**

1. Xcode → *New Project* → macOS *App* (SwiftUI), name `ScreenshotForge`.
2. Delete the auto-generated `ContentView.swift`/`App.swift`.
3. Drag the files in `App/` into the target.
4. *File → Add Package Dependencies… → Add Local…* and pick `macos/ForgeCore`.
5. Set your *Development Team* under *Signing & Capabilities* and run.

**Run the core tests:**

```bash
cd macos/ForgeCore
swift test          # runs CropGeometry + AppleSizes tests
```

## How it works

`CropGeometry.plan(source:target:)` is the shared heart — it returns the size to
scale the source to (fully covering the target) plus the centered crop origin,
identical to the Python `resize_and_crop`. `ImageCropper` and `VideoCropper`
just apply that plan with the right framework, and `BatchEngine` fans it out over
every input × every selected Apple size, writing to
`output/ios/<device>/<name>_<w>x<h>.{png,mp4}` — the same layout as the CLI.

Screenshots and app preview **videos use different Apple resolutions**, so
`AppleSizes` has two tables (`screenshots` and `videos`) and `BatchEngine` picks
the right one per asset — e.g. a 6.7" screenshot is `1290×2796` but its app
preview video is `886×1920`. Video resolutions per
[Apple's spec](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/).

## Caveats / next steps

- **AVFoundation transform:** the crop transform in `VideoCropper` handles the
  common upright case. Rotated footage (non-identity `preferredTransform`) should
  be verified on device — AVFoundation's composition coordinate space is the
  fiddly bit. Validate exported dimensions and framing with real clips.
- **Persistence (done):** apps and their assets are SwiftData `@Model`s
  (`AppProject`, `Asset`) persisted on disk via `.modelContainer`, so the library
  survives relaunch. Each `Asset` stores a **bookmark** (`BookmarkStore`) instead
  of a raw path, so access survives the file being moved. `BookmarkStore` prefers
  a security-scoped bookmark and falls back to a plain one, so it works whether or
  not the app is sandboxed.
- **Sandbox:** the MVP ships **without** App Sandbox (simplest for local use). To
  distribute it, enable App Sandbox + the *User Selected File* (read-write) and
  *Bookmarks (app-scope)* entitlements — `BookmarkStore` and the export path
  already start/stop the security scope, so no code change is needed. Validate on
  device: bookmark resolution is the part I couldn't compile here.
- **Asset PNGs & the repo `.gitignore`:** the repo root ignores `*.png`/`*.mov`/…
  so test media never gets committed. If you add an app-icon asset catalog, force
  it in (`git add -f`) or add a scoped un-ignore for `macos/**/Assets.xcassets`.
- **Roadmap:** live crop preview • Android sizes • device-frame overlays •
  title/subtitle captions • App Store Connect API upload • Fastlane `deliver` export.
