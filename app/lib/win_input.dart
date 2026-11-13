import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:ffi/ffi.dart';
import 'security.dart';

final class _WinRect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int cbSize;
  external _WinRect rcMonitor;
  external _WinRect rcWork;
  @Uint32()
  external int dwFlags;
}

final class _MouseInput extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class _KeybdInput extends Struct {
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class _HardwareInput extends Struct {
  @Uint32()
  external int uMsg;
  @Uint16()
  external int wParamL;
  @Uint16()
  external int wParamH;
}

final class _InputUnion extends Union {
  external _MouseInput mi;
  external _KeybdInput ki;
  external _HardwareInput hi;
}

final class _Input extends Struct {
  @Uint32()
  external int type;
  external _InputUnion u;
}

typedef _MonitorEnumProcNative = Int32 Function(
  IntPtr hMonitor,
  IntPtr hdc,
  Pointer<_WinRect> lprcMonitor,
  IntPtr dwData,
);

typedef _EnumDisplayMonitorsNative = Int32 Function(
  IntPtr hdc,
  Pointer<_WinRect> lprcClip,
  Pointer<NativeFunction<_MonitorEnumProcNative>> lpfnEnum,
  IntPtr dwData,
);
typedef _EnumDisplayMonitorsDart = int Function(
  int hdc,
  Pointer<_WinRect> lprcClip,
  Pointer<NativeFunction<_MonitorEnumProcNative>> lpfnEnum,
  int dwData,
);

typedef _GetSystemMetricsNative = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);

typedef _SendInputNative = Uint32 Function(Uint32 cInputs, Pointer<_Input> pInputs, Int32 cbSize);
typedef _SendInputDart = int Function(int cInputs, Pointer<_Input> pInputs, int cbSize);

typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _SetWindowPosNative = Int32 Function(
  IntPtr hWnd,
  IntPtr hWndInsertAfter,
  Int32 X,
  Int32 Y,
  Int32 cx,
  Int32 cy,
  Uint32 uFlags,
);
typedef _SetWindowPosDart = int Function(
  int hWnd,
  int hWndInsertAfter,
  int X,
  int Y,
  int cx,
  int cy,
  int uFlags,
);

typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);

typedef _GetWindowLongPtrNative = IntPtr Function(IntPtr hWnd, Int32 nIndex);
typedef _GetWindowLongPtrDart = int Function(int hWnd, int nIndex);
typedef _SetWindowLongPtrNative = IntPtr Function(IntPtr hWnd, Int32 nIndex, IntPtr value);
typedef _SetWindowLongPtrDart = int Function(int hWnd, int nIndex, int value);
typedef _GetWindowRectNative = Int32 Function(IntPtr hWnd, Pointer<_WinRect> rect);
typedef _GetWindowRectDart = int Function(int hWnd, Pointer<_WinRect> rect);
typedef _MonitorFromWindowNative = IntPtr Function(IntPtr hWnd, Uint32 flags);
typedef _MonitorFromWindowDart = int Function(int hWnd, int flags);
typedef _GetMonitorInfoNative = Int32 Function(IntPtr monitor, Pointer<_MonitorInfo> info);
typedef _GetMonitorInfoDart = int Function(int monitor, Pointer<_MonitorInfo> info);

final List<Rect> _mons = [];

int _enumCb(int hMonitor, int hdc, Pointer<_WinRect> r, int data) {
  _mons.add(Rect.fromLTRB(
    r.ref.left.toDouble(),
    r.ref.top.toDouble(),
    r.ref.right.toDouble(),
    r.ref.bottom.toDouble(),
  ));
  return 1;
}

/// Injects mouse/keyboard input and manages window state on Windows via user32.dll.
class WinInput {
  static DynamicLibrary? _user32;
  static late _EnumDisplayMonitorsDart _enumDisplayMonitors;
  static late _GetSystemMetricsDart _getSystemMetrics;
  static late _SendInputDart _sendInput;
  static late _GetForegroundWindowDart _getForegroundWindow;
  static late _SetWindowPosDart _setWindowPos;
  static late _ShowWindowDart _showWindow;
  static late _GetWindowLongPtrDart _getWindowLongPtr;
  static late _SetWindowLongPtrDart _setWindowLongPtr;
  static late _GetWindowRectDart _getWindowRect;
  static late _MonitorFromWindowDart _monitorFromWindow;
  static late _GetMonitorInfoDart _getMonitorInfo;
  static bool _bound = false;

