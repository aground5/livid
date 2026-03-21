# LiveWallpaperEnabler

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**LiveWallpaperEnabler** is a powerful macOS utility that allows you to convert any video (local or YouTube) into a native **macOS Live Wallpaper (Aerial)**.

Unlike simple video wallpaper apps that run an overlay window, this tool **patches the video file headers** and injects them into the macOS System Wallpaper database (`entries.json`). This means your custom wallpapers behave exactly like Apple's official Aerials: they work on the Lock Screen, support slow-motion (high framerate) playback, and integrate seamlessly with the native macOS "Liquid" transitions.

---

## 📸 Screenshots

| **Library & Import** | **Trim & Editor** |
|:---:|:---:|
| <!-- Insert Library Screenshot Here --> | <!-- Insert Editor Screenshot Here --> |
| *Browse local files and download from YouTube* | *Frame-accurate trimming and preview* |

| **System Integration** | **Render Queue** |
|:---:|:---:|
| <!-- Insert System Settings Screenshot Here --> | <!-- Insert Render Queue Screenshot Here --> |
| *Wallpapers appear natively in System Settings* | *Background transcoding with FFmpeg* |

---

## ✨ Key Features

*   **Native Aerial Injection**: Parses and patches MOV atoms (`moov`, `trak`, `csgm`, `sgpd`, `tapt`) to make custom videos recognized by macOS as official dynamic wallpapers.
*   **Optimal Aerial Transcoding**: Includes a custom-built static FFmpeg engine (`WebMSupport`) that converts videos to the specific **10-bit HEVC** format and GOP structure required by the macOS Lock Screen.
*   **Smart Quality Engine**: Automatically detects HDR, Wide Color (P3), and High Chroma content, applying intelligent tone-mapping or 4:4:4 downsampling strategies.
*   **Integrated YouTube Downloader**: Fetches videos up to **8K HDR** using the bundled standalone `yt-dlp` runtime, with automatic metadata extraction.
*   **System Catalog Management**: Modifies the system's `entries.json` manifest to create custom categories and register assets directly into the macOS Wallpaper settings.
*   **XPC Helper Architecture**: Uses a privileged XPC Helper to handle heavy tasks (FFmpeg transcoding, binary execution) without blocking the main UI thread.

---

## 🛠 Tech Stack

*   **UI Framework**: SwiftUI (macOS 14+) with AppKit interop for visual effects.
*   **Video Core**: `AVFoundation`, `VideoToolbox`, and a custom C++ bridge to `FFmpeg` (libavcodec, libx265, libplacebo).
*   **Parsing**: Custom Swift-based QuickTime Atom Parser (`QtParser`) for binary manipulation of MOV headers.
*   **Networking**: `Hummingbird` (Local Asset Server) & `NSXPCConnection`.
*   **Dependencies**: bundled standalone `yt-dlp`, packaged Python runtime.

---

## 🚀 Getting Started

### Prerequisites

*   macOS 26.0 or later.
*   Xcode 15.0+ for building.
*   **Homebrew** (required to install build tools for FFmpeg).

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/aground5/livid-community.git
    cd livid-community
    ```

2.  **Build & Run with Make:**
    The project provides an automated `Makefile` that handles compiling all FFmpeg dependencies, resolving SPM packages, copying frameworks, and building the Xcode project.
    Simply run:
    ```bash
    make run
    ```
    *Note: The first time you run this, it may take several minutes to build FFmpeg from source. Subsequent runs will be much faster.*

3.  **Reset / Clean Build Cache:**
    If you encounter any caching issues or Swift Package Manager errors, you can completely reset the build environment and SPM caches:
    ```bash
    make clean-all
    ```

### Usage

1.  **Import**: Drag and drop a video file or paste a YouTube URL in the **Start** tab.
2.  **Prepare**: The app will analyze the metadata (HDR, framerate, bitrate).
3.  **Edit**: Switch to the **Editor** tab to trim the video. Use the "Side-by-Side" view to compare start/end loops.
4.  **Render**: Add to the Render Queue. The app will transcode the video using the optimal format to ensure macOS compatibility.
5.  **Register**: Go to the **Library**, right-click your rendered wallpaper, and select **"Add to System Catalog"**.
6.  **Apply**: Open macOS **System Settings -> Wallpaper**. Your custom category and wallpaper will appear there.

---

## 📂 Project Structure

```bash
.
├── LiveWallpaperEnabler
│   ├── App                 # Entry point & Visual Effect Views
│   ├── Core
│   │   ├── Export          # Transcoding logic
│   │   ├── Models          # Media & Aerial Manifest models
│   │   ├── Network         # YouTube & XPC Connection logic
│   │   ├── QtParser        # Custom QuickTime Atom Parser/Writer
│   │   ├── Services        # RenderQueue, AerialService, ThumbnailManager
│   │   └── Storage         # Wallpaper persistence
│   ├── Features            # SwiftUI Views (Main, Editor, Library, Catalog)
│   └── LiveWallpaperHelper # XPC Service (Privileged operations, BinaryManager)
├── Packages                # Local Swift Packages
│   ├── WebMSupport         # C++ Bridge for FFmpeg & Transcoding
│   └── cpython-3.13.9-macos-aarch64-none  # packaged standalone Python + yt-dlp runtime
└── Makefile                # Main build script for ffmpeg, deps, and Xcode
```

---

## ⚠️ Disclaimer

This tool modifies system configuration files (`entries.json` in the Application Support directory) to inject wallpapers. While safe, it is recommended to keep backups. The app includes a "Health Check" feature in the Helper service.

This project is for educational purposes. Please respect the copyright of videos downloaded from YouTube.

---

## 📄 License

This project is licensed under the MIT License - see the `LICENSE` file for details.

**Note on Dependencies**:
*   **FFmpeg** is licensed under LGPL/GPL.
*   **yt-dlp** is Unlicense/Public Domain.
*   **yt-dlp** is released under the Unlicense.

---

## 📧 Contact

**Author**: k2zoo
**Issues**: Please file an issue on GitHub for bugs or feature requests.

---

## 🌐 Get Livid

Looking for premium, high-quality video wallpapers? We are currently building a marketplace for exclusive, high-resolution Live Wallpapers!
Visit us at: **[https://getlivid.app/](https://getlivid.app/)**
