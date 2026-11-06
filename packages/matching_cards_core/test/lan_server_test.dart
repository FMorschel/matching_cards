import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:matching_cards_core/server.dart';
import 'package:test/test.dart';

DeckLibrary _library() => DeckLibrary([
      DeckCategory(
        name: 'One',
        black: ['First _____ here.', 'Second _____ there.'],
        white: [for (var i = 0; i < 60; i++) 'Answer $i'],
      ),
    ]);

/// A bare-bones player that talks to the server like the real app does.
class _Client {
  _Client._(this._socket);

  final WebSocket _socket;
  GameView? view;
  String? playerId;
  String? token;
  final List<String> errors = [];
  final StreamController<void> _changed = StreamController<void>.broadcast();

  static Future<_Client> join(
    int port,
    String name, {
    String? token,
  }) async {
    final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final client = _Client._(socket);
    socket.listen((Object? data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      switch (message['t']) {
        case 'welcome':
          client.playerId = message['playerId'] as String;
          client.token = message['token'] as String;
        case 'state':
          client.view = GameView.fromJson(message);
        case 'error':
          client.errors.add(message['message'] as String);
      }
      client._changed.add(null);
    });
    client.send({'t': 'join', 'name': name, 'token': token});
    await client.waitFor((_) => true);
    return client;
  }

  void send(Map<String, Object?> message) => _socket.add(jsonEncode(message));

  Future<GameView> waitFor(bool Function(GameView view) test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final current = view;
      if (current != null && test(current)) return current;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for the expected state.');
      }
      await _changed.stream.first.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
    }
  }

  Future<String> nextError() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (errors.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('No error arrived.');
      }
      await _changed.stream.first.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
    }
    return errors.first;
  }

  Future<void> close() => _socket.close();
}

class _Response {
  _Response(this.status, this.body, this.mimeType);

  final int status;
  final String body;
  final String? mimeType;
}

Future<_Response> _get(int port, String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    return _Response(
      response.statusCode,
      body,
      response.headers.contentType?.mimeType,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  late GameEngine engine;
  late LanServer server;
  final clients = <_Client>[];

  setUp(() async {
    engine = GameEngine(library: _library(), random: Random(7));
    server = LanServer(engine: engine);
    await server.start(port: 0);
  });

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    await server.stop();
  });

  Future<_Client> join(String name, {String? token}) async {
    final client = await _Client.join(server.port, name, token: token);
    clients.add(client);
    return client;
  }

  test('plays a round over real WebSockets', () async {
    final alice = await join('Alice');
    final bob = await join('Bob');
    final cara = await join('Cara');
    final everyone = [alice, bob, cara];

    await alice.waitFor((v) => v.players.length == 3);
    expect(alice.view!.you.isHost, isTrue);

    alice.send({'t': 'start'});
    for (final client in everyone) {
      await client.waitFor((v) => v.phase == Phase.picking);
    }

    final czarId = alice.view!.round!.czarId;
    final czar = everyone.firstWhere((c) => c.playerId == czarId);
    final players = everyone.where((c) => c != czar).toList();
    for (final player in players) {
      final v = player.view!;
      player.send({
        't': 'submit',
        'cards': [for (final c in v.you.hand.take(v.round!.pick)) c.id],
      });
    }

    await czar.waitFor((v) => v.phase == Phase.judging);
    expect(czar.view!.round!.submissions, hasLength(2));

    czar.send({'t': 'pick', 'submission': 0});
    await alice.waitFor((v) => v.phase == Phase.roundEnd);
    expect(alice.view!.round!.winnerId, isNotNull);
  });

  test('sends rule violations back to the player who caused them', () async {
    final alice = await join('Alice');
    final bob = await join('Bob');
    await bob.waitFor((v) => v.players.length == 2);

    bob.send({'t': 'start'});
    expect(await bob.nextError(), 'Only the host can do that.');
    expect(alice.errors, isEmpty);
  });

  test('a returning player keeps their seat', () async {
    final alice = await join('Alice');
    final bob = await join('Bob');
    final cara = await join('Cara');
    await alice.waitFor((v) => v.players.length == 3);
    alice.send({'t': 'start'});
    await cara.waitFor((v) => v.phase == Phase.picking);

    final bobsId = bob.playerId!;
    await bob.close();
    await alice.waitFor(
      (v) => !v.players.singleWhere((p) => p.id == bobsId).connected,
    );

    final back = await join('Bob', token: bob.token);
    expect(back.playerId, bobsId);
    await alice.waitFor(
      (v) => v.players.singleWhere((p) => p.id == bobsId).connected,
    );
    expect(back.view!.you.hand, isNotEmpty);
  });

  test('reports itself at /api/info', () async {
    final response = await _get(server.port, '/api/info');
    expect(response.status, 200);
    final info = jsonDecode(response.body) as Map<String, dynamic>;
    expect(info['app'], 'matching_cards');
    expect(info['name'], engine.gameName);
  });

  test('explains itself when there is no web client', () async {
    final response = await _get(server.port, '/');
    expect(response.status, 200);
    expect(response.body, contains('Matching Cards'));
    expect((await _get(server.port, '/missing.js')).status, 404);
  });

  test('serves the web client from a folder', () async {
    final dir = Directory.systemTemp.createTempSync('matching_cards_web');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}index.html')
        .writeAsStringSync('<h1>hello</h1>');
    File('${dir.path}${Platform.pathSeparator}app.js')
        .writeAsStringSync('console.log(1)');

    final withWeb = LanServer(
      engine: engine,
      staticSource: DirectoryStaticSource(dir),
    );
    await withWeb.start(port: 0);
    addTearDown(withWeb.stop);

    final index = await _get(withWeb.port, '/');
    expect(index.status, 200);
    expect(index.body, '<h1>hello</h1>');
    expect(index.mimeType, 'text/html');

    final script = await _get(withWeb.port, '/app.js');
    expect(script.status, 200);
    expect(script.mimeType, 'text/javascript');

    expect((await _get(withWeb.port, '/nope.png')).status, 404);
  });
}
