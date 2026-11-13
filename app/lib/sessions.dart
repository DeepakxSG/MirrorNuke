import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';
import 'android_control.dart';
import 'security.dart';
import 'win_audio.dart';
import 'win_input.dart';

class RoomDevice {
  final String name;
  final String platform;
  final List<String> caps;
  final bool sharing;

  RoomDevice({
    required this.name,
    required this.platform,
    required this.caps,
    required this.sharing,
  });

  factory RoomDevice.fromJson(Map<String, dynamic> j) => RoomDevice(
        name: '${j['name'] ?? ''}',
        platform: '${j['platform'] ?? 'unknown'}',
        caps: (j['caps'] is List) ? List<String>.from((j['caps'] as List).map((e) => '$e')) : const [],
        sharing: j['sharing'] == true,
      );
}

class DeviceDirectory extends ChangeNotifier {
  String _url = '', _room = '', _me = '', _token = '';
  bool _sharing = false;
  Signaling? _sig;
  List<RoomDevice> devices = [];
  String status = 'Idle';
  String? error;

  void configure({
    required String url,
    required String room,
    required String me,
    required String token,
    required bool sharing,
  }) {
    final changed = _url != url || _room != room || _me != me || _token != token;
    _url = url;
    _room = room;
    _me = me;
    _token = token;
    _sharing = sharing;
    if (!validUrl(url) || !validRoom(room) || !validName(me)) {
      status = 'Configure valid server, room & device name in Settings';
      notifyListeners();
      return;
    }
    if (changed || _sig == null) {
      reconnect();
    } else {
      _sig?.send({
        'type': 'presence',
        'caps': _localCaps(),
        'sharing': _sharing,
      });
    }
  }

  List<String> _localCaps() => [
        'screen',
        'audio',
        'control',
        if (Platform.isWindows) 'multidisplay',
      ];

  void reconnect() {
    _sig?.close();
    devices = [];
    error = null;
    if (!validUrl(_url) || !validRoom(_room) || !validName(_me)) return;
    status = 'Connecting to room directory...';
    notifyListeners();

    final s = Signaling(
      _url,
      _room,
      _token,
      deviceName: _me,
      platform: Platform.isWindows ? 'windows' : 'android',
      caps: _localCaps(),
      sharing: _sharing,
    );
    s.onStatus = (st) {
      status = st;
      if (st.contains('duplicate_name')) {
        error = 'Device name "$_me" is already taken in room "$_room". Change it in Settings.';
      }
      notifyListeners();
    };
    s.onConnected = () {
      status = 'Connected to room "$_room"';
      error = null;
      notifyListeners();
    };
    s.onMessage = (m) {
      if (m['type'] == 'directory' && m['devices'] is List) {
        devices = (m['devices'] as List)
            .whereType<Map<String, dynamic>>()
            .map(RoomDevice.fromJson)
            .where((d) => d.name.isNotEmpty && d.name != _me)
            .toList();
        notifyListeners();
      }
    };
    _sig = s;
    s.connect();
  }

  @override
  void dispose() {
    _sig?.close();
    super.dispose();
  }
}

class StreamMetrics {
  String rttMs = '—';
  String resolution = '—';
  String fps = '—';
  String bitrateKbps = '—';
  String packetLoss = '—';
  String qualityLabel = 'Waiting';
}

class Signaling {
  final String url, room, token;
  final String? deviceName, platform;
  final List<String> caps;
  final bool sharing;

  Signaling(
    this.url,
    this.room,
    this.token, {
    this.deviceName,
    this.platform,
    this.caps = const [],
    this.sharing = false,
  });

  IOWebSocketChannel? _ws;
  bool _closed = false, _retrying = false;
  int _attempt = 0;
  void Function(Map<String, dynamic>)? onMessage;
  void Function(String)? onStatus;
  void Function()? onConnected;

