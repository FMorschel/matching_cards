import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:matching_cards_core/server.dart';

/// Hosts a game inside the app: the game engine, a WebSocket server, the web
/// client for browsers, and the LAN announcement.
class LanHost {
  static bool get supported => true;

  LanServer? _server;
  LanAdvertiser? _advertiser;
  GameEngine? _engine;
  List<String> _addresses = const [];
  bool _webClient = false;

  bool get isRunning => _server?.isRunning ?? false;
  bool get isOpen => _server?.acceptRemote ?? false;
  bool get webClientBundled => _webClient;
  int get port => _server?.port ?? 0;
  List<String> get addresses => _addresses;

  /// Where this machine's own player connects.
  Uri get localSocketUri => Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        path: webSocketPath,
      );

  Future<void> start({required String gameName}) async {
    if (isRunning) return;
    final json = await rootBundle.loadString('assets/decks/cards.json');
    final engine = GameEngine(
      library: DeckLibrary.fromJsonStrings([json]),
      gameName: gameName,
    );
    final source = await _AssetStaticSource.load();
    _webClient = source != null;
    final server = LanServer(engine: engine, staticSource: source);
    try {
      await server.start(port: defaultGamePort);
    } on SocketException {
      await server.start(port: 0);
    }
    _engine = engine;
    _server = server;
    _addresses = await _safeAddresses();
  }

  /// "I want others to join in": accept players from the network and announce
  /// the game. Turning it off sends remote players away again.
  Future<void> setOpen(bool open) async {
    final server = _server;
    final engine = _engine;
    if (server == null || engine == null) return;
    server.acceptRemote = open;
    if (open) {
      _addresses = await _safeAddresses();
      final advertiser = _advertiser ??
          LanAdvertiser(
            port: server.port,
            nameOf: () => engine.gameName,
            playersOf: () => engine.connectedCount,
          );
      _advertiser = advertiser;
      try {
        await advertiser.start();
      } on SocketException {
        // Browsers and typed addresses still work without the announcement.
      }
    } else {
      await _advertiser?.stop();
      _advertiser = null;
    }
  }

  Future<void> stop() async {
    await _advertiser?.stop();
    _advertiser = null;
    await _server?.stop();
    _server = null;
    _engine = null;
  }

  Future<List<String>> _safeAddresses() async {
    try {
      return await localIPv4Addresses();
    } catch (_) {
      return const [];
    }
  }
}

/// Serves the web client that `tool/bundle_web.dart` put into the app assets.
class _AssetStaticSource implements StaticSource {
  _AssetStaticSource(this._paths);

  final Set<String> _paths;

  static Future<_AssetStaticSource?> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/web_client/'))
          .toSet();
      if (!paths.contains('assets/web_client/index.html')) return null;
      return _AssetStaticSource(paths);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StaticFile?> read(List<String> segments) async {
    final key = 'assets/web_client/${segments.join('/')}';
    if (!_paths.contains(key)) return null;
    try {
      final data = await rootBundle.load(key);
      return StaticFile(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        contentTypeFor(segments.last),
      );
    } catch (_) {
      return null;
    }
  }
}
