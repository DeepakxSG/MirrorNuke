# MirrorNuke Publishing Checklist

## Store & Signing Costs
- **Google Play Console:** One-time $25 developer registration fee.
- **Microsoft Store:** Free developer registration for individuals and companies; Microsoft takes a fee only if using Microsoft commerce.
- **Windows Code Signing (optional):** Azure Artifact Signing (~$10/month) prevents Windows SmartScreen warnings on direct `.exe` downloads.

## Google Play Release Steps
1. Create an upload keystore (`keytool -genkey -v -keystore mirrornuke-release.jks ...`) and configure signing in `android/app/build.gradle.kts`. Back up the keystore safely.
2. Build a release App Bundle: `flutter build appbundle --release`.
3. Declare `MediaProjection` (screen/audio casting) and `AccessibilityService` (optional remote control) in Play Console App Content with a short demo video explaining user-initiated casting.
4. You can also distribute `app-release.apk` directly via GitHub Releases for sideloading on Android phones and Android TVs.

## Microsoft Store / Windows Distribution
- Package as MSIX (`dart run msix:create`) for Microsoft Store submission, or sign both `mirrornuke_app.exe` and `dist/MirrorNuke-Setup.exe` with `signtool.exe` for direct website/GitHub distribution.
