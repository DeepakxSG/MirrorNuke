import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'security.dart';

class DiscoveredLanDevice {
  final String name;
  final String host;
  final int port;
  final String model;

  DiscoveredLanDevice({
    required this.name,
    required this.host,
    required this.port,
    this.model = 'MirrorNuke PC Server',
  });

  String get wsUrl => 'ws://$host:$port';
}

/// Zero-config mDNS scanner that discovers MirrorNuke servers (_mirrornuke._tcp.local) on Wi-Fi.
class LanDiscovery {
  static Future<List<DiscoveredLanDevice>> scan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <String, DiscoveredLanDevice>{};
    final client = MDnsClient();
    try {
      await client.start();
    } catch (e) {
      AppLog.add('lanDiscovery.start', e);
      return [];
    }

    try {
      await for (final ptr in client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_mirrornuke._tcp.local'))
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
            final key = '${ip.address.address}:${srv.port}';
            found[key] = DiscoveredLanDevice(
              name: meta['fn'] ?? ptr.domainName.split('.').first,
              host: ip.address.address,
              port: srv.port,
              model: meta['md'] ?? 'MirrorNuke Server',
            );
          }
        }
      }
    } catch (e) {
      AppLog.add('lanDiscovery.scan', e);
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
    return found.values.toList();
  }
}
