# MirrorNuke Publishing Checklist

## Store & Signing Costs
- **Google Play Console:** One-time $25 developer registration fee.
- **Microsoft Store:** Free developer registration for individuals and companies; Microsoft takes a fee only if using Microsoft commerce.
- **Windows Code Signing (optional):** Azure Artifact Signing (~$10/month) prevents Windows SmartScreen warnings on direct `.exe` downloads.

## Google Play Release Steps
1. Create an upload keystore (`keytool -genkey -v -keystore mirrornuke-release.jks ...`) and configure signing in `android/app/build.gradle.kts`. Back up the keystore safely.
2. Build a release App Bundle: `flutter build appbundle --release`.
3. Declare `MediaProjection` (screen/audio casting) and `AccessibilityService` (optional remote control) in Play Console App Content with a short demo video explaining user-initiated casting.
4. For Android TV listings, add a 320x180 `android:banner` drawable to `AndroidManifest.xml`.

## Microsoft Store / Windows Distribution
- Package as MSIX (`dart run msix:create`) for Microsoft Store submission, or sign both `mirrornuke_app.exe` and `dist/MirrorNuke-Setup.exe` with `signtool.exe` for direct website/GitHub distribution.


## Version 2.0.2 features

- Local preview-only pinch zoom and pan; remote input coordinates are mapped through the preview transform.
- HUD-free full-screen viewer with Windows borderless monitor mode and Android immersive mode.
- Exit by Esc/F11 on Windows or the temporary on-screen exit control.


## Version 2.0.4 startup and video update

- Branded loading screen is shown before settings and secure-storage initialization completes.
- Independent preferences and credential reads run concurrently.
- Startup timing is written to diagnostic logs to help identify slow initialization.
- Windows viewer registers real WebRTC remote streams and avoids `MediaStream.addTrack()` on already-received remote tracks.
- Preserves preview zoom, zoom-aware controls, full-screen viewing, multi-monitor controls, and existing navigation controls.
- Windows installer and Android package version are updated to 2.0.4.

Before publishing, wait for Android and Windows GitHub Actions jobs to pass, then attach the generated APK, Windows installer, and portable ZIP to the GitHub Release.
