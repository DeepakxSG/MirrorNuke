**Current source patch: 2.0.4** — fixes the Windows remote-video stream attachment path, brings up a visible startup screen before asynchronous settings load, and loads independent preferences/secure-storage values concurrently. Retains local preview pinch-zoom, pan, zoom-aware remote input, and immersive full-screen viewing.

**Current source patch: 2.0.3** — retains the Windows remote-video receiver and Android capture-startup fixes, and adds local preview pinch-zoom/pan plus a HUD-free full-screen viewer. Version 2.0.3 fixes nullable WebRTC track IDs and removes the redundant Matrix4 import. See [VIDEO_TROUBLESHOOTING.md](VIDEO_TROUBLESHOOTING.md) for blank-preview diagnostics and [ZOOM_FULLSCREEN_GUIDE.md](ZOOM_FULLSCREEN_GUIDE.md) for the new viewer controls.

Private, one-click, zero-cloud screen + stereo audio casting and remote control across **Windows 10/11**, **Android 7+**, and **Android TV** — peer-to-peer over your own Wi-Fi, with a built-in signaling server (no terminal or Node.js required on Windows).

- **One-Click Local Hosting:** Windows launches a built-in Dart WebSocket signaling and room directory server automatically on port `8080`, displaying your local Wi-Fi URL (`ws://<pc-ip>:8080`) with one-tap copy and automatic LAN discovery.
- **Two-Way Screen & Stereo Audio Casting:** Cast Android screen + internal media/game audio directly into Windows PC speakers, or mirror your Windows desktop + system audio to your phone or Android TV.
- **Ultra-Low-Latency Audio Pipeline:** 4:1 IMA-ADPCM 48 kHz stereo framing with 16-bit sequence numbers and an adaptive jitter buffer that smooths Wi-Fi spikes without latency drift.
- **Sharp Text & Bandwidth Presets:** Configures WebRTC `contentHint = 'detail'`, `maintain-resolution` degradation preference, and real `maxBitrate` caps (*Gaming 60 FPS / 10 Mbps*, *Movie 30 FPS / 5 Mbps*, *Data Saver 20 FPS / 1.5 Mbps*).
- **Cross-Platform Remote Control:** Native `user32.dll` mouse, scroll, multi-monitor mapping, and Unicode text injection on Windows; Android Accessibility touch gestures, navigation keys, and clipboard sync.
- **Authenticated P2P Privacy:** Media never leaves your network; devices verify each other with HMAC-SHA256 proofs bound to both WebRTC DTLS fingerprints.

```text
PC (Embedded Dart Server + WebRTC) ── DTLS/SRTP ── Phone / Android TV
```

## Quick Start (Zero-Terminal on Windows)

1. **Launch MirrorNuke on your Windows PC:**
   - **Host local server on this PC** is enabled by default. The Overview screen shows your PC's Wi-Fi address (for example `ws://192.168.1.10:8080`).
2. **Open MirrorNuke on your Android Phone or TV:**
   - Tap **Scan Wi-Fi** on the **Devices** tab to auto-detect your PC, or paste the `ws://<pc-ip>:8080` address in **Settings**.
   - Use the same **Room Code** and **Pairing Password** (8+ characters) on both devices.
3. **Cast:**
   - Enable **Share this device screen** + **Stream device audio** on your phone, tap **Start Casting Session**, and connect from your PC to watch with audio coming through your PC speakers.

*(Optional)* For an always-on headless relay (Raspberry Pi, Docker, Linux VPS), run `npm install && npm start` inside `server/` and toggle off **Host local server on this PC**.

## Building `.exe` and `.apk`

### Cloud Build via GitHub Actions
Push this repository to `main` (or run **Actions → Build MirrorNuke → Run workflow**). Download the compiled artifacts:
- `MirrorNuke-windows-installer` (`MirrorNuke-Setup.exe`)
- `MirrorNuke-windows-portable` (`mirrornuke_app.exe` + runtime)
- `MirrorNuke-android-apk` (`app-release.apk`)

### Local Build on Windows
```bash
python tools/setup_project.py
cd mirrornuke_app
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
flutter build apk --release
```

## Tests

```bash
cd server && npm install && npm test
cd ../
python tools/setup_project.py
cd mirrornuke_app && flutter analyze --no-fatal-infos && flutter test
```

See [VIDEO_TROUBLESHOOTING.md](VIDEO_TROUBLESHOOTING.md) for a focused phone-to-PC screen test and how to interpret the new on-screen diagnostic messages.


## Version 2.0.2: local zoom and immersive viewing

The remote viewer now supports local two-finger preview zoom/pan, coordinate-correct remote input while zoomed, preview reset, and a HUD-free full-screen mode. See `ZOOM_FULLSCREEN_GUIDE.md` and `V2.0.2_CHANGELOG.md`.


## Version 2.0.3: CI null-safety and workflow update

- Fixed nullable `MediaStreamTrack.id` handling in the remote video receiver. Tracks without an ID are deduplicated using object identity rather than passing `String?` to a `String` set.
- Removed the redundant direct `vector_math` import and dependency; `Matrix4` is already exported by Flutter's gestures library used by the viewer.
- Updated the Windows installer version to 2.0.3.
- Updated GitHub Actions to also validate pull requests, use read-only repository permissions, name each validation/build step clearly, and retain build artifacts for 14 days.

## Version 2.0.4: startup feedback and remote-video receiver fix

The app renders its first Flutter frame before awaiting saved settings, so users see a branded startup panel instead of a blank white window. The panel reports real initialization stages and offers a retry if settings initialization fails. Shared preferences and secure-storage reads now begin concurrently. The Windows viewer reuses actual remote MediaStreams from the WebRTC event/peer connection and no longer calls `MediaStream.addTrack()` with an already-received remote track.
