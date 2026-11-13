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
