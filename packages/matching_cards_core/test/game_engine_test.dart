import 'dart:io';
import 'dart:math';

import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:test/test.dart';

DeckLibrary _library() => DeckLibrary([
      DeckCategory(
        name: 'One',
        black: ['First _____ here.', 'Second _____ there.'],
        white: [for (var i = 0; i < 40; i++) 'Answer $i'],
      ),
      DeckCategory(
        name: 'Two',
        black: ['Third _____ now.'],
        white: [for (var i = 40; i < 80; i++) 'Answer $i'],
      ),
    ]);

const _names = ['Alice', 'Bob', 'Cara', 'Dan', 'Eve'];

/// A few players around one engine. Alice joins first, so she is the host and
/// the first Card Czar.
class _Table {
  _Table({DeckLibrary? library, int players = 4, int seed = 1})
      : engine = GameEngine(
          library: library ?? _library(),
          random: Random(seed),
        ) {
    for (var i = 0; i < players; i++) {
      final result = engine.join(name: _names[i]);
      ids.add(result.playerId);
      tokens.add(result.token);
    }
  }

  final GameEngine engine;
  final List<String> ids = [];
  final List<String> tokens = [];

  String get host => ids.first;

  GameView view(String id) => engine.viewFor(id);

  RoundView get round => view(host).round!;

  String get czar => round.czarId;

  /// Everybody who is not the Card Czar this round.
  List<String> get others => [
        for (final id in ids)
          if (id != czar) id,
      ];

  /// Plays the first cards of [id]'s hand.
  void play(String id) {
    final v = view(id);
    engine.submit(id, [for (final c in v.you.hand.take(v.round!.pick)) c.id]);
  }

  void playAll() {
    for (final id in others) {
      play(id);
    }
  }
}

