# screenshot-forge

Resize and crop screenshots **and app preview videos** for Google Play and Apple App Store. Accepts a single file or an entire folder and generates every required size in one pass.

CLI, GUI, and web interface. Works directly with Python or inside Docker.

## Features

- Batch processing: point to a folder, get all store sizes at once
- Scale-to-cover + center-crop (no black bars, no distortion)
- **App preview videos**: drop a video and it gets cropped to the Apple / iOS sizes the same way (needs ffmpeg)
- All official sizes built in: iPhone 6.7", 6.5", 5.5", iPad 12.9", Android phone, tablet, Chromebook
- Organized output by platform and device
- Portrait and landscape orientations
- CLI for scripting and CI/CD, GUI for desktop, web for the browser
- Web interface with drag-and-drop and ZIP download

## Supported sizes

### Apple App Store

| Device           | Portrait    | Landscape   |
|------------------|-------------|-------------|
| iPhone 6.7"      | 1290 x 2796 | 2796 x 1290 |
| iPhone 6.5"      | 1242 x 2688 | 2688 x 1242 |
|                  | 1284 x 2778 | 2778 x 1284 |
| iPhone 5.5"      | 1242 x 2208 | 2208 x 1242 |
| iPad 12.9"       | 2048 x 2732 | 2732 x 2048 |

> **Videos** (`.mp4`, `.mov`, `.m4v`) are cropped to these Apple / iOS sizes only — the App Store is where app preview videos live. Output is H.264 `.mp4`, one per size, alongside the images.

### Google Play Store

| Device     | Size         |
|------------|--------------|
| Phone      | 1080 x 1920  |
| 7" Tablet  | 1200 x 1920  |
| 10" Tablet | 1600 x 2560  |
| Chromebook | 1920 x 1080  |

## Installation

```bash
git clone https://github.com/AlejandroCordon/screenshot-forge.git
cd screenshot-forge
pip install -r requirements.txt
```

Requires Python 3.10+ and Pillow. Cropping **videos** also needs [ffmpeg](https://ffmpeg.org) on your `PATH` (`brew install ffmpeg`, `apt install ffmpeg`, …). Images work without it.

## Usage (CLI)

The `--input` flag accepts a single file or a folder. When you pass a folder, every `.png`/`.jpg` image and every `.mp4`/`.mov`/`.m4v` video inside it gets processed automatically. Images are cropped to every selected size; videos are cropped to the Apple / iOS sizes only.

```bash
# Folder with all your screenshots, all platforms
python forge.py --input ./screenshots --output ./output

# iOS only
python forge.py -i ./screenshots -o ./output -p ios

# Android, phone sizes only
python forge.py -i ./screenshots -o ./output -p android -d phone

# Single file
python forge.py -i ./screenshots/home.png -o ./output

# A single app preview video → cropped to every Apple size
python forge.py -i ./previews/demo.mp4 -o ./output -p ios
```

### CLI arguments

| Flag               | Required | Default    | Description                     |
|--------------------|----------|------------|---------------------------------|
| `-i` / `--input`   | yes      |            | Image/video file or folder      |
| `-o` / `--output`  | no       | `./output` | Output folder                   |
| `-p` / `--platform` | no      | `all`      | `ios`, `android`, or `all`      |
| `-d` / `--device`  | no       | all        | Specific device (e.g. `phone`)  |
| `-q` / `--quality` | no       | `6`        | PNG compression level (0-9)     |

## Usage (GUI)

```bash
python forge_gui.py
```

1. Select the input folder with your screenshots
2. Pick which platforms and devices you want
3. Click Forge
4. Open the output folder when it finishes

## Usage (Web)

```bash
python forge_web.py
```

Open http://localhost:8642 in your browser.

1. Drag and drop your screenshots onto the page (or click to browse)
2. Check the platforms and devices you want
3. Click Forge
4. A ZIP file downloads automatically with the results

Also works with Docker Compose:

```bash
docker compose up web
```

Then open http://localhost:8642.

## Usage (Docker)

Build the image once:

```bash
docker build -t screenshot-forge .
```

Run it by mounting your input and output folders:

```bash
# All platforms, all devices
docker run --rm \
  -v ./screenshots:/data/input \
  -v ./output:/data/output \
  screenshot-forge

# iOS only
docker run --rm \
  -v ./screenshots:/data/input \
  -v ./output:/data/output \
  screenshot-forge -i /data/input -o /data/output -p ios

# Android phone only
docker run --rm \
  -v ./screenshots:/data/input \
  -v ./output:/data/output \
  screenshot-forge -i /data/input -o /data/output -p android -d phone
```

Or with Docker Compose. Put your screenshots in `./input`:

```bash
docker compose run --rm forge
docker compose run --rm forge -p ios
docker compose run --rm forge -p android -d phone
```

## Output structure

```
output/
  ios/
    6.7inch/
      home_1290x2796.png
      home_2796x1290.png
      demo_1290x2796.mp4    # from a video input
      demo_2796x1290.mp4
    6.5inch/
      home_1242x2688.png
      home_2688x1242.png
      home_1284x2778.png
      home_2778x1284.png
    5.5inch/
    ipad_12.9inch/
  android/
    phone/
    7inch_tablet/
    10inch_tablet/
    chromebook/
```

## How the resize works

1. Scale the source image so it fully covers the target dimensions
2. Center-crop to the exact target size

No letterboxing. No stretching.

## Roadmap

- [x] Batch resize + center-crop
- [x] CLI
- [x] GUI (Tkinter)
- [x] Docker
- [x] Web interface (Flask + drag-and-drop)
- [x] App preview video cropping (Apple / iOS, via ffmpeg)
- [ ] Device frame overlays (iPhone/Pixel mockups)
- [ ] Text overlays (title + subtitle per screenshot)
- [ ] Fastlane integration
- [ ] CI/CD GitHub Action

## Tech stack

| Component | Tech     |
|-----------|----------|
| Language  | Python   |
| Imaging   | Pillow   |
| Video     | ffmpeg   |
| GUI       | Tkinter  |
| CLI       | argparse |
| Web       | Flask    |
| Container | Docker   |

## License

MIT

Built by [Alejandro Cordon](https://alejandrocordon.com)
