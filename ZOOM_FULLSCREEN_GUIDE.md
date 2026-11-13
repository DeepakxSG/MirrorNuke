# MirrorNuke — Zoom and Full-Screen Guide

## Local preview zoom

1. Connect to the remote device and wait for the live screen.
2. Put two fingers on the video preview and pinch outward to enlarge the preview.
3. Keep two fingers on the preview and move them to pan around the enlarged area.
4. Use the toolbar's **Reset preview zoom** button, double-tap the preview, or press **Ctrl+0** to return to 100%.

The transform is applied only to MirrorNuke's local video widget. No zoom, display scaling, or resolution command is sent to the remote Windows PC.

While two fingers are down, the gesture is consumed locally. One-finger touch/mouse actions continue to control the remote device. When a second finger joins an active one-finger press, MirrorNuke sends a release to prevent a stuck remote press.

## Full screen

- Click the **Full screen** icon in the viewer toolbar or press **F11**.
- The viewer hides its toolbar, status banner, metrics and other in-app HUD elements.
- On Windows the MirrorNuke window switches to a borderless, monitor-filling window; the original window style and size are restored when leaving full screen.
- On Android the system status/navigation bars are hidden.
- Press **Esc** or **F11** on Windows to exit. On touch screens, tap the screen to reveal the temporary exit icon in the top-right corner, then tap it.

## Suggested test sequence

1. Build and install the same project version on the devices that need it.
2. Connect Windows to Android and verify normal one-finger remote taps still work.
3. Pinch in/out on the preview and confirm the Android/PC's actual display is not changing scale.
4. While zoomed, tap a small visible target and confirm the remote pointer lands on that same visible location.
5. Double-tap or use Reset preview zoom and confirm the preview returns to 100%.
6. Enter full screen, verify the HUD disappears, then exit with Esc/F11 or the temporary exit button.
7. Re-enter full screen and close the session; verify the Windows window returns to its original size and style.

## Notes

- Zoom works on the received preview; it does not increase the source resolution. Fine text may look larger but can become pixelated if the incoming stream resolution is low.
- Protected apps may still block capture and show a black area.
- Check the diagnostic log if a gesture, window restoration, or remote pointer action behaves unexpectedly.
