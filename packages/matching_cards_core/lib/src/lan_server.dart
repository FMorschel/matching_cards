import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'game_engine.dart';
import 'protocol.dart';
import 'static_source.dart';

/// Hosts one game: a WebSocket endpoint at `/ws` for players, plus the web
/// client over plain HTTP so a browser can join by just opening the address.
///
/// Connections from this machine are always accepted. Connections from the
/// network are only accepted while [acceptRemote] is true.
class LanServer {
  LanServer({
    required this.engine,
    this.staticSource,
    bool acceptRemote = false,
  }) : _acceptRemote = acceptRemote;

  final GameEngine engine;

  /// Where the web client comes from. Without one, browsers get a short
  /// explanation instead of the game.
  final StaticSource? staticSource;

  HttpServer? _http;
  bool _acceptRemote;

  // Open sockets, and whether each one connected from this machine.
  final Map<WebSocket, bool> _sockets = {};
  final Map<WebSocket, String> _playerBySocket = {};

  /// The port the server listens on, once started.
  int get port => _http?.port ?? 0;

  bool get isRunning => _http != null;

  /// Whether other machines may connect. Turning this off disconnects every
  /// player who is not on this machine.
  bool get acceptRemote => _acceptRemote;

  set acceptRemote(bool value) {
    _acceptRemote = value;
    if (!value) {
      for (final entry in _sockets.entries.toList()) {
        if (!entry.value) entry.key.close(WebSocketStatus.goingAway);
      }
    }
  }

  /// Starts listening on all IPv4 interfaces. Pass port 0 to let the system
  /// choose one. Throws a [SocketException] if the port is taken.
  Future<void> start({int port = defaultGamePort}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http = server;
    server.listen(_handleRequest, onError: (Object _) {});
  }

