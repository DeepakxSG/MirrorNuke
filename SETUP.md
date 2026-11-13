# MirrorNuke — Build, Audio Cast & Test Guide

## A) Build `.exe` and `.apk` via GitHub Actions (Recommended)

1. Upload every file and folder inside `MirrorNuke/` to your GitHub repository (make sure `.github/workflows/build.yml` is included).
2. Open **Actions → Build MirrorNuke → Run workflow** (also runs automatically on every push to `main`).
3. Once all jobs turn green, download from **Artifacts**:
   - **`MirrorNuke-windows-installer`** → `MirrorNuke-Setup.exe`
   - **`MirrorNuke-windows-portable`** → standalone Windows folder (`mirrornuke_app.exe`)
   - **`MirrorNuke-android-apk`** → `app-release.apk` (Android 7+ phones and Android TV)

## B) Build Locally on Windows

### Prerequisites
- **Flutter SDK** (stable)
- **Python 3.10+**
- **Android Studio** (Android SDK + platform-tools)
- **Visual Studio 2022** with **Desktop development with C++** and **C++ ATL**
- **Inno Setup 6** (optional, to compile `installer/mirrornuke.iss`)

### Commands
```bash
python tools/setup_project.py
cd mirrornuke_app
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release
flutter build windows --release
```

## C) Casting Movies with Audio (Phone → PC Speakers)

1. Open **MirrorNuke** on your Windows PC. Keep **Host local server on this PC** switched **ON** — no terminal or Node.js needed. Note your PC's Wi-Fi URL shown on the Overview card (e.g., `ws://192.168.1.10:8080`).
2. Allow **MirrorNuke** through **Windows Defender Firewall** on **Private networks** when prompted on first launch.
3. Open **MirrorNuke** on your Android phone, go to **Devices → Scan Wi-Fi** (or enter the `ws://` URL in **Settings**), enter the same **Room Code** and **Pairing Password** (8+ characters), and enable **Share this device screen** + **Stream device audio**.
4. Tap **Start Casting Session** on the phone, approve the screen/audio capture prompts, and tap **Connect** on your PC.
   - *Note:* DRM-protected apps (Netflix, Prime Video) block `AudioPlaybackCapture` at the Android OS level; local video players (VLC, MX Player), browsers, YouTube, and games stream stereo audio normally.


## D) Phone controls work but PC preview is blank

The navigation controls use a WebRTC data channel, while the picture uses a separate video track. A working Back/Home/Recents button does not prove that a video frame reached the Windows renderer.

1. Rebuild and install the updated APK and Windows app from the same source version.
2. On the phone, start a fresh sharing session and approve screen capture. On Android 14+, choose **Entire screen** when that option is shown if you want the whole phone display.
3. On Windows, connect to the phone from the Devices/Remote view and wait for the video status banner.
4. If it says no video track arrived, stop sharing on the phone and start a new session. If it says a track arrived but no frames are rendering, check the Android capture permission and repeat the capture prompt.
5. Test on the phone home screen first. Some apps deliberately block screen capture and may appear black.

See `VIDEO_TROUBLESHOOTING.md` for the full explanation and diagnostic-log collection steps.


## E) Local zoom and full-screen viewer (introduced in 2.0.2)

See `ZOOM_FULLSCREEN_GUIDE.md` for pinch-zoom, preview pan, zoom reset, full-screen shortcuts, and the recommended hardware test sequence. These viewer features are preserved in 2.0.4. Rerun `python tools/setup_project.py` so the generated Flutter project receives the current source and dependency templates before building.

## F) MirrorNuke 2.0.4 startup and remote-video update

- The first Flutter frame now displays a branded startup panel before saved settings finish loading.
- Settings and secure-storage values are loaded concurrently. The startup panel shows an indeterminate progress bar, not a fabricated percentage.
- The Windows dashboard title is set to `MirrorNuke`.
- The viewer no longer calls `MediaStream.addTrack()` with a remote WebRTC track. It registers actual remote streams delivered by WebRTC and polls the peer connection for remote streams when needed.

See `STARTUP_AND_VIDEO_TESTING.md` for the recommended Windows startup and phone-to-PC video test sequence.