  Future<void> connect() async {
    _closed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_closed) return;
    try {
      final ws = IOWebSocketChannel.connect(
        Uri.parse(url),
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 8),
      );
      await ws.ready;
      if (_closed) {
        ws.sink.close();
        return;
      }
      _ws = ws;
      _attempt = 0;
      _retrying = false;
      ws.stream.listen(
        (raw) {
          try {
            if (raw is! String || raw.length > 70000) return;
            final m = jsonDecode(raw);
            if (m is! Map<String, dynamic>) return;
            if (m['type'] == 'error') {
              onStatus?.call('Server refused: ${m['reason']}');
              if (m['reason'] == 'denied' || m['reason'] == 'bad_room' || m['reason'] == 'duplicate_name') {
                close();
              }
              return;
            }
            onMessage?.call(m);
          } catch (e) {
            AppLog.add('signaling.parse', e);
          }
        },
        onError: (_) => _lost(),
        onDone: _lost,
        cancelOnError: true,
      );
      final joinMsg = <String, dynamic>{
        'type': 'join',
        'room': room,
        'token': token,
      };
      if (deviceName != null) {
        joinMsg['name'] = deviceName;
        joinMsg['platform'] = platform ?? 'unknown';
        joinMsg['caps'] = caps;
        joinMsg['sharing'] = sharing;
      }
      send(joinMsg);
      onConnected?.call();
    } catch (e) {
      AppLog.add('signaling.connect', e);
      onStatus?.call('Cannot reach signaling server. Retrying...');
      _lost();
    }
  }

  void _lost() {
    if (_closed || _retrying) return;
    _retrying = true;
    _ws = null;
    _attempt++;
    Timer(Duration(seconds: min(30, 1 << min(_attempt, 5))), () {
      _retrying = false;
      _open();
    });
  }

  void send(Map<String, dynamic> m) {
    try {
      _ws?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  void close() {
    _closed = true;
    try {
      _ws?.sink.close();
    } catch (_) {}
  }
}

const _rtcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
  'sdpSemantics': 'unified-plan',
};

RTCDataChannelInit _controlInit() => RTCDataChannelInit()
  ..negotiated = true
  ..id = 1
  ..ordered = true;

RTCDataChannelInit _audioChannelInit() => RTCDataChannelInit()
  ..negotiated = true
  ..id = 2
  ..ordered = false
  ..maxRetransmits = 0;

class ShareSession extends ChangeNotifier {
  final String url, room, name, token, password, quality;
  final bool shareAudio;

  ShareSession({
    required this.url,
    required this.room,
    required this.name,
    required this.token,
    required this.password,
    this.shareAudio = true,
    this.quality = 'movie',
  });

  String get roomKey => '$room:$name';
  String status = 'Starting...';
  bool audioActive = false;
  int selected = 0;
  List<String> get displayNames => List.unmodifiable(_names);
  final StreamMetrics metrics = StreamMetrics();

  bool _disposed = false;
  late final Signaling _sig = Signaling(url, roomKey, token, deviceName: name);
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  RTCDataChannel? _audioDc;
  final List<MediaStream> _streams = [];
  final List<String> _names = [];
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescSet = false;
  StreamSubscription<Uint8List>? _androidAudioSub;
  Timer? _statsTimer;
  int _prevBytesSent = 0, _prevStatsTs = 0;

  bool _authed = false;
  String _nonce = '';
  String _senderFp = '', _viewerFp = '';
  String? _viewerName;
  int _fails = 0;
  DateTime? _lockUntil;
  int _lastReadyAt = 0;

  int _winStart = 0, _winCount = 0;
  final List<List<double>> _path = [];
  int _downAt = 0;

  void _set(String s) {
    status = s;
    if (!_disposed) notifyListeners();
  }

  double get _targetFps => quality == 'gaming' ? 60.0 : (quality == 'saver' ? 20.0 : 30.0);
  int get _maxBitrateBps => quality == 'gaming' ? 10000000 : (quality == 'saver' ? 1500000 : 5000000);

