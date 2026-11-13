import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'android_control.dart';
import 'embedded_server.dart';
import 'lan_discovery.dart';
import 'security.dart';
import 'sessions.dart';
import 'settings.dart';
import 'startup.dart';
import 'win_input.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final auto = args.contains('--autostart');
  if (Platform.isWindows) {
    Startup.setup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WinInput.configureWindow(minimize: auto);
    });
  }
  final s = await Settings.load(
    defMe: Platform.isWindows ? 'pc' : 'phone',
    defOther: Platform.isWindows ? 'phone' : 'pc',
  );
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MirrorNuke',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF4F46E5),
      brightness: Brightness.dark,
    ),
    home: DashboardPage(settings: s, autostart: auto),
  ));
}

class DashboardPage extends StatefulWidget {
  final Settings settings;
  final bool autostart;
  const DashboardPage({super.key, required this.settings, required this.autostart});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;
  late final TextEditingController _server = TextEditingController(text: widget.settings.server);
  late final TextEditingController _token = TextEditingController(text: widget.settings.token);
  late final TextEditingController _room = TextEditingController(text: widget.settings.room);
  late final TextEditingController _me = TextEditingController(text: widget.settings.me);
  late final TextEditingController _other = TextEditingController(text: widget.settings.other);
  late final TextEditingController _pass = TextEditingController(text: widget.settings.password);

  late bool _share = widget.settings.share;
  late bool _view = widget.settings.view;
  late bool _shareAudio = widget.settings.shareAudio;
  late bool _playAudio = widget.settings.playAudio;
  late bool _hostLocal = widget.settings.hostLocalServer;
  late String _quality = widget.settings.quality;

  bool _acc = false, _startup = false, _hidePass = true, _scanningLan = false;
  List<DiscoveredLanDevice> _lanDevices = [];
  final DeviceDirectory _directory = DeviceDirectory();
  final EmbeddedSignalingServer _localServer = EmbeddedSignalingServer();

  String get _effectiveServerUrl =>
      (_hostLocal && _localServer.running) ? _localServer.localClientUrl : _server.text.trim();

