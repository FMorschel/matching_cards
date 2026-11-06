import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// The UDP port hosts announce themselves on.
const int discoveryPort = 41234;

/// This machine's IPv4 addresses on real networks, most likely home network
/// first (192.168.x.x, then 10.x.x.x, then 172.16-31.x.x).
Future<List<String>> localIPv4Addresses() async {
  final adapters = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final found = <String>[];
  for (final adapter in adapters) {
    for (final address in adapter.addresses) {
      if (!address.isLoopback) found.add(address.address);
    }
  }
  found.sort((a, b) => _rank(a).compareTo(_rank(b)));
  return found;
}

int _rank(String ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  final parts = ip.split('.');
  if (parts.length == 4 && parts[0] == '172') {
    final second = int.tryParse(parts[1]) ?? 0;
    if (second >= 16 && second <= 31) return 2;
  }
  if (ip.startsWith('169.254.')) return 9;
  return 5;
}

/// Announces a game on the local network once a second, so that apps on other
/// machines can list it.
///
/// Announcements go out as UDP broadcasts to each local /24 network and to
/// 255.255.255.255. Browsers cannot receive these; they join by address.
class LanAdvertiser {
  LanAdvertiser({
    required this.port,
    required this.nameOf,
    required this.playersOf,
  });

  /// The port the game server listens on.
  final int port;

  final String Function() nameOf;
  final int Function() playersOf;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<InternetAddress> _targets = [InternetAddress('255.255.255.255')];
  int _ticks = 0;

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    _socket = socket;
    await _refreshTargets();
    _announce();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _announce());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  void _announce() {
    final socket = _socket;
    if (socket == null) return;
    _ticks++;
    if (_ticks % 10 == 0) unawaited(_refreshTargets());
    final payload = utf8.encode(
      jsonEncode({
        'app': 'matching_cards',
        'v': protocolVersion,
        'name': nameOf(),
        'port': port,
        'players': playersOf(),
      }),
    );
    for (final target in _targets) {
      try {
        socket.send(payload, target, discoveryPort);
      } catch (_) {
        // That network may not allow broadcasts; the others still work.
      }
    }
  }

  Future<void> _refreshTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      for (final address in await localIPv4Addresses()) {
        final parts = address.split('.');
        if (parts.length == 4) {
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } catch (_) {
      // Keep whatever targets we had.
    }
    _targets = [for (final target in targets) InternetAddress(target)];
  }
}

class _Sighting {
  _Sighting(this.game, this.seenAt);

  final DiscoveredGame game;
  final DateTime seenAt;
}

/// Listens for [LanAdvertiser] announcements and keeps a list of the games
/// currently on the network.
class LanScanner {
  final Map<String, _Sighting> _seen = {};
  final StreamController<List<DiscoveredGame>> _controller =
      StreamController<List<DiscoveredGame>>.broadcast();

  RawDatagramSocket? _socket;
  Timer? _pruneTimer;

  /// Emits the full list whenever a game appears, changes or goes away.
  Stream<List<DiscoveredGame>> get games => _controller.stream;

  List<DiscoveredGame> get current => _snapshot();

  /// Starts listening. Throws a [SocketException] if the port is unavailable.
  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      var datagram = socket.receive();
      while (datagram != null) {
        _handle(datagram);
        datagram = socket.receive();
      }
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) => _prune());
  }

  Future<void> stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _seen.clear();
    if (!_controller.isClosed) await _controller.close();
  }

  void _handle(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['app'] != 'matching_cards') return;
      final port = decoded['port'];
      final name = decoded['name'];
      final players = decoded['players'];
      if (port is! int || name is! String) return;

      final game = DiscoveredGame(
        name: name,
        host: datagram.address.address,
        port: port,
        players: players is int ? players : 0,
      );
      final key = '${game.host}:${game.port}';
      final previous = _seen[key]?.game;
      _seen[key] = _Sighting(game, DateTime.now());
      if (previous == null ||
          previous.name != game.name ||
          previous.players != game.players) {
        _emit();
      }
    } catch (_) {
      // Not one of ours; ignore it.
    }
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
    final before = _seen.length;
    _seen.removeWhere((_, sighting) => sighting.seenAt.isBefore(cutoff));
    if (_seen.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  List<DiscoveredGame> _snapshot() {
    final list = [for (final sighting in _seen.values) sighting.game];
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}
