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
      CropGeometry.swift     # pure crop math + keptRegion for previews (tested)
      AppleSizes.swift       # Apple screenshot + app-preview-video sizes
      GooglePlaySizes.swift  # Google Play screenshot sizes
      SupportedTypes.swift
      ForgeError.swift
      ImageCropper.swift     # CoreGraphics
      VideoCropper.swift     # AVFoundation (30 fps cap)
      FrameStyle.swift       # device-bezel style (data)
      BezelRenderer.swift    # frames a screenshot in a rounded bezel
      AppStoreConnectAuth.swift    # ES256 JWT (tested)
      AppStoreConnectClient.swift  # API client (listApps works; upload stubbed)
      BatchEngine.swift      # orchestration + progress (actor)
    Tests/ForgeCoreTests/    # CropGeometry, AppleSizes, GooglePlay, ASC-auth
  App/                       # SwiftUI app (sidebar of apps → assets → export)
    ScreenshotForgeApp.swift # @main + SwiftData model container
    Models.swift             # SwiftData @Model: AppProject, Asset (persisted)
    BookmarkStore.swift      # security-scoped file bookmarks
    ContentView.swift
    AppDetailView.swift      # assets, live preview, device toggles, export
    CropPreview.swift        # "what gets kept" overlay
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
swift test          # CropGeometry, AppleSizes, GooglePlay, App Store Connect auth
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
Screenshots also export to **Google Play** sizes (`GooglePlaySizes`) under
`output/android/<device>/`; Google Play previews are a YouTube URL, not an
upload, so videos stay Apple-only.

## Features

- **Apple + Google Play** screenshots, **Apple** app preview videos (30 fps cap).
- **Live crop preview** (`CropPreview` + `CropGeometry.keptRegion`): see what will
  be kept per device before exporting.
- **Device bezel** (`BezelRenderer`): optionally frame screenshots in a rounded
  bezel at the exact target size — a scaffold that needs no mockup assets.
- **Persistence**: SwiftData library of apps + assets, stored via bookmarks.
- **App Store Connect** (`AppStoreConnect*`): ES256 JWT auth is complete and
  tested; `listApps()` checks credentials; screenshot upload is a documented stub.

## Caveats / next steps

- **AVFoundation transform:** the crop transform in `VideoCropper` handles the
  common upright case. Rotated footage (non-identity `preferredTransform`) should
  be verified on device — AVFoundation's composition coordinate space is the
  fiddly bit. Validate exported dimensions and framing with real clips.
- **Device frames are a bezel, not a mockup:** `BezelRenderer` draws a rounded
  bezel — no photorealistic iPhone/iPad shell. To use real frames, load a frame
  PNG with a transparent screen cutout and composite the cropped screenshot into
  its known screen rect.
- **App Store Connect upload is a stub:** the JWT auth is real and tested; the
  screenshot reservation/upload/commit flow is documented in
  `AppStoreConnectClient.uploadScreenshot` but not implemented — finish and test
  it with a real API key (issuer id, key id, `.p8`).
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
- **Roadmap:** ~~live crop preview~~ • ~~Android sizes~~ • ~~device-frame overlays~~ •
  ~~App Store Connect auth~~ • finish ASC upload • real device-frame mockups •
  title/subtitle captions • Fastlane `deliver` export.
