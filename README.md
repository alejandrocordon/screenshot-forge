# screenshot-forge
Batch-resize screenshots for Google Play &amp; App Store. CLI + GUI. No cloud, no subscriptions — just correctly sized screenshot

Resize and crop screenshots for Google Play and Apple App Store — CLI + GUI.

> No cloud. No subscriptions. Just correctly sized screenshots, every time.

---

## Features

- **Batch processing** — drop a folder of screenshots, get store-ready outputs
- **Smart resize + crop** — preserves aspect ratio, center-crops to exact target dimensions
- **All store sizes built-in** — iPhone 6.7", 6.5", 5.5", iPad 12.9", Android phone/tablet/Chromebook
- **Organized output** — `output/ios/6.5inch/`, `output/android/phone/`, etc.
- **CLI + GUI** — scriptable from CI/CD or point-and-click for quick jobs
- **Portrait & Landscape** — both orientations per device spec

## Supported Target Sizes

### Apple App Store

| Device           | Portrait        | Landscape       |
|------------------|-----------------|-----------------|
| iPhone 6.7"      | 1290 × 2796     | 2796 × 1290     |
| iPhone 6.5"      | 1242 × 2688     | 2688 × 1242     |
|                  | 1284 × 2778     | 2778 × 1284     |
| iPhone 5.5"      | 1242 × 2208     | 2208 × 1242     |
| iPad 12.9" (6th) | 2048 × 2732     | 2732 × 2048     |
| iPad 12.9" (2nd) | 2048 × 2732     | 2732 × 2048     |

### Google Play Store

| Device     | Size            |
|------------|-----------------|
| Phone      | 1080 × 1920     |
| 7" Tablet  | 1200 × 1920     |
| 10" Tablet | 1600 × 2560     |
| Chromebook | 1920 × 1080     |

## Installation

```bash
# Clone
git clone https://github.com/AlejandroCordon/screenshot-forge.git
cd screenshot-forge

# Install dependencies
pip install -r requirements.txt
```

### Requirements

- Python 3.10+
- Pillow

## Usage

### CLI

```bash
# Resize for all platforms
python forge.py --input ./screenshots --output ./output

# iOS only
python forge.py --input ./screenshots --output ./output --platform ios

# Android only, specific device
python forge.py --input ./screenshots --output ./output --platform android --device phone

# Single file
python forge.py --input ./screenshots/home.png --output ./output --platform ios --device 6.5
```

### GUI

```bash
python forge_gui.py
```

1. Select input folder (or drag & drop)
2. Pick target platforms/devices
3. Click **Forge** 🔨
4. Output lands in the selected directory, organized by platform and device

## Output Structure

```
output/
├── ios/
│   ├── 6.7inch/
│   │   ├── home_1290x2796.png
│   │   └── home_2796x1290.png
│   ├── 6.5inch/
│   │   ├── home_1242x2688.png
│   │   ├── home_2688x1242.png
│   │   ├── home_1284x2778.png
│   │   └── home_2778x1284.png
│   ├── 5.5inch/
│   └── ipad_12.9inch/
└── android/
    ├── phone/
    ├── 7inch_tablet/
    ├── 10inch_tablet/
    └── chromebook/
```

## Resize Strategy

1. **Scale** the source image so it fully covers the target dimensions (no empty space)
2. **Center-crop** to the exact target size

No letterboxing. No stretching. No black bars.

## Roadmap

- [x] Batch resize + center-crop
- [x] CLI interface
- [x] GUI (Tkinter)
- [ ] Device frame overlays (iPhone/Pixel mockups)
- [ ] Text overlays (title + subtitle per screenshot)
- [ ] Fastlane integration
- [ ] CI/CD GitHub Action

## Tech Stack

| Component | Tech     |
|-----------|----------|
| Language  | Python   |
| Imaging   | Pillow   |
| GUI       | Tkinter  |
| CLI       | argparse |

## License

MIT

---

Built by [Alejandro Cordón](https://alejandrocordon.com) · [@cordon.alejandro](https://medium.com/@cordon.alejandro)
