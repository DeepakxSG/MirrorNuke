import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'security.dart';

class _LocalPeer {
  final WebSocket socket;
  final String ip;
  String? room;
  String? deviceName;
  String platform = 'unknown';
  List<String> caps = const [];
  bool sharing = false;
  int msgCount = 0;
  int windowStartMs = 0;
  Timer? joinTimer;

  _LocalPeer(this.socket, this.ip);
}

/// Built-in Dart signaling and room-scoped directory server.
/// Speaks the exact same wire protocol as `server/server.js`, eliminating the need
/// to install Node.js or open a terminal for LAN casting.
class EmbeddedSignalingServer extends ChangeNotifier {
  static const int defaultPort = 8080;
  static const int _maxPeersPerRoom = 12;
  static const int _maxConnPerIp = 30;
  static const int _maxRooms = 200;
  static const int _msgLimitPerSec = 120;
  static const Set<String> _allowedCaps = {'screen', 'audio', 'control', 'multidisplay', 'tv'};
  static const Set<String> _relayTypes = {'hello', 'ready', 'offer', 'answer', 'candidate'};

  HttpServer? _http;
  final Map<String, Set<_LocalPeer>> _rooms = {};
  final Map<String, int> _perIp = {};

  bool running = false;
  int port = defaultPort;
  List<String> lanUrls = const [];
  String status = 'Stopped';

  String get localClientUrl => 'ws://127.0.0.1:$port';
  String get primaryLanUrl => lanUrls.isNotEmpty ? lanUrls.first : 'ws://127.0.0.1:$port';

