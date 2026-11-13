# MirrorNuke — Phone-to-PC blank preview troubleshooting

## Why the controls can work while video is blank

MirrorNuke uses separate channels:

- The **control data channel** sends Back, Home, Recents, mouse and keyboard actions.
- The **video RTP track** transports the phone's screen frames.

Therefore, working navigation buttons confirm that the control channel is authenticated, but do not prove that the screen frames are being captured, delivered, or attached to the Windows video renderer.

## Fixes included in 2.0.1

The receiver no longer discards a WebRTC `onTrack` event just because its `streams` list is empty. It now creates a receiver-side stream for streamless tracks, accepts compatibility callbacks, checks remote receivers if an event is missed, and prefers video-bearing streams over audio-only streams. The app also shows whether no video track arrived, a track arrived but produced no frames, or the first video frame rendered successfully.

Android capture startup now waits for an affirmative foreground-service start result before it asks flutter_webrtc to begin MediaProjection capture. This follows Android's MediaProjection foreground-service sequence: obtain user consent, start the correctly typed foreground service, and then acquire the projection.

## Test procedure

1. Build and install the APK generated from this updated source. Rebuild the Windows app from the same source.
2. Open MirrorNuke on both devices. Confirm that the room code and pairing password match and each device has a unique device name.
3. On the phone, enable **Share this device screen** and start a fresh session. Approve the Android screen-capture prompt. If Android offers a choice between a single app and the entire display, choose the entire display for this test.
4. On Windows, connect to the phone. First test on the Android home screen, not inside a protected streaming app.
5. Read the message shown over the preview:
   - **Waiting for phone video track** / **Controls connected, but the phone has not sent a video track**: capture track negotiation/delivery did not complete. Stop the session on both ends and start sharing again.
   - **Video track received; waiting for first frame** / **Video track connected, but no frames are rendering**: a track reached Windows, but the phone is not producing usable frames or the renderer is not receiving them. Recheck the Android capture prompt, restart the phone app, and start a new capture session.
   - **Video is live**: the Windows renderer has displayed its first frame.
6. If the problem remains, open **Settings → View Diagnostic Log** on the phone and Windows app. Use **Copy log** in the diagnostic dialog and share the recent lines around `capture.android`, `view.track`, `view.stream`, `view.video`, and `view.ice`. Remove any private IP addresses before posting publicly; never share pairing passwords or server tokens.

## Notes

- Android may black out apps that opt out of screen capture or show protected media. Use the home screen as the baseline test.
- Android requires user consent for each new MediaProjection session; do not expect a previous consent to authorize a later session.
- The Windows and Android builds must be rebuilt from this source. Updating only the Windows app will not change the Android capture code.
- If you report the issue, include the phone's Android version, the exact diagnostic banner, and the relevant diagnostic-log entries. Do not share pairing passwords or server tokens.