  Future<void> start() async {
    final err = validPassword(password) ??
        (validUrl(url) ? null : 'Invalid server address (use ws://IP:8080)') ??
        (validRoom(room) && validName(name) ? null : 'Room and device names: letters, numbers, - and _ only');
    if (err != null) {
      _set(err);
      return;
    }
    try {
      await _capture();
    } catch (e) {
      AppLog.add('share.capture', e);
      _set('Screen capture failed: $e');
      return;
    }
    _sig.onMessage = _onMsg;
    _sig.onStatus = _set;
    _sig.onConnected = () {
      _set(audioActive
          ? 'Sharing screen + audio. Waiting for viewer...'
          : 'Sharing screen. Waiting for viewer...');
      _sig.send({'type': 'hello', 'from': name});
    };
    await _sig.connect();
  }

  Future<void> _capture() async {
    if (WebRTC.platformIsDesktop) {
      final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
      for (var idx = 0; idx < sources.length; idx++) {
        final s = sources[idx];
        final videoConstraints = {
          'deviceId': {'exact': s.id},
          'mandatory': {'frameRate': _targetFps},
        };
        MediaStream st;
        if (shareAudio && idx == 0) {
          try {
            st = await navigator.mediaDevices.getDisplayMedia({
              'video': videoConstraints,
              'audio': true,
            });
            audioActive = st.getAudioTracks().isNotEmpty;
          } catch (_) {
            st = await navigator.mediaDevices.getDisplayMedia({
              'video': videoConstraints,
              'audio': false,
            });
          }
        } else {
          st = await navigator.mediaDevices.getDisplayMedia({
            'video': videoConstraints,
            'audio': false,
          });
        }
        _streams.add(st);
        _names.add(s.name);
      }
    } else {
      final ok = await Helper.requestCapturePermission();
      if (!ok) throw 'permission denied';
      await AndroidControl.startCaptureService();
      await Future.delayed(const Duration(milliseconds: 300));
      final st = await navigator.mediaDevices.getDisplayMedia({'video': true});
      _streams.add(st);
      _names.add('Phone Screen');

      if (shareAudio) {
        final audioOk = await AndroidControl.startAudioCapture();
        if (audioOk) {
          audioActive = true;
          _androidAudioSub = AndroidControl.encodedAudioStream.listen((packet) {
            if (_authed && _audioDc?.state == RTCDataChannelState.RTCDataChannelOpen) {
              try {
                _audioDc!.send(RTCDataChannelMessage.fromBinary(packet));
              } catch (_) {}
            }
          });
        }
      }
    }
    _applySelection();
  }

  void selectLocalDisplay(int i) {
    if (_streams.isEmpty) return;
    selected = i.clamp(0, _streams.length - 1);
    _applySelection();
    if (_authed) _sendInfo();
    if (!_disposed) notifyListeners();
  }

  void _applySelection() {
    for (var i = 0; i < _streams.length; i++) {
      for (final t in _streams[i].getVideoTracks()) {
        t.enabled = _authed && i == selected;
      }
      for (final a in _streams[i].getAudioTracks()) {
        a.enabled = _authed && shareAudio;
      }
    }
  }

