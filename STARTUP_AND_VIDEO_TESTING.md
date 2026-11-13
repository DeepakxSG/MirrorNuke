# MirrorNuke 2.0.4 — Startup and video test guide

## Startup screen
1. Install the Windows build generated from this source version.
2. Launch MirrorNuke normally.
3. Confirm the branded loading screen appears instead of a blank white window and the window title says `MirrorNuke`.
4. Confirm the status changes while saved preferences are being loaded, then the dashboard appears.
5. If settings storage fails, confirm the screen shows an error and a Try again button.
6. Once the dashboard appears, check the built-in PC server card; it should show its actual starting/ready/error status.

The progress bar is intentionally indeterminate. It does not claim a fake percentage because secure storage and plugin initialization do not expose reliable completion percentages.

## Remote video
1. Install the same build version on Windows and Android.
2. Start screen sharing on Android and approve the Android capture prompt.
3. Connect from Windows.
4. Confirm the app no longer reports `MediaStreamAddTrack ... track is null`.
5. Check for `Video track received; waiting for its remote stream…`, `Video track attached; waiting for first frame…`, or `Video is live`.
6. If no video appears, copy the diagnostic logs from both devices and include the WebRTC signalling/track entries.

## Test both directions
- Android shares to Windows viewer.
- Windows shares to Android viewer.
- Verify Back/Home/Recent controls still work.
- Verify zoom, pan, and full-screen viewing remain available.

## Build
Run `python tools/setup_project.py`, then inside `mirrornuke_app` run `flutter analyze --no-fatal-infos`, `flutter test`, `flutter build windows --release`, and `flutter build apk --release`.
