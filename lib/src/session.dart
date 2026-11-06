import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'storage.dart';

enum SessionStatus { idle, connecting, connected, closed, failed }

/// One player's connection to a host, as a [ChangeNotifier] the UI listens to.
class GameSession extends ChangeNotifier {
  GameSession();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<String> _errors = StreamController<String>.broadcast();
  bool _disposed = false;

  SessionStatus status = SessionStatus.idle;
  GameView? view;
  String? playerId;
  String? failure;

  /// Rule violations and the like, to show in a SnackBar.
  Stream<String> get errors => _errors.stream;

  bool get isHost => view?.you.isHost ?? false;

  static String hostKey(Uri uri) => '${uri.host}:${uri.port}';

  /// Connects to [uri] and joins as [name]. Returns true on success.
  Future<bool> connect(Uri uri, String name) async {
    await close();
    status = SessionStatus.connecting;
    failure = null;
    view = null;
    notifyListeners();

    final key = hostKey(uri);
    final token = await Prefs.loadToken(key);
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 6));
      final welcomed = Completer<void>();
      _subscription = channel.stream.listen(
        (data) => _onData(data, key, welcomed),
        onError: (Object error) => _onClosed('The connection failed.'),
        onDone: () => _onClosed('The connection was closed.'),
      );
      _send({'t': 'join', 'name': name, 'token': token});
      await welcomed.future.timeout(const Duration(seconds: 6));
      status = SessionStatus.connected;
      notifyListeners();
      return true;
    } catch (error) {
      await close();
      status = SessionStatus.failed;
      failure = error is TimeoutException
          ? 'Nobody answered at ${uri.host}:${uri.port}.'
          : 'Could not reach ${uri.host}:${uri.port}.';
      notifyListeners();
      return false;
    }
  }

  void _onData(dynamic data, String key, Completer<void> welcomed) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['t']) {
      case 'welcome':
        playerId = decoded['playerId'] as String?;
        unawaited(Prefs.saveToken(key, decoded['token'] as String?));
        if (!welcomed.isCompleted) welcomed.complete();
      case 'state':
        view = GameView.fromJson(decoded);
        notifyListeners();
      case 'error':
        final message = decoded['message'] as String? ?? 'Something went wrong.';
        if (!welcomed.isCompleted) {
          welcomed.completeError(StateError(message));
          failure = message;
        } else if (!_errors.isClosed) {
          _errors.add(message);
        }
    }
  }

  void _onClosed(String message) {
    if (_disposed || status == SessionStatus.closed) return;
    if (status == SessionStatus.connected) {
      status = SessionStatus.closed;
      failure = message;
      notifyListeners();
    }
  }

  void _send(Map<String, Object?> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  // Actions -------------------------------------------------------------------

  void setConfig(GameConfig config) => _send({'t': 'config', 'config': config.toJson()});
  void start() => _send({'t': 'start'});
  void submit(List<int> cards) => _send({'t': 'submit', 'cards': cards});
  void pick(int submission) => _send({'t': 'pick', 'submission': submission});
  void next() => _send({'t': 'next'});
  void endGame() => _send({'t': 'end'});
  void playAgain() => _send({'t': 'again'});
  void kick(String player) => _send({'t': 'kick', 'player': player});

  /// Leaves the game. The saved seat token stays, so rejoining resumes it.
  Future<void> close() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {}
    if (status != SessionStatus.failed) status = SessionStatus.closed;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    _errors.close();
    super.dispose();
  }
}