  Future<void> _applyEncoderTuning() async {
    if (_pc == null) return;
    try {
      final senders = await _pc!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final params = sender.parameters;
          params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
          final encs = params.encodings;
          if (encs != null && encs.isNotEmpty) {
            for (final enc in encs) {
              enc.maxBitrate = _maxBitrateBps;
              enc.maxFramerate = _targetFps.round();
            }
          }
          await sender.setParameters(params);
        }
      }
    } catch (e) {
      AppLog.add('share.setParameters', e);
    }
  }

  String _stateLabel(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return _authed
            ? (audioActive ? 'Viewer connected (Video + Audio)' : 'Viewer connected')
            : 'Viewer connecting, verifying password...';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Connection failed. Waiting for viewer...';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Viewer disconnected';
      default:
        return 'Connecting...';
    }
  }

  Future<void> _newPc() async {
    _statsTimer?.cancel();
    await _pc?.close();
    _authed = false;
    _remoteDescSet = false;
    _pendingIce.clear();
    _nonce = '';
    _senderFp = '';
    _viewerFp = '';
    _applySelection();

    _pc = await createPeerConnection(_rtcConfig);
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _sig.send({
          'type': 'candidate',
          'from': name,
          if (_viewerName != null) 'to': _viewerName,
          'candidate': c.toMap(),
        });
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _authed = false;
        _applySelection();
      }
      _set(_stateLabel(s));
    };

    for (final st in _streams) {
      for (final t in st.getTracks()) {
        await _pc!.addTrack(t, st);
      }
    }
    await _applyEncoderTuning();

    _dc = await _pc!.createDataChannel('control', _controlInit());
    _dc!.onMessage = (m) => _onControl(m.text);
    _dc!.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _nonce = randomNonce();
        _dcSend({'t': 'challenge', 'n': _nonce});
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        _authed = false;
        _applySelection();
      }
    };

    _audioDc = await _pc!.createDataChannel('audio', _audioChannelInit());
    _startStatsLoop();
  }

  void _startStatsLoop() {
    _prevBytesSent = 0;
    _prevStatsTs = DateTime.now().millisecondsSinceEpoch;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_pc == null || _disposed || !_authed) return;
      try {
        final stats = await _pc!.getStats();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final report in stats) {
          final v = report.values;
          if (report.type == 'outbound-rtp' && v['kind'] == 'video') {
            final w = v['frameWidth'];
            final h = v['frameHeight'];
            if (w != null && h != null) metrics.resolution = '${w}x$h';
            final fps = v['framesPerSecond'];
            if (fps is num) metrics.fps = '${fps.round()} fps';
            final bytes = v['bytesSent'];
            if (bytes is num && _prevBytesSent > 0 && now > _prevStatsTs) {
              final kbps = ((bytes - _prevBytesSent) * 8) / (now - _prevStatsTs);
              metrics.bitrateKbps = '${kbps.round()} kbps';
            }
            if (bytes is num) _prevBytesSent = bytes.toInt();
            _prevStatsTs = now;
          } else if (report.type == 'candidate-pair' && v['state'] == 'succeeded') {
            final rtt = v['currentRoundTripTime'];
            if (rtt is num) metrics.rttMs = '${(rtt * 1000).round()} ms';
          }
        }
        if (!_disposed) notifyListeners();
      } catch (_) {}
    });
  }

  void _dcSend(Map<String, dynamic> m) {
    try {
      _dc?.send(RTCDataChannelMessage(jsonEncode(m)));
    } catch (_) {}
  }

  void _sendInfo() => _dcSend({
        't': 'info',
        'os': Platform.isWindows ? 'windows' : 'android',
        'ids': _streams.map((s) => s.id).toList(),
        'names': _names,
        'sel': selected,
        'audio': audioActive,
      });

  Future<void> _flushPendingIce() async {
    if (_pc == null || !_remoteDescSet) return;
    final copy = List<RTCIceCandidate>.of(_pendingIce);
    _pendingIce.clear();
    for (final c in copy) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _onMsg(Map<String, dynamic> m) async {
    try {
      switch (m['type']) {
        case 'ready':
          if (_streams.isEmpty) return;
          if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) return;
          // Do not allow an unauthenticated peer to disrupt an active authenticated viewer
          if (_authed) return;
          final readyAt = DateTime.now().millisecondsSinceEpoch;
          if (readyAt - _lastReadyAt < 1500) return;
          _lastReadyAt = readyAt;
          final from = m['from'];
          _viewerName = (from is String && validName(from)) ? from : null;

          await _newPc();
          final offer = await _pc!.createOffer();
          _senderFp = fingerprintOf(offer.sdp);
          await _pc!.setLocalDescription(offer);
          _sig.send({
            'type': 'offer',
            'from': name,
            if (_viewerName != null) 'to': _viewerName,
            'sdp': offer.sdp,
          });
          break;
        case 'answer':
          final sdp = m['sdp'];
          if (sdp is! String || sdp.length > 60000 || _pc == null) return;
          _viewerFp = fingerprintOf(sdp);
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          _remoteDescSet = true;
          await _flushPendingIce();
          break;
        case 'candidate':
          final c = m['candidate'];
          if (c is! Map || c['candidate'] is! String) return;
          final cand = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
          if (_pc == null || !_remoteDescSet) {
            if (_pendingIce.length < 64) _pendingIce.add(cand);
          } else {
            await _pc!.addCandidate(cand);
          }
          break;
      }
    } catch (e) {
      AppLog.add('share.signal', e);
    }
  }

  void _auth(Map<String, dynamic> m) {
    if (_authed || _nonce.isEmpty) return;
    final now = DateTime.now();
    if (_lockUntil != null && now.isBefore(_lockUntil!)) {
      _dcSend({'t': 'auth_fail', 'left': 0});
      return;
    }
    final p = m['p'];
    final expected = proof(password, 'V', _nonce, roomKey, _senderFp, _viewerFp);
    if (p is String && constEq(p, expected)) {
      _authed = true;
      _fails = 0;
      _dcSend({'t': 'auth_ok', 'sp': proof(password, 'S', _nonce, roomKey, _senderFp, _viewerFp)});
      _applySelection();
      _sendInfo();
      _set(audioActive ? 'Viewer connected (Video + Audio)' : 'Viewer connected');
    } else {
      _fails++;
      if (_fails >= 5) {
        _fails = 0;
        _lockUntil = now.add(const Duration(seconds: 60));
        _pc?.close();
        _pc = null;
        _set('Too many wrong passwords. Locked for 60 seconds.');
      } else {
        _dcSend({'t': 'auth_fail', 'left': 5 - _fails});
      }
    }
  }

  bool _allow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _winStart > 1000) {
      _winStart = now;
      _winCount = 0;
    }
    return ++_winCount <= 300;
  }

  void _onControl(String text) {
    if (text.length > 4096 || !_allow()) return;
    Map<String, dynamic> m;
    try {
      final d = jsonDecode(text);
      if (d is! Map<String, dynamic>) return;
      m = d;
    } catch (_) {
      return;
    }
    final t = m['t'];
    if (t == 'auth') {
      _auth(m);
      return;
    }
    if (!_authed) return;
    try {
      switch (t) {
        case 'screen':
          final i = m['i'];
          if (i is! int || _streams.isEmpty) return;
          selected = i.clamp(0, _streams.length - 1);
          _applySelection();
          notifyListeners();
          break;
        case 'mouse':
          _mouse(m);
          break;
        case 'wheel':
          final dy = m['dy'];
          if (dy is num && dy.isFinite) _wheel(dy.toDouble().clamp(-2000.0, 2000.0));
          break;
        case 'text':
          final s = m['s'];
          if (s is! String) return;
          final clean = cleanText(s);
          if (clean.isEmpty) return;
          Platform.isWindows ? WinInput.text(clean) : AndroidControl.text(clean);
          break;
        case 'clipboard':
          final s = m['s'];
          if (s is String && s.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: s.length > 2000 ? s.substring(0, 2000) : s));
          }
          break;
        case 'key':
          final k = m['k'];
          if (Platform.isWindows) {
            if (k == 'enter') WinInput.vk(0x0D);
            if (k == 'backspace') WinInput.vk(0x08);
          } else if (k == 'backspace') {
            AndroidControl.backspace();
          }
          break;
        case 'nav':
          final a = m['a'];
          if (Platform.isAndroid && (a == 'back' || a == 'home' || a == 'recents')) {
            AndroidControl.global(a as String);
          }
          break;
      }
    } catch (e) {
      AppLog.add('share.control', e);
    }
  }

  void _mouse(Map<String, dynamic> m) {
    final a = m['a'];
    final x = unit(m['x']), y = unit(m['y']);
    final bRaw = m['b'];
    final b = bRaw is int && bRaw >= 0 && bRaw <= 2 ? bRaw : 0;
    if (x == null || y == null || (a != 'down' && a != 'move' && a != 'up')) return;
    if (Platform.isWindows) {
      WinInput.mouse(x, y, a as String, b, selected);
      return;
    }
    if (b == 2 && a == 'down') {
      AndroidControl.global('back');
      return;
    }
    if (b == 1 && a == 'down') {
      AndroidControl.global('home');
      return;
    }
    if (b != 0) return;
    if (a == 'down') {
      _path
        ..clear()
        ..add([x, y]);
      _downAt = DateTime.now().millisecondsSinceEpoch;
    } else if (a == 'move') {
      if (_path.isNotEmpty && _path.length < 2000) _path.add([x, y]);
    } else if (a == 'up') {
      if (_path.isEmpty) return;
      _path.add([x, y]);
      final dur = (DateTime.now().millisecondsSinceEpoch - _downAt).clamp(50, 5000);
      final s = _path.first, e = _path.last;
      final moved = sqrt(pow(e[0] - s[0], 2) + pow(e[1] - s[1], 2)) > 0.02;
      if (!moved) {
        AndroidControl.gesture([s[0], s[1]], dur);
      } else {
        final step = max(1, _path.length ~/ 30);
        final pts = <double>[];
        for (var i = 0; i < _path.length; i += step) {
          pts..add(_path[i][0])..add(_path[i][1]);
        }
        pts..add(e[0])..add(e[1]);
        AndroidControl.gesture(pts, dur);
      }
      _path.clear();
    }
  }

  void _wheel(double dy) {
    if (Platform.isWindows) {
      WinInput.wheel(dy);
    } else {
      final up = dy > 0;
      AndroidControl.gesture(up ? [0.5, 0.65, 0.5, 0.35] : [0.5, 0.35, 0.5, 0.65], 150);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    _androidAudioSub?.cancel();
    for (final s in _streams) {
      s.getTracks().forEach((t) => t.stop());
      s.dispose();
    }
    _pc?.close();
    _sig.close();
    if (Platform.isAndroid) {
      AndroidControl.stopAudioCapture();
      AndroidControl.stopCaptureService();
    }
    super.dispose();
  }
}

