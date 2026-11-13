import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

class DiscoveredLanDevice {
  final String name;
  final String host;
  final int port;
  final String kind; // 'mirrornuke' | 'chromecast'
  final String model;

  DiscoveredLanDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.kind,
    this.model = '',
  });

  String get wsUrl => 'ws://$host:$port';
}

/// Zero-config mDNS scanner that detects MirrorNuke servers (_mirrornuke._tcp.local)
/// and Google Cast / Chromecast receivers (_googlecast._tcp.local) on the local Wi-Fi.
class LanDiscovery {
  static Future<List<DiscoveredLanDevice>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <String, DiscoveredLanDevice>{};
    final client = MDnsClient();
    try {
      await client.start();
    } catch (_) {
      return [];
    }

    Future<void> probe(String ptrName, String kind) async {
      try {
        await for (final ptr in client
            .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(ptrName))
            .timeout(timeout, onTimeout: (sink) => sink.close())) {
          await for (final srv in client
              .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
              .timeout(const Duration(milliseconds: 900), onTimeout: (sink) => sink.close())) {
            final meta = <String, String>{};
            await for (final txt in client
                .lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName))
                .timeout(const Duration(milliseconds: 600), onTimeout: (sink) => sink.close())) {
              for (final line in txt.text.split('\n')) {
                final idx = line.indexOf('=');
                if (idx > 0) {
                  meta[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
                }
              }
            }
            await for (final ip in client
                .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
                .timeout(const Duration(milliseconds: 900), onTimeout: (sink) => sink.close())) {
              final key = '$kind:${ip.address.address}:${srv.port}';
              found[key] = DiscoveredLanDevice(
                name: meta['fn'] ?? ptr.domainName.split('.').first,
                host: ip.address.address,
                port: srv.port,
                kind: kind,
                model: meta['md'] ?? (kind == 'chromecast' ? 'Google Cast Receiver' : 'MirrorNuke Server'),
              );
            }
          }
        }
      } catch (_) {}
    }

    try {
      await Future.wait([
        probe('_mirrornuke._tcp.local', 'mirrornuke'),
        probe('_googlecast._tcp.local', 'chromecast'),
      ]);
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
    return found.values.toList();
  }
}