  Future<void> stop() async {
    final server = _http;
    _http = null;
    for (final socket in _sockets.keys.toList()) {
      // Not awaited: a client that has vanished must not hold up shutdown.
      socket.close(WebSocketStatus.goingAway);
    }
    _sockets.clear();
    _playerBySocket.clear();
    await server?.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // HTTP

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final remote = request.connectionInfo?.remoteAddress;
      final isLocal = remote != null && remote.isLoopback;
      if (!isLocal && !_acceptRemote) {
        response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.text
          ..write('This game is not open to other players yet.');
        await response.close();
        return;
      }

      if (request.uri.path == webSocketPath &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _onSocket(socket, isLocal);
        return;
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      if (request.uri.path == '/api/info') {
        response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'app': 'matching_cards',
              'name': engine.gameName,
              'protocol': protocolVersion,
              'players': engine.connectedCount,
            }),
          );
        await response.close();
        return;
      }

      await _serveStatic(request);
    } catch (_) {
      try {
        await response.close();
      } catch (_) {
        // The client is already gone.
      }
    }
  }

  Future<void> _serveStatic(HttpRequest request) async {
    final response = request.response;
    final segments = _safeSegments(request.uri);
    if (segments == null) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    if (segments.isEmpty) segments.add('index.html');

    final source = staticSource;
    final file = source == null ? null : await source.read(segments);
    if (file == null) {
      if (segments.length == 1 && segments.first == 'index.html') {
        response
          ..headers.contentType = ContentType.html
          ..write(_noWebClientPage);
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
      return;
    }

    response.headers.contentType = ContentType.parse(file.contentType);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.contentLength = file.bytes.length;
    if (request.method != 'HEAD') response.add(file.bytes);
    await response.close();
  }

  /// URL-decoded path segments, or null if the path tries to escape the root.
  List<String>? _safeSegments(Uri uri) {
    final segments = <String>[];
    for (final segment in uri.pathSegments) {
      if (segment.isEmpty) continue;
      if (segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains(r'\') ||
          segment.contains(':')) {
        return null;
      }
      segments.add(segment);
    }
    return segments;
  }

  // ---------------------------------------------------------------------------
  // WebSocket

  void _onSocket(WebSocket socket, bool isLocal) {
    socket.pingInterval = const Duration(seconds: 20);
    _sockets[socket] = isLocal;
    socket.listen(
      (Object? data) => _onMessage(socket, data),
      onDone: () => _onClosed(socket),
      onError: (Object _) => _onClosed(socket),
      cancelOnError: true,
    );
  }

  void _onClosed(WebSocket socket) {
    _sockets.remove(socket);
    final playerId = _playerBySocket.remove(socket);
    if (playerId == null) return;
    engine.disconnect(playerId);
    _broadcast();
  }

  void _onMessage(WebSocket socket, Object? data) {
    if (data is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final message = decoded;

    try {
      final type = message['t'];
      if (type == 'join') {
        _join(socket, message);
        return;
      }
      final playerId = _playerBySocket[socket];
      if (playerId == null) throw GameError('Join the game first.');

      switch (type) {
        case 'config':
          engine.setConfig(
            playerId,
            GameConfig.fromJson(message['config'] as Map<String, dynamic>),
          );
        case 'start':
          engine.start(playerId);
        case 'submit':
          engine.submit(playerId, [
            for (final id in message['cards'] as List) (id as num).toInt(),
          ]);
        case 'pick':
          engine.pickWinner(playerId, (message['submission'] as num).toInt());
        case 'next':
          engine.next(playerId);
        case 'end':
          engine.endGame(playerId);
        case 'again':
          engine.playAgain(playerId);
        case 'kick':
          final target = message['player'] as String;
          engine.kick(playerId, target);
          _dropSocketsOf(target);
        default:
          throw GameError('Unknown message.');
      }
      _broadcast();
    } on GameError catch (error) {
      _send(socket, {'t': 'error', 'message': error.message});
    } catch (_) {
      _send(socket, {'t': 'error', 'message': 'That message was not understood.'});
    }
  }

  void _join(WebSocket socket, Map<String, dynamic> message) {
    if (_playerBySocket.containsKey(socket)) {
      throw GameError('You already joined.');
    }
    final name = message['name'];
    final token = message['token'];
    final result = engine.join(
      name: name is String ? name : '',
      token: token is String ? token : null,
    );

    // A player who reconnects replaces any older socket that is still open.
    _dropSocketsOf(result.playerId);

    _playerBySocket[socket] = result.playerId;
    _send(socket, {
      't': 'welcome',
      'playerId': result.playerId,
      'token': result.token,
      'protocol': protocolVersion,
    });
    _broadcast();
  }

  void _dropSocketsOf(String playerId) {
    for (final entry in _playerBySocket.entries.toList()) {
      if (entry.value == playerId) {
        _playerBySocket.remove(entry.key);
        entry.key.close(WebSocketStatus.normalClosure);
      }
    }
  }

  void _broadcast() {
    for (final entry in _playerBySocket.entries.toList()) {
      final view = _viewOrNull(entry.value);
      if (view == null) continue;
      _send(entry.key, {'t': 'state', ...view.toJson()});
    }
  }

  GameView? _viewOrNull(String playerId) {
    try {
      return engine.viewFor(playerId);
    } on GameError {
      return null;
    }
  }

  void _send(WebSocket socket, Map<String, Object?> message) {
    try {
      socket.add(jsonEncode(message));
    } catch (_) {
      // The socket closed under us; its onDone handler cleans up.
    }
  }
}

const String _noWebClientPage = '''
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Matching Cards</title>
<body style="font-family: sans-serif; max-width: 34rem; margin: 3rem auto; padding: 0 1rem">
<h1>Matching Cards</h1>
<p>A game is running here, but this host has no web client to hand out.</p>
<p>If you are the host: run <code>dart run tool/bundle_web.dart</code> and
rebuild the app, or start the headless server with
<code>--web build/web</code>. Everyone using the app can still join from the
Join screen.</p>
</body>
''';