class ViewSession extends ChangeNotifier {
  final String url, room, me, target, token, password;
  final bool playAudio;

  ViewSession({
    required this.url,
    required this.room,
    required this.me,
    required this.target,
    required this.token,
    required this.password,
    this.playAudio = true,
  });

  String get roomKey => '$room:$target';
  final renderer = RTCVideoRenderer();
  final StreamMetrics metrics = StreamMetrics();
  String status = 'Starting...';
  String os = '';
  List<String> ids = [], names = [];
  int selected = 0;
  bool authed = false;
  bool remoteAudioEnabled = false;
  bool audioMuted = false;

  bool _disposed = false, _retryScheduled = false, _remoteDescSet = false;
  late final Signaling _sig = Signaling(url, roomKey, token, deviceName: me);
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  RTCDataChannel? _audioDc;
  final Map<String, MediaStream> _byId = {};
  final List<String> _order = [];
  final List<RTCIceCandidate> _pendingIce = [];
  String _nonce = '', _senderFp = '', _viewerFp = '';

  final WinSpeakerPlayer _winSpeaker = WinSpeakerPlayer();
  final AudioJitterBuffer _jitterBuffer = AudioJitterBuffer(targetFrames: 2, maxFrames: 5);
  Timer? _statsTimer;
  int _prevBytesRecv = 0, _prevStatsTs = 0;

