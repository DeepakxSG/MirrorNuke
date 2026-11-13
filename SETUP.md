# MirrorNuke — Build, Audio Cast & Test Guide

MirrorNuke is a cross-platform screen & audio casting and remote-control app for **Windows 10/11**, **Android 7+**, and **Android TV**.

---

## A) Build `.exe` and `.apk` via GitHub Actions (No Local SDK Needed)

1. Upload **every file and folder** inside `MirrorNuke/` to your GitHub repository (including `.github/workflows/build.yml`).
2. Open your repository on GitHub → **Actions** tab → select **Build MirrorNuke** → click **Run workflow** (also runs automatically on every push to `main`).
3. Once both jobs turn green, scroll down to **Artifacts** at the bottom of the workflow run and download:
   - **`MirrorNuke-windows-installer`** → `MirrorNuke-Setup.exe` (Windows 10 & 11 installer with bundled VC++ runtime)
   - **`MirrorNuke-windows-portable`** → standalone Windows folder (`mirrornuke_app.exe` + DLLs)
   - **`MirrorNuke-android-apk`** → `app-release.apk` (installable on Android phones and Android TV)

---

## B) Build Locally on Windows

### Prerequisites
- **Flutter SDK** (stable channel)
- **Python 3.10+**
- **Node.js 18+** (for the signaling server)
- **Android Studio** (with Android SDK + platform-tools)
- **Visual Studio 2022** with **Desktop development with C++** and the **C++ ATL** component (required by `flutter_secure_storage`)
- **Inno Setup 6** (optional, to package `MirrorNuke-Setup.exe`)

### Commands
```bash
python tools/setup_project.py
cd mirrornuke_app
flutter doctor -v
flutter analyze
flutter build apk --release
flutter build windows --release
```

Compiled outputs:
- **Android APK:** `mirrornuke_app/build/app/outputs/flutter-apk/app-release.apk`
- **Windows EXE:** `mirrornuke_app/build/windows/x64/runner/Release/mirrornuke_app.exe`
- **Windows Installer:** Compile `installer/mirrornuke.iss` with Inno Setup 6 → `dist/MirrorNuke-Setup.exe`

---

## C) Start the Signaling & Room Discovery Server

Run on any PC on your Wi-Fi network:
```bash
cd server
npm install
npm start
```
- Listens on `0.0.0.0:8080` by default.
- Optional shared server access token:
  ```bash
  set MIRRORNUKE_TOKEN=your-secret-token
  npm start
  ```
- Allow **Node.js** and **MirrorNuke** through Windows Defender Firewall on **Private networks**.

---

## D) Casting Movies with Audio (Phone → PC Speakers & PC → Phone/TV)

### Phone → Windows PC Speakers (Movies, YouTube, Games)
1. Open **MirrorNuke** on both your Windows PC and Android phone.
2. In **Settings**, enter the same **Server URL** (`ws://YOUR-PC-IP:8080`), **Room code**, and **Pairing password** (8+ characters), and set unique device names (e.g., `pc` and `phone`).
3. On your **Android phone**:
   - Enable **Share this device screen** and **Stream device audio**.
   - Optional: Tap **Enable Remote Touch Control** to allow touch/navigation control from your PC.
   - Tap **Start Casting Session** and approve both the screen-capture and audio-capture prompts.
4. On your **Windows PC**:
   - Open the **Devices** tab → tap **Connect** next to your phone (or enable **View & control** on Overview and tap **Start Casting Session**).
   - Ensure the speaker icon in the top viewer toolbar is unmuted — your phone's movie audio plays directly through your PC speakers.
   - *Note:* DRM-protected apps (such as Netflix or Prime Video) block Android's `AudioPlaybackCapture` at the OS level; YouTube, local video players (VLC, MX Player), browsers, and games stream audio normally.

### Windows PC → Phone / Android TV
1. Enable **Share this device screen** and **Stream device audio** on the PC and tap **Start Casting Session**.
2. Connect from your phone or Android TV — both video and Windows system audio stream live.