void main() {
  group('prompts', () {
    test('fillBlanks writes answers in order', () {
      expect(fillBlanks('A _____ B', ['x']), 'A x B');
      expect(fillBlanks('A _____ and _____.', ['x', 'y']), 'A x and y.');
    });

    test('fillBlanks leaves blanks that have no answer yet', () {
      expect(fillBlanks('A _____ and _____.', ['x']), 'A x and _____.');
    });

    test('pickCount is one per blank, at least one', () {
      expect(pickCount('One _____.'), 1);
      expect(pickCount('_____ and _____'), 2);
      expect(pickCount('No blank'), 1);
    });
  });

  group('DeckLibrary', () {
    test('merges categories that share a name', () {
      const a = '{"categories":[{"name":"X","black":["a _____"],"white":["1"]}]}';
      const b = '{"categories":[{"name":"X","black":["b _____"],"white":["2"]}]}';
      final library = DeckLibrary.fromJsonStrings([a, b]);
      expect(library.names, ['X']);
      expect(library.categories.single.black, ['a _____', 'b _____']);
      expect(library.categories.single.white, ['1', '2']);
    });

    test('rejects a prompt without a blank', () {
      const bad = '{"categories":[{"name":"X","black":["no blank"],"white":[]}]}';
      expect(
        () => DeckLibrary.fromJsonStrings([bad]),
        throwsA(isA<FormatException>()),
      );
    });

    test('pool only uses the chosen categories and drops duplicates', () {
      final library = DeckLibrary([
        const DeckCategory(name: 'A', black: ['p _____'], white: ['x', 'y']),
        const DeckCategory(name: 'B', black: ['q _____'], white: ['y', 'z']),
        const DeckCategory(name: 'C', black: ['r _____'], white: ['w']),
      ]);
      final pool = library.pool(['A', 'B']);
      expect(pool.black, ['p _____', 'q _____']);
      expect(pool.white, ['x', 'y', 'z']);
    });

    test('the bundled decks load and are playable', () {
      final path = [
        '../../assets/decks/cards.json',
        'assets/decks/cards.json',
      ].firstWhere((p) => File(p).existsSync());
      final library = DeckLibrary.fromJsonStrings([File(path).readAsStringSync()]);
      final pool = library.pool(library.names);
      expect(library.categories.length, greaterThanOrEqualTo(30));
      expect(pool.black.length, greaterThan(700));
      expect(pool.white.length, greaterThan(700));
      expect(pool.black.every((p) => blankCount(p) >= 1), isTrue);
    });
  });

  group('addresses', () {
    test('parseGameAddress accepts what people type', () {
      final plain = parseGameAddress('192.168.1.20')!;
      expect([plain.scheme, plain.host, plain.port, plain.path],
          ['ws', '192.168.1.20', 8080, '/ws']);

      final withPort = parseGameAddress(' 192.168.1.20:9000 ')!;
      expect(withPort.port, 9000);

      final url = parseGameAddress('http://party.local:8081/')!;
      expect([url.scheme, url.host, url.port], ['ws', 'party.local', 8081]);

      final secure = parseGameAddress('https://example.com')!;
      expect([secure.scheme, secure.port], ['wss', 443]);
    });

    test('parseGameAddress rejects nonsense', () {
      expect(parseGameAddress(''), isNull);
      expect(parseGameAddress('   '), isNull);
      expect(parseGameAddress('ftp://example.com'), isNull);
    });
  });

  group('lobby', () {
    test('the first player is the host', () {
      final t = _Table();
      expect(t.view(t.ids[0]).you.isHost, isTrue);
      expect(t.view(t.ids[1]).you.isHost, isFalse);
    });

    test('duplicate names get a number', () {
      final engine = GameEngine(library: _library());
      engine.join(name: 'Sam');
      final second = engine.join(name: 'sam');
      expect(engine.viewFor(second.playerId).players.map((p) => p.name),
          ['Sam', 'sam (2)']);
    });

    test('leaving the lobby frees the seat and passes the host on', () {
      final t = _Table();
      t.engine.disconnect(t.ids[0]);
      expect(t.view(t.ids[1]).players, hasLength(3));
      expect(t.view(t.ids[1]).you.isHost, isTrue);
    });

    test('only the host can start, and only with enough players', () {
      final two = _Table(players: 2);
      expect(() => two.engine.start(two.host), throwsA(isA<GameError>()));

      final three = _Table(players: 3);
      expect(() => three.engine.start(three.ids[1]), throwsA(isA<GameError>()));
      three.engine.start(three.host);
      expect(three.engine.phase, Phase.picking);
    });

    test('settings are clamped, validated and host-only', () {
      final t = _Table();
      t.engine.setConfig(
        t.host,
        const GameConfig(
          pointsToWin: 99,
          handSize: 2,
          categories: ['One', 'Nope'],
        ),
      );
      expect(t.engine.config.pointsToWin, GameConfig.maxPoints);
      expect(t.engine.config.handSize, GameConfig.minHandSize);
      expect(t.engine.config.categories, ['One']);

      expect(
        () => t.engine.setConfig(t.host, const GameConfig(categories: ['Nope'])),
        throwsA(isA<GameError>()),
      );
      expect(
        () => t.engine.setConfig(t.ids[1], t.engine.config),
        throwsA(isA<GameError>()),
      );

      t.engine.start(t.host);
      expect(
        () => t.engine.setConfig(t.host, t.engine.config),
        throwsA(isA<GameError>()),
      );
    });

    test('refuses to start without enough answer cards', () {
      final t = _Table(
        library: DeckLibrary([
          const DeckCategory(name: 'Tiny', black: ['_____'], white: ['a', 'b']),
        ]),
      );
      expect(() => t.engine.start(t.host), throwsA(isA<GameError>()));
      expect(t.engine.started, isFalse);
    });

    test('the host can remove a player', () {
      final t = _Table();
      expect(
        () => t.engine.kick(t.ids[1], t.ids[2]),
        throwsA(isA<GameError>()),
      );
      expect(() => t.engine.kick(t.host, t.host), throwsA(isA<GameError>()));
      t.engine.kick(t.host, t.ids[3]);
      expect(t.view(t.host).players, hasLength(3));
    });
  });

  group('a round', () {
    test('starts with a Czar and full hands', () {
      final t = _Table();
      t.engine.start(t.host);
      expect(t.engine.phase, Phase.picking);
      expect(t.round.number, 1);
      expect(t.czar, t.ids[0]);
      for (final id in t.ids) {
        expect(t.view(id).you.hand, hasLength(7));
      }
      expect(t.view(t.ids[0]).you.isCzar, isTrue);
      expect(t.view(t.ids[1]).you.canPlay, isTrue);
      expect(t.view(t.ids[0]).you.canPlay, isFalse);
    });

    test('judging starts when everyone but the Czar has played', () {
      final t = _Table();
      t.engine.start(t.host);
      final others = t.others;
      for (final id in others.take(others.length - 1)) {
        t.play(id);
      }
      expect(t.engine.phase, Phase.picking);
      expect(t.round.submittedCount, others.length - 1);

      t.play(others.last);
      expect(t.engine.phase, Phase.judging);
      final judging = t.view(t.czar).round!;
      expect(judging.submissions, hasLength(others.length));
      expect(judging.submissions.every((s) => s.playerId == null), isTrue);
    });

    test('the Czar cannot play and players cannot judge', () {
      final t = _Table();
      t.engine.start(t.host);
      expect(() => t.engine.submit(t.czar, [0]), throwsA(isA<GameError>()));
      expect(() => t.engine.pickWinner(t.ids[1], 0), throwsA(isA<GameError>()));

      t.playAll();
      expect(
        () => t.engine.pickWinner(t.others.first, 0),
        throwsA(isA<GameError>()),
      );
      expect(() => t.engine.pickWinner(t.czar, 99), throwsA(isA<GameError>()));
    });

    test('cards must come from your own hand, once each', () {
      final t = _Table();
      t.engine.start(t.host);
      final bob = t.ids[1];
      final cara = t.ids[2];
      final carasCard = t.view(cara).you.hand.first.id;
      expect(() => t.engine.submit(bob, [carasCard]), throwsA(isA<GameError>()));

      t.play(bob);
      expect(() => t.play(bob), throwsA(isA<GameError>()));
      expect(t.view(bob).you.hasSubmitted, isTrue);
      expect(t.view(bob).you.canPlay, isFalse);
    });

    test('the winner scores and the authors are revealed', () {
      final t = _Table();
      t.engine.start(t.host);
      t.playAll();
      final czar = t.czar;

      t.engine.pickWinner(czar, 1);
      expect(t.engine.phase, Phase.roundEnd);

      final end = t.view(czar).round!;
      expect(end.submissions.every((s) => s.playerId != null), isTrue);
      final winner = end.submissions.singleWhere((s) => s.isWinner);
      expect(winner.id, 1);
      expect(end.winnerId, winner.playerId);
      expect(t.view(czar).playerById(winner.playerId)!.score, 1);
    });

    test('the next round rotates the Czar and refills hands', () {
      final t = _Table();
      t.engine.start(t.host);
      t.playAll();
      t.engine.pickWinner(t.czar, 0);

      expect(() => t.engine.next(t.ids[2]), throwsA(isA<GameError>()));
      t.engine.next(t.host);

      expect(t.engine.phase, Phase.picking);
      expect(t.round.number, 2);
      expect(t.czar, t.ids[1]);
      for (final id in t.ids) {
        expect(t.view(id).you.hand, hasLength(7));
      }
    });

    test('prompts with two blanks need two different cards', () {
      final t = _Table(
        library: DeckLibrary([
          DeckCategory(
            name: 'Two',
            black: ['A _____ and a _____.'],
            white: [for (var i = 0; i < 60; i++) 'W$i'],
          ),
        ]),
      );
      t.engine.start(t.host);
      final bob = t.ids[1];
      final hand = t.view(bob).you.hand;
      expect(t.view(bob).round!.pick, 2);

      expect(
        () => t.engine.submit(bob, [hand[0].id]),
        throwsA(isA<GameError>()),
      );
      expect(
        () => t.engine.submit(bob, [hand[0].id, hand[0].id]),
        throwsA(isA<GameError>()),
      );
      t.engine.submit(bob, [hand[0].id, hand[1].id]);
      expect(t.view(bob).you.submitted, [hand[0].text, hand[1].text]);
    });

    test('plays many rounds by recycling the decks', () {
      final t = _Table();
      t.engine.setConfig(
        t.host,
        t.engine.config.copyWith(pointsToWin: GameConfig.maxPoints),
      );
      t.engine.start(t.host);
      for (var round = 1; round <= 30; round++) {
        expect(t.engine.phase, Phase.picking);
        expect(t.round.number, round);
        t.playAll();
        t.engine.pickWinner(t.czar, 0);
        t.engine.next(t.host);
        for (final id in t.ids) {
          expect(t.view(id).you.hand, hasLength(7));
        }
      }
    });
  });

  group('the end of a game', () {
    test('reaching the target score ends the game, then play again resets', () {
      final t = _Table();
      t.engine.setConfig(t.host, t.engine.config.copyWith(pointsToWin: 1));
      t.engine.start(t.host);
      t.playAll();
      t.engine.pickWinner(t.czar, 0);
      expect(t.round.gameWon, isTrue);

      t.engine.next(t.host);
      expect(t.engine.phase, Phase.gameOver);
      expect(t.view(t.host).round, isNull);

      expect(() => t.engine.playAgain(t.ids[1]), throwsA(isA<GameError>()));
      t.engine.playAgain(t.host);
      expect(t.engine.phase, Phase.lobby);
      expect(t.engine.started, isFalse);
      expect(t.view(t.host).players.map((p) => p.score), everyElement(0));
    });

    test('the host can end a game in the middle of a round', () {
      final t = _Table();
      t.engine.start(t.host);
      t.play(t.ids[1]);
      t.engine.endGame(t.host);
      expect(t.engine.phase, Phase.gameOver);
    });
  });

  group('players coming and going', () {
    test('a returning player gets their seat and hand back', () {
      final t = _Table();
      t.engine.start(t.host);
      final bob = t.ids[1];
      final before = [for (final c in t.view(bob).you.hand) c.id];

      t.engine.disconnect(bob);
      expect(
        t.view(t.host).players.singleWhere((p) => p.id == bob).connected,
        isFalse,
      );

      final back = t.engine.join(name: 'Somebody else', token: t.tokens[1]);
      expect(back.playerId, bob);
      expect([for (final c in t.view(bob).you.hand) c.id], before);
      expect(t.view(t.host).players, hasLength(4));
    });

    test('a round does not wait for a player who left', () {
      final t = _Table();
      t.engine.start(t.host);
      t.engine.disconnect(t.ids[1]);
      t.play(t.ids[2]);
      t.play(t.ids[3]);
      expect(t.engine.phase, Phase.judging);
      expect(t.view(t.host).round!.submissions, hasLength(2));
    });

    test('a Czar who leaves hands the round to a new Czar', () {
      final t = _Table();
      t.engine.start(t.host);
      final oldCzar = t.czar;
      t.engine.disconnect(oldCzar);

      final v = t.view(t.ids[1]);
      expect(t.engine.phase, Phase.picking);
      expect(v.round!.czarId, isNot(oldCzar));
      expect(v.round!.number, 1);
      expect(v.notice, isNotNull);
      expect(v.you.isHost, isTrue);
    });

    test('too few players pauses the game, and it resumes with scores', () {
      final t = _Table(players: 3);
      t.engine.start(t.host);
      t.engine.disconnect(t.ids[2]);

      expect(t.engine.phase, Phase.lobby);
      expect(t.engine.started, isTrue);
      expect(t.view(t.host).notice, isNotNull);
      expect(t.view(t.host).round, isNull);

      t.engine.join(name: 'Cara', token: t.tokens[2]);
      t.engine.start(t.host);
      expect(t.engine.phase, Phase.picking);
      expect(t.round.number, 1);
    });

    test('someone who joins mid-round plays from the next round', () {
      final t = _Table(players: 3);
      t.engine.start(t.host);
      final late = t.engine.join(name: 'Late');
      final v = t.engine.viewFor(late.playerId);

      expect(v.you.hand, hasLength(7));
      expect(v.you.canPlay, isFalse);
      expect(
        () => t.engine.submit(late.playerId, [v.you.hand.first.id]),
        throwsA(isA<GameError>()),
      );

      t.playAll();
      t.engine.pickWinner(t.czar, 0);
      t.engine.next(t.host);
      expect(t.engine.viewFor(late.playerId).round!.expectedCount, 3);
    });
  });
}