  bool get hasVideo => authed && renderer.srcObject != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(String s) {
    status = s;
    _notify();
  }

  void toggleMute() {
    audioMuted = !audioMuted;
    _winSpeaker.setMuted(audioMuted);
    if (audioMuted) _jitterBuffer.reset();
    final st = renderer.srcObject;
    if (st != null) {
      for (final a in st.getAudioTracks()) {
        a.enabled = !audioMuted;
      }
    }
    _notify();
  }

  Future<void> start() async {
    final err = validPassword(password) ??
        (validUrl(url) ? null : 'Invalid server address (use ws://IP:8080)') ??
        (validRoom(room) && validName(target) ? null : 'Room and device names: letters, numbers, - and _ only');
    if (err != null) {
      _set(err);
      return;
    }
    if (Platform.isWindows && playAudio) {
      _winSpeaker.open();
    }
    await renderer.initialize();
    renderer.onResize = () => _notify();
    _sig.onMessage = _onMsg;
    _sig.onStatus = _set;
    _sig.onConnected = () {
      _set('Waiting for "$target" to share...');
      _sig.send({'type': 'ready', 'from': me, 'to': target});
    };
    await _sig.connect();
  }

  Future<void> _newPc() async {
    _statsTimer?.cancel();
    await _pc?.close();
    authed = false;
    _remoteDescSet = false;
    _pendingIce.clear();
    _jitterBuffer.reset();
    _nonce = '';
    _senderFp = '';
    _viewerFp = '';
    _byId.clear();
    _order.clear();
    renderer.srcObject = null;

    _pc = await createPeerConnection(_rtcConfig);
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _sig.send({
          'type': 'candidate',
          'from': me,
          'to': target,
          'candidate': c.toMap(),
        });
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!authed) _set('Connected, checking password...');
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        authed = false;
        _jitterBuffer.reset();
        _set('Connection lost. Reconnecting...');
        _scheduleReady();
      }
    };
    _pc!.onTrack = (e) {
      if (e.streams.isEmpty) return;
      final s = e.streams[0];
      if (!_byId.containsKey(s.id)) _order.add(s.id);
      _byId[s.id] = s;
      if (s.getAudioTracks().isNotEmpty) {
        remoteAudioEnabled = true;
      }
      _show();
    };

    _dc = await _pc!.createDataChannel('control', _controlInit());
    _dc!.onMessage = (m) => _onChannel(m.text);

    _audioDc = await _pc!.createDataChannel('audio', _audioChannelInit());
    _audioDc!.onMessage = (m) {
      if (!authed || !playAudio || audioMuted || !m.isBinary) return;
      final decoded = ImaAdpcmDecoder.decodePacket(m.binary);
      if (decoded == null) return;
      final frames = _jitterBuffer.push(decoded.seq, decoded.pcm);
      if (frames.isEmpty) return;
      remoteAudioEnabled = true;
      for (final pcm in frames) {
        if (Platform.isWindows) {
          _winSpeaker.playPcm(pcm);
        } else if (Platform.isAndroid) {
          AndroidControl.playAudioPcm(pcm);
        }
      }
    };

    _startStatsLoop();
  }

  void _startStatsLoop() {
    _prevBytesRecv = 0;
    _prevStatsTs = DateTime.now().millisecondsSinceEpoch;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_pc == null || _disposed || !authed) return;
      try {
        final stats = await _pc!.getStats();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final report in stats) {
          final v = report.values;
          if (report.type == 'inbound-rtp' && v['kind'] == 'video') {
            final w = v['frameWidth'];
            final h = v['frameHeight'];
            if (w != null && h != null) metrics.resolution = '${w}x$h';
            final fps = v['framesPerSecond'];
            if (fps is num) metrics.fps = '${fps.round()} fps';
            final bytes = v['bytesReceived'];
            if (bytes is num && _prevBytesRecv > 0 && now > _prevStatsTs) {
              final kbps = ((bytes - _prevBytesRecv) * 8) / (now - _prevStatsTs);
              metrics.bitrateKbps = '${kbps.round()} kbps';
            }
            if (bytes is num) _prevBytesRecv = bytes.toInt();
            _prevStatsTs = now;

            final lost = v['packetsLost'];
            final recv = v['packetsReceived'];
            if (lost is num && recv is num && (lost + recv) > 0) {
              final pct = (lost.clamp(0, 1000000) / (lost + recv)) * 100;
              metrics.packetLoss = '${pct.toStringAsFixed(1)}%';
            }
          } else if (report.type == 'candidate-pair' && v['state'] == 'succeeded') {
            final rtt = v['currentRoundTripTime'];
            if (rtt is num) {
              final ms = (rtt * 1000).round();
              metrics.rttMs = '$ms ms';
              metrics.qualityLabel = ms < 25 ? 'Excellent' : (ms < 70 ? 'Good' : 'Fair');
            }
          }
        }
        _notify();
      } catch (_) {}
    });
  }

  void _scheduleReady() {
    if (_retryScheduled || _disposed) return;
    _retryScheduled = true;
    Future.delayed(const Duration(seconds: 3), () {
      _retryScheduled = false;
      if (!_disposed && !authed) _sig.send({'type': 'ready', 'from': me, 'to': target});
    });
  }

  void _onChannel(String text) {
    if (text.length > 8192) return;
    try {
      final d = jsonDecode(text);
      if (d is! Map<String, dynamic>) return;
      switch (d['t']) {
        case 'challenge':
          final n = d['n'];
          if (n is! String || n.isEmpty || n.length > 64) return;
          _nonce = n;
          _rawSend({'t': 'auth', 'p': proof(password, 'V', n, roomKey, _senderFp, _viewerFp)});
          break;
        case 'auth_ok':
          final sp = d['sp'];
          final expected = proof(password, 'S', _nonce, roomKey, _senderFp, _viewerFp);
          if (sp is String && constEq(sp, expected)) {
            authed = true;
            _set('Connected');
            _show();
          } else {
            authed = false;
            _set('Could not verify the other device. Connection closed.');
            _pc?.close();
          }
          break;
        case 'auth_fail':
          authed = false;
          _set('Wrong password. Check the pairing password in Settings.');
          break;
        case 'info':
          if (!authed) return;
          final rawIds = d['ids'];
          final rawNames = d['names'];
          if (rawIds is! List) return;
          os = d['os'] == 'windows' ? 'windows' : 'android';
          ids = rawIds.take(8).map((e) => '$e').toList();
          names = rawNames is List ? rawNames.take(8).map((e) => '$e').toList() : <String>[];
          final sel = d['sel'];
          selected = (sel is num ? sel.toInt() : 0).clamp(0, max(0, ids.length - 1));
          if (d['audio'] == true) remoteAudioEnabled = true;
          _show();
          break;
      }
    } catch (e) {
      AppLog.add('view.channel', e);
    }
  }

  void _show() {
    if (!authed) {
      _notify();
      return;
    }
    MediaStream? s;
    if (selected < ids.length) s = _byId[ids[selected]];
    s ??= selected < _order.length ? _byId[_order[selected]] : null;
    s ??= _byId.values.isNotEmpty ? _byId.values.first : null;
    if (s != null) {
      renderer.srcObject = s;
      for (final a in s.getAudioTracks()) {
        a.enabled = playAudio && !audioMuted;
      }
    }
    _notify();
  }

  void selectScreen(int i) {
    selected = i;
    sendControl({'t': 'screen', 'i': i});
    _show();
  }

  void _rawSend(Map<String, dynamic> m) {
    try {
      _dc?.send(RTCDataChannelMessage(jsonEncode(m)));
    } catch (_) {}
  }

  void sendControl(Map<String, dynamic> m) {
    if (authed && _dc?.state == RTCDataChannelState.RTCDataChannelOpen) _rawSend(m);
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null || !_remoteDescSet) return;
    final copy = List<RTCIceCandidate>.of(_pendingIce);
    _pendingIce.clear();
    for (final c in copy) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _onMsg(Map<String, dynamic> m) async {
    try {
      switch (m['type']) {
        case 'hello':
          _sig.send({'type': 'ready', 'from': me, 'to': target});
          break;
        case 'offer':
          final sdp = m['sdp'];
          if (sdp is! String || sdp.length > 60000) return;
          await _newPc();
          _senderFp = fingerprintOf(sdp);
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
          _remoteDescSet = true;
          final answer = await _pc!.createAnswer();
          _viewerFp = fingerprintOf(answer.sdp);
          await _pc!.setLocalDescription(answer);
          _sig.send({
            'type': 'answer',
            'from': me,
            'to': target,
            'sdp': answer.sdp,
          });
          await _flushPendingIce();
          break;
        case 'candidate':
          final c = m['candidate'];
          if (c is! Map || c['candidate'] is! String) return;
          final cand = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
          if (_pc == null || !_remoteDescSet) {
            if (_pendingIce.length < 64) _pendingIce.add(cand);
          } else {
            await _pc!.addCandidate(cand);
          }
          break;
      }
    } catch (e) {
      AppLog.add('view.signal', e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    _winSpeaker.close();
    if (Platform.isAndroid) AndroidControl.stopAudioPlayback();
    _pc?.close();
    _sig.close();
    renderer.dispose();
    super.dispose();
  }
}