  static int _fullscreenHwnd = 0;
  static int _savedWindowStyle = 0;
  static Rect? _savedWindowRect;

  static List<Rect> _cache = [];
  static int _cacheAt = 0;

  static bool _ensureBound() {
    if (!Platform.isWindows) return false;
    if (_bound) return true;
    try {
      _user32 = DynamicLibrary.open('user32.dll');
      _enumDisplayMonitors = _user32!
          .lookupFunction<_EnumDisplayMonitorsNative, _EnumDisplayMonitorsDart>('EnumDisplayMonitors');
      _getSystemMetrics =
          _user32!.lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>('GetSystemMetrics');
      _sendInput = _user32!.lookupFunction<_SendInputNative, _SendInputDart>('SendInput');
      _getForegroundWindow =
          _user32!.lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>('GetForegroundWindow');
      _setWindowPos = _user32!.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
      _showWindow = _user32!.lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');
      _getWindowLongPtr = _user32!.lookupFunction<_GetWindowLongPtrNative, _GetWindowLongPtrDart>('GetWindowLongPtrW');
      _setWindowLongPtr = _user32!.lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>('SetWindowLongPtrW');
      _getWindowRect = _user32!.lookupFunction<_GetWindowRectNative, _GetWindowRectDart>('GetWindowRect');
      _monitorFromWindow = _user32!.lookupFunction<_MonitorFromWindowNative, _MonitorFromWindowDart>('MonitorFromWindow');
      _getMonitorInfo = _user32!.lookupFunction<_GetMonitorInfoNative, _GetMonitorInfoDart>('GetMonitorInfoW');
      _bound = true;
      return true;
    } catch (e) {
      AppLog.add('winInput.bind', e);
      return false;
    }
  }

  static void configureWindow({bool minimize = false}) {
    if (!_ensureBound()) return;
    try {
      final hwnd = _getForegroundWindow();
      if (hwnd != 0) {
        _setWindowPos(hwnd, 0, 0, 0, 760, 820, 0x0002 | 0x0004);
        if (minimize) {
          _showWindow(hwnd, 6);
        }
      }
    } catch (e) {
      AppLog.add('winInput.configureWindow', e);
    }
  }

  /// Makes the active MirrorNuke window borderless and fits it to its current
  /// monitor. The original style and rectangle are restored on exit.
  static void setViewerFullscreen(bool enabled) {
    if (!_ensureBound()) return;
    try {
      if (enabled) {
        if (_fullscreenHwnd != 0) return;
        final hwnd = _getForegroundWindow();
        if (hwnd == 0) return;
        final rectPtr = calloc<_WinRect>();
        final infoPtr = calloc<_MonitorInfo>();
        try {
          if (_getWindowRect(hwnd, rectPtr) == 0) return;
          final originalRect = Rect.fromLTRB(
            rectPtr.ref.left.toDouble(),
            rectPtr.ref.top.toDouble(),
            rectPtr.ref.right.toDouble(),
            rectPtr.ref.bottom.toDouble(),
          );
          final originalStyle = _getWindowLongPtr(hwnd, -16); // GWL_STYLE
          var target = originalRect;
          final monitor = _monitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
          if (monitor != 0) {
            infoPtr.ref.cbSize = sizeOf<_MonitorInfo>();
            if (_getMonitorInfo(monitor, infoPtr) != 0) {
              final r = infoPtr.ref.rcMonitor;
              target = Rect.fromLTRB(r.left.toDouble(), r.top.toDouble(), r.right.toDouble(), r.bottom.toDouble());
            }
          }
          _fullscreenHwnd = hwnd;
          _savedWindowStyle = originalStyle;
          _savedWindowRect = originalRect;
          const overlappedWindow = 0x00CF0000;
          const popup = 0x80000000;
          _setWindowLongPtr(hwnd, -16, (originalStyle & ~overlappedWindow) | popup);
          _setWindowPos(
            hwnd,
            0,
            target.left.round(),
            target.top.round(),
            target.width.round(),
            target.height.round(),
            0x0020 | 0x0004 | 0x0200, // SWP_FRAMECHANGED | NOZORDER | NOOWNERZORDER
          );
        } finally {
          calloc.free(rectPtr);
          calloc.free(infoPtr);
        }
      } else {
        final hwnd = _fullscreenHwnd;
        final rect = _savedWindowRect;
        if (hwnd == 0 || rect == null) return;
        _setWindowLongPtr(hwnd, -16, _savedWindowStyle);
        _setWindowPos(
          hwnd,
          0,
          rect.left.round(),
          rect.top.round(),
          rect.width.round(),
          rect.height.round(),
          0x0020 | 0x0004 | 0x0200,
        );
        _fullscreenHwnd = 0;
        _savedWindowStyle = 0;
        _savedWindowRect = null;
      }
    } catch (e) {
      AppLog.add('winInput.fullscreen', e);
    }
  }