  @override
  void initState() {
    super.initState();
    _checkAcc();
    Startup.isEnabled().then((v) {
      if (mounted) setState(() => _startup = v);
    });
    _syncLocalServer().then((_) {
      _refreshDirectory();
      if (widget.autostart && widget.settings.share && validPassword(widget.settings.password) == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _startSession(autostart: true));
      }
    });
  }

  Future<void> _syncLocalServer() async {
    if (_hostLocal) {
      await _localServer.start(serverToken: _token.text.trim());
    } else {
      await _localServer.stop();
    }
  }

  @override
  void dispose() {
    _directory.dispose();
    _localServer.dispose();
    _server.dispose();
    _token.dispose();
    _room.dispose();
    _me.dispose();
    _other.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _refreshDirectory() {
    _directory.configure(
      url: _effectiveServerUrl,
      room: _room.text.trim(),
      me: _me.text.trim(),
      token: _token.text.trim(),
      sharing: _share,
    );
  }

  Future<void> _checkAcc() async {
    final v = await AndroidControl.isEnabled();
    if (mounted) setState(() => _acc = v);
  }

  Future<void> _scanLan() async {
    if (_scanningLan) return;
    setState(() => _scanningLan = true);
    final found = await LanDiscovery.scan();
    if (mounted) {
      setState(() {
        _lanDevices = found;
        _scanningLan = false;
      });
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveSettings({bool notify = true}) async {
    final s = widget.settings
      ..server = _server.text.trim()
      ..token = _token.text.trim()
      ..room = _room.text.trim()
      ..me = _me.text.trim()
      ..other = _other.text.trim()
      ..password = _pass.text
      ..share = _share
      ..view = _view
      ..shareAudio = _shareAudio
      ..playAudio = _playAudio
      ..hostLocalServer = _hostLocal
      ..quality = _quality;
    await s.save();
    await _syncLocalServer();
    _refreshDirectory();
    if (notify && mounted) _snack('Settings saved');
  }

  Future<void> _startSession({bool autostart = false, String? overrideTarget}) async {
    if (overrideTarget != null) {
      _other.text = overrideTarget;
      _view = true;
    }
    await _syncLocalServer();
    final activeUrl = _effectiveServerUrl;
    final s = widget.settings
      ..server = _server.text.trim()
      ..token = _token.text.trim()
      ..room = _room.text.trim()
      ..me = _me.text.trim()
      ..other = _other.text.trim()
      ..password = _pass.text
      ..share = autostart ? true : _share
      ..view = autostart ? false : _view
      ..shareAudio = _shareAudio
      ..playAudio = _playAudio
      ..hostLocalServer = _hostLocal
      ..quality = _quality;

    final err = !validUrl(activeUrl)
        ? 'Server address must look like ws://192.168.1.10:8080'
        : !validRoom(s.room)
            ? 'Room code: 4-32 letters, numbers, - or _'
            : (!validName(s.me) || (s.view && !validName(s.other)))
                ? 'Device names: letters, numbers, - or _ only'
                : validPassword(s.password);
    if (err != null) {
      _snack(err);
      setState(() => _tab = 2);
      return;
    }
    if (!s.share && !s.view) {
      _snack('Enable Share or View first');
      return;
    }
    if (!autostart) await s.save();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LinkPage(s: s, activeServerUrl: activeUrl)));
    _refreshDirectory();
  }

  void _showDiagnostics() {
    final logs = AppLog.snapshot();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnostic Log'),
        content: SizedBox(
          width: 480,
          height: 300,
          child: logs.isEmpty
              ? const Center(child: Text('No warnings or errors logged in this session.'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (_, i) => Text(logs[logs.length - 1 - i], style: const TextStyle(fontSize: 12)),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppLog.clear();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cast_connected, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MirrorNuke Cast & Control', style: Theme.of(context).textTheme.titleLarge),
                          Text('Room: ${_room.text.trim()}  •  This device: ${_me.text.trim()}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _localServer,
                    builder: (_, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _localServer.running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                            size: 20,
                            color: _localServer.running ? Colors.lightGreenAccent : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _hostLocal
                                      ? (_localServer.running
                                          ? 'Built-in PC Server Ready: ${_localServer.primaryLanUrl}'
                                          : _localServer.status)
                                      : 'Using External Server: ${_server.text.trim()}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                if (_hostLocal && _localServer.running)
                                  const Text(
                                    'Enter this address & room code on your phone — no terminal needed',
                                    style: TextStyle(fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          if (_hostLocal && _localServer.running)
                            IconButton(
                              tooltip: 'Copy server URL for phone',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _localServer.primaryLanUrl));
                                _snack('Copied ${_localServer.primaryLanUrl}');
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share this device screen'),
                  subtitle: const Text('Allow paired devices in your room to view & control'),
                  value: _share,
                  onChanged: (v) {
                    setState(() => _share = v);
                    _saveSettings(notify: false);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stream device audio'),
                  subtitle: Text(Platform.isAndroid
                      ? 'Captures phone movie/game playback audio for PC speakers'
                      : 'Captures Windows desktop system audio'),
                  value: _shareAudio,
                  onChanged: (v) {
                    setState(() => _shareAudio = v);
                    _saveSettings(notify: false);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('View & control "${_other.text.trim()}"'),
                  subtitle: const Text('Watch remote screen and send mouse/touch/keyboard input'),
                  value: _view,
                  onChanged: (v) {
                    setState(() => _view = v);
                    _saveSettings(notify: false);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Platform.isWindows
                      ? 'Play remote audio on PC speakers'
                      : 'Play remote audio on device speakers'),
                  subtitle: const Text('Receives stereo movie & media audio in real time'),
                  value: _playAudio,
                  onChanged: (v) {
                    setState(() => _playAudio = v);
                    _saveSettings(notify: false);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _quality,
                  decoration: const InputDecoration(
                    labelText: 'Stream Quality Preset',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'movie', child: Text('Movie & Video (30 FPS, 5 Mbps)')),
                    DropdownMenuItem(value: 'gaming', child: Text('Gaming & Low Latency (60 FPS, 10 Mbps)')),
                    DropdownMenuItem(value: 'saver', child: Text('Data Saver (20 FPS, 1.5 Mbps)')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _quality = v);
                      _saveSettings(notify: false);
                    }
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _startSession,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Casting Session'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (Platform.isAndroid && !_acc) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.accessibility_new),
              title: const Text('Enable Remote Touch Control (Optional)'),
              subtitle: const Text('Tap to open Android Accessibility settings for MirrorNuke'),
              trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _checkAcc),
              onTap: AndroidControl.openSettings,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDevicesTab() {
    return AnimatedBuilder(
      animation: _directory,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Room Directory (${_room.text.trim()})',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Refresh directory',
                icon: const Icon(Icons.refresh),
                onPressed: _directory.reconnect,
              ),
            ],
          ),
          Text(_directory.status, style: Theme.of(context).textTheme.bodySmall),
          if (_directory.error != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_directory.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_directory.devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No other devices in this room yet. Open MirrorNuke on your other device with the same room code.'),
              ),
            )
          else
            for (final d in _directory.devices)
              Card(
                child: ListTile(
                  leading: Icon(d.platform == 'windows' ? Icons.computer : Icons.smartphone),
                  title: Text(d.name),
                  subtitle: Text('${d.platform.toUpperCase()} • ${d.caps.join(', ')}'),
                  trailing: FilledButton(
                    onPressed: () => _startSession(overrideTarget: d.name),
                    child: const Text('Connect'),
                  ),
                ),
              ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Wi-Fi Server Radar', style: Theme.of(context).textTheme.titleMedium),
              ),
              OutlinedButton.icon(
                onPressed: _scanningLan ? null : _scanLan,
                icon: _scanningLan
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find),
                label: Text(_scanningLan ? 'Scanning...' : 'Scan Wi-Fi'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lanDevices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tap "Scan Wi-Fi" to discover MirrorNuke servers advertised on your local network.'),
              ),
            )
          else
            for (final item in _lanDevices)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(item.name),
                  subtitle: Text('${item.model} (${item.host}:${item.port})'),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        _hostLocal = false;
                        _server.text = item.wsUrl;
                      });
                      _saveSettings();
                    },
                    child: const Text('Use Server'),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (Platform.isWindows) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Host local server on this PC'),
            subtitle: const Text('Runs built-in signaling automatically — no Node.js or terminal needed'),
            value: _hostLocal,
            onChanged: (v) async {
              setState(() => _hostLocal = v);
              await _saveSettings(notify: false);
            },
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _server,
          enabled: !_hostLocal,
          decoration: InputDecoration(
            labelText: _hostLocal
                ? 'External Server URL (disabled while hosting locally)'
                : 'Signaling Server URL (ws://PC-IP:8080)',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Server Token (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _room,
          decoration: const InputDecoration(
            labelText: 'Room Code (same on all your devices)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _me,
          decoration: const InputDecoration(
            labelText: 'This Device Name (unique in room)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _other,
          decoration: const InputDecoration(
            labelText: 'Default Target Device Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: _hidePass,
          decoration: InputDecoration(
            labelText: 'Pairing Password (8+ characters, same on both devices)',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_hidePass ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _hidePass = !_hidePass),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (Startup.supported)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start MirrorNuke with Windows'),
            subtitle: const Text('Starts minimized and shares after you sign in'),
            value: _startup,
            onChanged: (v) async {
              await Startup.set(v);
              final now = await Startup.isEnabled();
              if (mounted) setState(() => _startup = now);
            },
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _saveSettings(),
          icon: const Icon(Icons.save),
          label: const Text('Save & Refresh Directory'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _showDiagnostics,
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('View Diagnostic Log'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_buildOverviewTab(), _buildDevicesTab(), _buildSettingsTab()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('MirrorNuke'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: pages[_tab],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _refreshDirectory();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class LinkPage extends StatefulWidget {
  final Settings s;
  final String activeServerUrl;
  const LinkPage({super.key, required this.s, required this.activeServerUrl});

  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  ShareSession? _share;
  ViewSession? _view;

  @override
  void initState() {
    super.initState();
    final s = widget.s;
    final url = widget.activeServerUrl;
    if (s.share) {
      _share = ShareSession(
        url: url,
        room: s.room,
        name: s.me,
        token: s.token,
        password: s.password,
        shareAudio: s.shareAudio,
        quality: s.quality,
      )..start();
    }
    if (s.view) {
      _view = ViewSession(
        url: url,
        room: s.room,
        me: s.me,
        target: s.other,
        token: s.token,
        password: s.password,
        playAudio: s.playAudio,
      )..start();
    }
  }

  @override
  void dispose() {
    _share?.dispose();
    _view?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.pop(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_view != null)
            Positioned.fill(child: RemoteView(view: _view!, onClose: close))
          else
            Center(
              child: AnimatedBuilder(
                animation: _share!,
                builder: (_, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Sharing: ${_share!.status}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    if (_share!.displayNames.length > 1)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (var i = 0; i < _share!.displayNames.length; i++)
                            ChoiceChip(
                              label: Text('Display ${i + 1}'),
                              selected: _share!.selected == i,
                              onSelected: (_) => _share!.selectLocalDisplay(i),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${_share!.metrics.resolution} • ${_share!.metrics.fps} • ${_share!.metrics.bitrateKbps} • RTT ${_share!.metrics.rttMs}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: close, child: const Text('Stop Sharing')),
                  ],
                ),
              ),
            ),
          if (_share != null && _view != null)
            Positioned(
              left: 10,
              bottom: 10,
              child: AnimatedBuilder(
                animation: _share!,
                builder: (_, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'Sharing: ${_share!.status}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RemoteView extends StatefulWidget {
  final ViewSession view;
  final VoidCallback onClose;
  const RemoteView({super.key, required this.view, required this.onClose});

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  int _mode = 0;
  int _btn = 0;
  int _lastMove = 0;
  ViewSession get v => widget.view;

  Offset? _norm(Offset p, Size box) {
    final vw = v.renderer.videoWidth.toDouble();
    final vh = v.renderer.videoHeight.toDouble();
    if (vw == 0 || vh == 0) return null;
    final scale = min(box.width / vw, box.height / vh);
    final w = vw * scale, h = vh * scale;
    final ox = (box.width - w) / 2, oy = (box.height - h) / 2;
    return Offset(((p.dx - ox) / w).clamp(0.0, 1.0), ((p.dy - oy) / h).clamp(0.0, 1.0));
  }

  void _ptr(String a, PointerEvent e, Size box) {
    final n = _norm(e.localPosition, box);
    if (n == null) return;
    final isMouse = e.kind == PointerDeviceKind.mouse;
    if (a == 'down') {
      if (isMouse) {
        _btn = (e.buttons & kSecondaryMouseButton) != 0 ? 2 : ((e.buttons & kMiddleMouseButton) != 0 ? 1 : 0);
      } else {
        _btn = _mode == 1 ? 2 : 0;
      }
    }
    if (_mode == 2 && !isMouse) {
      if (a == 'move') v.sendControl({'t': 'wheel', 'dy': -e.delta.dy * 2});
      return;
    }
    if (a == 'move') {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastMove < 12) return;
      _lastMove = now;
    }
    v.sendControl({'t': 'mouse', 'a': a, 'x': n.dx, 'y': n.dy, 'b': _btn});
  }

  Future<void> _keyboard() async {
    final c = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Type on remote device'),
        content: TextField(controller: c, autofocus: true, maxLength: 200),
        actions: [
          TextButton(onPressed: () => v.sendControl({'t': 'key', 'k': 'backspace'}), child: const Text('Backspace')),
          TextButton(onPressed: () => v.sendControl({'t': 'key', 'k': 'enter'}), child: const Text('Enter')),
          FilledButton(
            onPressed: () {
              v.sendControl({'t': 'text', 's': c.text});
              c.clear();
            },
            child: const Text('Send'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
    c.dispose();
  }

  Future<void> _sendClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text ?? '';
    if (txt.isNotEmpty) {
      v.sendControl({'t': 'clipboard', 's': txt});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard sent to remote device')));
      }
    }
  }

  Widget _modeBtn(int mode, IconData icon, String tip) => IconButton(
        tooltip: tip,
        icon: Icon(icon, color: _mode == mode ? Colors.lightBlueAccent : Colors.white),
        onPressed: () => setState(() => _mode = mode),
      );

  Widget _toolbar() => SafeArea(
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: widget.onClose),
                if (v.authed) ...[
                  IconButton(
                    tooltip: v.audioMuted ? 'Unmute speaker audio' : 'Mute speaker audio',
                    icon: Icon(
                      v.audioMuted ? Icons.volume_off : Icons.volume_up,
                      color: v.remoteAudioEnabled ? Colors.lightGreenAccent : Colors.white70,
                    ),
                    onPressed: v.toggleMute,
                  ),
                  for (var i = 0; i < v.names.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(v.names.length > 1 ? 'Display ${i + 1}' : v.names[i]),
                        selected: v.selected == i,
                        onSelected: (_) => v.selectScreen(i),
                      ),
                    ),
                  _modeBtn(0, Icons.touch_app, 'Click / touch'),
                  _modeBtn(1, Icons.mouse, 'Right-click'),
                  _modeBtn(2, Icons.swap_vert, 'Scroll'),
                  IconButton(tooltip: 'Keyboard', icon: const Icon(Icons.keyboard, color: Colors.white), onPressed: _keyboard),
                  IconButton(tooltip: 'Send clipboard', icon: const Icon(Icons.content_paste, color: Colors.white), onPressed: _sendClipboard),
                  if (v.os == 'android') ...[
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => v.sendControl({'t': 'nav', 'a': 'back'})),
                    IconButton(icon: const Icon(Icons.circle_outlined, color: Colors.white), onPressed: () => v.sendControl({'t': 'nav', 'a': 'home'})),
                    IconButton(icon: const Icon(Icons.crop_square, color: Colors.white), onPressed: () => v.sendControl({'t': 'nav', 'a': 'recents'})),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    '${v.metrics.resolution} • ${v.metrics.fps} • ${v.metrics.bitrateKbps} • RTT ${v.metrics.rttMs} • Loss ${v.metrics.packetLoss}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: v,
      builder: (_, _) => Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (ctx, c) {
              final box = Size(c.maxWidth, c.maxHeight);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _ptr('down', e, box),
                onPointerMove: (e) => _ptr('move', e, box),
                onPointerUp: (e) => _ptr('up', e, box),
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) v.sendControl({'t': 'wheel', 'dy': e.scrollDelta.dy});
                },
                child: v.hasVideo
                    ? RTCVideoView(v.renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            v.status,
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
              );
            }),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _toolbar()),
        ],
      ),
    );
  }
}