  Future<void> start({int bindPort = defaultPort, String serverToken = ''}) async {
    if (running) return;
    port = bindPort;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      running = true;
      lanUrls = await _detectLanUrls(port);
      status = 'Running on $primaryLanUrl';
      notifyListeners();

      _http!.listen((HttpRequest req) async {
        if (!WebSocketTransformer.isUpgradeRequest(req)) {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.text
            ..write('MirrorNuke Signaling Server')
            ..close();
          return;
        }
        final ip = req.connectionInfo?.remoteAddress.address ?? 'unknown';
        final count = (_perIp[ip] ?? 0) + 1;
        if (count > _maxConnPerIp) {
          req.response
            ..statusCode = HttpStatus.tooManyRequests
            ..close();
          return;
        }
        _perIp[ip] = count;

        try {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.pingInterval = const Duration(seconds: 20);
          _attachPeer(ws, ip, serverToken);
        } catch (e) {
          _decIp(ip);
          AppLog.add('embeddedServer.upgrade', e);
        }
      }, onError: (Object e) {
        AppLog.add('embeddedServer.listen', e);
      });
    } catch (e) {
      running = false;
      status = 'Port $port busy or blocked ($e)';
      AppLog.add('embeddedServer.start', e);
      notifyListeners();
    }
  }

  void _decIp(String ip) {
    final left = (_perIp[ip] ?? 1) - 1;
    if (left <= 0) {
      _perIp.remove(ip);
    } else {
      _perIp[ip] = left;
    }
  }

  void _reject(_LocalPeer peer, String reason) {
    try {
      peer.socket.add(jsonEncode({'type': 'error', 'reason': reason}));
    } catch (_) {}
    try {
      peer.socket.close(1008, reason);
    } catch (_) {}
  }

  List<String> _cleanCaps(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw.take(8)) {
      if (item is String && _allowedCaps.contains(item) && !out.contains(item)) {
        out.add(item);
      }
    }
    return out;
  }

  Map<String, dynamic>? _cleanRelay(Map<String, dynamic> m) {
    final type = m['type'];
    if (type is! String || !_relayTypes.contains(type)) return null;
    final out = <String, dynamic>{'type': type};

    if (m.containsKey('from') && m['from'] != null) {
      final from = m['from'];
      if (from is! String || !validName(from)) return null;
      out['from'] = from;
    }
    if (m.containsKey('to') && m['to'] != null) {
      final to = m['to'];
      if (to is! String || !validName(to)) return null;
      out['to'] = to;
    }

    if (type == 'offer' || type == 'answer') {
      final sdp = m['sdp'];
      if (sdp is! String || sdp.isEmpty || sdp.length > 55000) return null;
      out['sdp'] = sdp;
    } else if (type == 'candidate') {
      final c = m['candidate'];
      if (c is! Map || c['candidate'] is! String || (c['candidate'] as String).length > 1000) return null;
      final idx = c['sdpMLineIndex'];
      out['candidate'] = {
        'candidate': c['candidate'],
        'sdpMid': c['sdpMid'] is String ? (c['sdpMid'] as String).substring(0, (c['sdpMid'] as String).length.clamp(0, 64)) : null,
        'sdpMLineIndex': (idx is int && idx >= 0 && idx < 64) ? idx : 0,
      };
    }
    return out;
  }

  void _broadcastDirectory(String roomKey) {
    final peers = _rooms[roomKey];
    if (peers == null) return;
    final devices = <Map<String, dynamic>>[];
    for (final p in peers) {
      if (p.deviceName != null) {
        devices.add({
          'name': p.deviceName,
          'platform': p.platform,
          'caps': p.caps,
          'sharing': p.sharing,
        });
      }
    }
    final payload = jsonEncode({'type': 'directory', 'devices': devices});
    for (final p in peers) {
      if (p.deviceName != null && p.socket.readyState == WebSocket.open) {
        try {
          p.socket.add(payload);
        } catch (_) {}
      }
    }
  }

  void _attachPeer(WebSocket ws, String ip, String serverToken) {
    final peer = _LocalPeer(ws, ip);
    peer.joinTimer = Timer(const Duration(seconds: 10), () {
      if (peer.room == null) {
        try {
          ws.close(1008, 'join_timeout');
        } catch (_) {}
      }
    });

    ws.listen(
      (dynamic raw) {
        if (raw is! String || raw.length > 65536) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - peer.windowStartMs > 1000) {
          peer.windowStartMs = now;
          peer.msgCount = 0;
        }
        if (++peer.msgCount > _msgLimitPerSec) {
          try {
            ws.close(1008, 'rate_limited');
          } catch (_) {}
          return;
        }

        Map<String, dynamic> m;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) return;
          m = decoded;
        } catch (_) {
          return;
        }

        final type = m['type'];
        if (type == 'join') {
          if (peer.room != null) return;
          final room = m['room'];
          if (room is! String || !RegExp(r'^[A-Za-z0-9_:-]{1,80}$').hasMatch(room)) {
            _reject(peer, 'bad_room');
            return;
          }
          if (serverToken.isNotEmpty) {
            final tok = m['token'];
            if (tok is! String || !constEq(tok, serverToken)) {
              _reject(peer, 'denied');
              return;
            }
          }
          final set = _rooms.putIfAbsent(room, () => <_LocalPeer>{});
          if (_rooms.length > _maxRooms) {
            _rooms.remove(room);
            _reject(peer, 'server_busy');
            return;
          }
          if (set.length >= _maxPeersPerRoom) {
            _reject(peer, 'room_full');
            return;
          }

          final name = m['name'];
          if (name is String && validName(name)) {
            for (final existing in set) {
              if (existing.deviceName == name) {
                _reject(peer, 'duplicate_name');
                return;
              }
            }
            peer.deviceName = name;
            peer.platform = (m['platform'] == 'windows' || m['platform'] == 'android')
                ? m['platform'] as String
                : 'unknown';
            peer.caps = _cleanCaps(m['caps']);
            peer.sharing = m['sharing'] == true;
          }

          set.add(peer);
          peer.room = room;
          peer.joinTimer?.cancel();

          if (peer.deviceName != null) {
            _broadcastDirectory(room);
          }
          return;
        }

        final room = peer.room;
        if (room == null) return;

        if (type == 'presence') {
          if (peer.deviceName != null) {
            peer.caps = _cleanCaps(m['caps']);
            peer.sharing = m['sharing'] == true;
            _broadcastDirectory(room);
          }
          return;
        }

        final clean = _cleanRelay(m);
        if (clean == null) return;
        final to = clean['to'] as String?;
        final encoded = jsonEncode(clean);
        for (final target in _rooms[room] ?? const <_LocalPeer>{}) {
          if (target == peer || target.socket.readyState != WebSocket.open) continue;
          if (to != null && target.deviceName != to) continue;
          try {
            target.socket.add(encoded);
          } catch (_) {}
        }
      },
      onDone: () => _cleanupPeer(peer),
      onError: (_) => _cleanupPeer(peer),
      cancelOnError: true,
    );
  }

  void _cleanupPeer(_LocalPeer peer) {
    peer.joinTimer?.cancel();
    _decIp(peer.ip);
    final room = peer.room;
    if (room != null) {
      final hadName = peer.deviceName != null;
      final set = _rooms[room];
      if (set != null) {
        set.remove(peer);
        if (set.isEmpty) {
          _rooms.remove(room);
        } else if (hadName) {
          _broadcastDirectory(room);
        }
      }
      peer.room = null;
    }
  }

  static Future<List<String>> _detectLanUrls(int port) async {
    final urls = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      // Prioritize common private Wi-Fi subnets (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
      final allIps = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('169.254.')) {
            allIps.add(ip);
          }
        }
      }
      allIps.sort((a, b) {
        int score(String ip) => ip.startsWith('192.168.') ? 0 : (ip.startsWith('10.') ? 1 : 2);
        return score(a).compareTo(score(b));
      });
      for (final ip in allIps) {
        urls.add('ws://$ip:$port');
      }
    } catch (e) {
      AppLog.add('embeddedServer.detectIp', e);
    }
    return urls;
  }

  Future<void> stop() async {
    if (!running && _http == null) return;
    running = false;
    for (final set in _rooms.values) {
      for (final p in set) {
        p.joinTimer?.cancel();
        try {
          await p.socket.close(1001, 'server_stopped');
        } catch (_) {}
      }
    }
    _rooms.clear();
    _perIp.clear();
    try {
      await _http?.close(force: true);
    } catch (_) {}
    _http = null;
    status = 'Stopped';
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