  static List<Rect> monitors() {
    if (!_ensureBound()) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cache.isNotEmpty && now - _cacheAt < 3000) return _cache;
    _mons.clear();
    final cb = Pointer.fromFunction<_MonitorEnumProcNative>(_enumCb, 0);
    _enumDisplayMonitors(0, nullptr, cb, 0);

    final sorted = List<Rect>.of(_mons)
      ..sort((a, b) {
        final aPrimary = (a.left == 0 && a.top == 0) ? 0 : 1;
        final bPrimary = (b.left == 0 && b.top == 0) ? 0 : 1;
        if (aPrimary != bPrimary) return aPrimary.compareTo(bPrimary);
        final cmpX = a.left.compareTo(b.left);
        return cmpX != 0 ? cmpX : a.top.compareTo(b.top);
      });

    _cache = sorted;
    _cacheAt = now;
    return _cache;
  }

  static void _mouseEvent(int flags, {int dx = 0, int dy = 0, int data = 0}) {
    if (!_ensureBound()) return;
    final p = calloc<_Input>();
    p.ref.type = 0;
    p.ref.u.mi.dx = dx;
    p.ref.u.mi.dy = dy;
    p.ref.u.mi.mouseData = data & 0xFFFFFFFF;
    p.ref.u.mi.dwFlags = flags;
    p.ref.u.mi.time = 0;
    p.ref.u.mi.dwExtraInfo = 0;
    _sendInput(1, p, sizeOf<_Input>());
    calloc.free(p);
  }

  static void _keyEvent(int vk, int scan, int flags) {
    if (!_ensureBound()) return;
    final p = calloc<_Input>();
    p.ref.type = 1;
    p.ref.u.ki.wVk = vk;
    p.ref.u.ki.wScan = scan;
    p.ref.u.ki.dwFlags = flags;
    p.ref.u.ki.time = 0;
    p.ref.u.ki.dwExtraInfo = 0;
    _sendInput(1, p, sizeOf<_Input>());
    calloc.free(p);
  }

  static void mouse(double nx, double ny, String a, int btn, int screen) {
    if (!_ensureBound()) return;
    final mons = monitors();
    if (mons.isEmpty) return;
    final r = mons[screen.clamp(0, mons.length - 1)];
    final px = r.left + nx * (r.width - 1);
    final py = r.top + ny * (r.height - 1);
    final vx = _getSystemMetrics(76);
    final vy = _getSystemMetrics(77);
    final vw = _getSystemMetrics(78);
    final vh = _getSystemMetrics(79);
    if (vw <= 0 || vh <= 0) return;

    final ax = (((px - vx) * 65535 / vw).round()).clamp(0, 65535);
    final ay = (((py - vy) * 65535 / vh).round()).clamp(0, 65535);
    _mouseEvent(0x0001 | 0x8000 | 0x4000, dx: ax, dy: ay);
    if (a == 'down') {
      _mouseEvent(btn == 2 ? 0x0008 : (btn == 1 ? 0x0020 : 0x0002));
    } else if (a == 'up') {
      _mouseEvent(btn == 2 ? 0x0010 : (btn == 1 ? 0x0040 : 0x0004));
    }
  }

  static void wheel(double dy) {
    _mouseEvent(0x0800, data: (-dy).round());
  }

  static void text(String s) {
    for (final u in s.codeUnits) {
      _keyEvent(0, u, 0x0004);
      _keyEvent(0, u, 0x0004 | 0x0002);
    }
  }

  static void vk(int code) {
    _keyEvent(code, 0, 0);
    _keyEvent(code, 0, 0x0002);
  }
}
