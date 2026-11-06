import 'dart:math';

import 'deck.dart';
import 'protocol.dart';

/// Thrown for actions the rules do not allow. The message is safe to show to
/// the player who tried.
class GameError implements Exception {
  GameError(this.message);

  final String message;

  @override
  String toString() => 'GameError: $message';
}

/// What a player needs to remember to come back to the same seat.
class JoinResult {
  const JoinResult({required this.playerId, required this.token});

  final String playerId;
  final String token;
}

class _Player {
  _Player({required this.id, required this.token, required this.name});

  final String id;
  final String token;
  String name;
  int score = 0;
  bool connected = true;
  final List<int> hand = [];
}

class _Submission {
  _Submission(this.playerId, this.cardIds);

  final String playerId;
  final List<int> cardIds;
}

/// The rules of the game, with no networking.
///
/// Players take turns being the Card Czar. Everybody else answers the Czar's
/// prompt with cards from their hand, the Czar picks the best answer without
/// knowing who wrote it, and that player scores a point. The first player to
/// reach the target score wins.
///
/// Every public action takes the id of the player doing it and throws a
/// [GameError] when it is not allowed. Call [viewFor] to get what a player may
/// see after any change.
class GameEngine {
  GameEngine({
    required this.library,
    this.gameName = 'Matching Cards',
    this.minPlayers = 3,
    Random? random,
  })  : _random = random ?? Random(),
        _config = GameConfig(categories: library.names);

  final DeckLibrary library;
  final String gameName;

  /// Fewest connected players a round can be played with.
  final int minPlayers;

  final Random _random;
  final Random _secure = Random.secure();

  GameConfig _config;
  Phase _phase = Phase.lobby;
  bool _started = false;
  final List<_Player> _players = [];
  int _nextPlayerNumber = 1;
  String? _hostId;
  String? _notice;

  // Decks of the running game. Card ids are indexes into these lists.
  List<String> _white = [];
  List<String> _black = [];
  List<int> _whiteDraw = [];
  List<int> _whiteDiscard = [];
  List<int> _blackDraw = [];
  List<int> _blackDiscard = [];

  // The current round.
  int _roundNumber = 0;
  int _czarCursor = -1;
  String? _czarId;
  int _blackCard = -1;
  final Set<String> _participants = {};
  final List<_Submission> _submissions = [];
  int _winningSubmission = -1;
  String? _winnerId;
  bool _gameWon = false;

  Phase get phase => _phase;
  GameConfig get config => _config;
  bool get started => _started;

  /// How many players are connected right now.
  int get connectedCount => _players.where((p) => p.connected).length;

  // ---------------------------------------------------------------------------
  // Joining and leaving

  /// Seats a new player, or reconnects the one that owns [token].
  JoinResult join({required String name, String? token}) {
    if (token != null) {
      final existing = _playerByToken(token);
      if (existing != null) {
        existing.connected = true;
        _afterMembershipChange();
        return JoinResult(playerId: existing.id, token: existing.token);
      }
    }
    final player = _Player(
      id: 'p${_nextPlayerNumber++}',
      token: _newToken(),
      name: _uniqueName(name),
    );
    _players.add(player);
    if (_started && _isRoundInProgress) {
      _refillHand(player);
    }
    _afterMembershipChange();
    return JoinResult(playerId: player.id, token: player.token);
  }

  /// Marks a player as gone. Before a game starts the seat is simply freed;
  /// during a game it is kept so the player can come back with their token.
  void disconnect(String playerId) {
    final player = _playerOrNull(playerId);
    if (player == null) return;
    if (_started) {
      player.connected = false;
    } else {
      _removePlayer(player);
    }
    _afterMembershipChange();
  }

  /// Removes a player for good. Host only.
  void kick(String hostId, String targetId) {
    _clearNotice();
    _requireHost(hostId);
    if (targetId == hostId) throw GameError('You cannot remove yourself.');
    final target = _playerOrNull(targetId);
    if (target == null) throw GameError('That player is not here.');
    _removePlayer(target);
    _afterMembershipChange();
  }

  // ---------------------------------------------------------------------------
  // Host actions

  /// Changes the settings. Host only, and only before the game starts.
  void setConfig(String playerId, GameConfig requested) {
    _clearNotice();
    _requireHost(playerId);
    if (_started || _phase != Phase.lobby) {
      throw GameError('Settings can only change before the game starts.');
    }
    final known = library.names.toSet();
    final categories = [
      for (final name in requested.categories)
        if (known.contains(name)) name,
    ].toSet().toList();
    if (categories.isEmpty) throw GameError('Pick at least one deck.');
    _config = GameConfig(
      pointsToWin: _clamp(
        requested.pointsToWin,
        GameConfig.minPoints,
        GameConfig.maxPoints,
      ),
      handSize: _clamp(
        requested.handSize,
        GameConfig.minHandSize,
        GameConfig.maxHandSize,
      ),
      categories: categories,
    );
  }

  /// Starts the game, or resumes one that was paused. Host only.
  void start(String playerId) {
    _clearNotice();
    _requireHost(playerId);
    if (_phase != Phase.lobby) throw GameError('The game is already running.');
    if (connectedCount < minPlayers) {
      throw GameError('At least $minPlayers players must be connected.');
    }
    if (!_started) _setupGame();
    _startRound();
  }

  /// Ends the running game and shows the final scores. Host only.
  void endGame(String playerId) {
    _clearNotice();
    _requireHost(playerId);
    if (!_started) throw GameError('There is no game to end.');
    if (_phase == Phase.picking || _phase == Phase.judging) _voidRound();
    _phase = Phase.gameOver;
  }

  /// Returns to the lobby with fresh scores. Host only, after a game.
  void playAgain(String playerId) {
    _clearNotice();
    _requireHost(playerId);
    if (_phase != Phase.gameOver) throw GameError('The game is not over.');
    _players.removeWhere((p) => !p.connected);
    for (final player in _players) {
      player.score = 0;
      player.hand.clear();
    }
    _started = false;
    _phase = Phase.lobby;
    _ensureHost();
  }

  // ---------------------------------------------------------------------------
  // Playing

  /// Plays cards from your hand as your answer. Pass one card per blank, in
  /// blank order.
  void submit(String playerId, List<int> cardIds) {
    _clearNotice();
    final player = _requirePlayer(playerId);
    if (_phase != Phase.picking) {
      throw GameError('It is not time to choose answers.');
    }
    if (playerId == _czarId) {
      throw GameError('The Card Czar does not play answers.');
    }
    if (!_participants.contains(playerId)) {
      throw GameError('You will join in on the next round.');
    }
    if (_hasSubmitted(playerId)) {
      throw GameError('You already played this round.');
    }
    final pick = pickCount(_black[_blackCard]);
    if (cardIds.length != pick) {
      throw GameError(pick == 1 ? 'Pick one card.' : 'Pick exactly $pick cards.');
    }
    if (cardIds.toSet().length != cardIds.length) {
      throw GameError('Pick different cards.');
    }
    for (final id in cardIds) {
      if (!player.hand.contains(id)) {
        throw GameError('That card is not in your hand.');
      }
    }
    player.hand.removeWhere((id) => cardIds.contains(id));
    _submissions.add(_Submission(playerId, List<int>.of(cardIds)));
    _checkPickingComplete();
  }

  /// The Card Czar chooses the winning submission (by [SubmissionView.id]).
  void pickWinner(String playerId, int submissionId) {
    _clearNotice();
    _requirePlayer(playerId);
    if (_phase != Phase.judging) throw GameError('There is nothing to judge.');
    if (playerId != _czarId) {
      throw GameError('Only the Card Czar picks the winner.');
    }
    if (submissionId < 0 || submissionId >= _submissions.length) {
      throw GameError('That answer does not exist.');
    }
    final winner = _playerOrNull(_submissions[submissionId].playerId);
    _winningSubmission = submissionId;
    _winnerId = winner?.id;
    if (winner != null) {
      winner.score += 1;
      _gameWon = winner.score >= _config.pointsToWin;
    }
    _phase = Phase.roundEnd;
  }

  /// Moves on after a round. Host or Card Czar.
  void next(String playerId) {
    _clearNotice();
    _requirePlayer(playerId);
    if (_phase != Phase.roundEnd) throw GameError('The round is not over yet.');
    if (playerId != _hostId && playerId != _czarId) {
      throw GameError('Only the host or the Card Czar can continue.');
    }
    if (_gameWon) {
      _phase = Phase.gameOver;
      return;
    }
    if (connectedCount < minPlayers) {
      _pause('Waiting for more players.');
      return;
    }
    _startRound();
  }

  // ---------------------------------------------------------------------------
  // Views

  /// What [playerId] is allowed to see right now.
  GameView viewFor(String playerId) {
    final me = _requirePlayer(playerId);
    final inRound = _isRoundInProgress;
    final mine = _submissionOf(me.id);
    return GameView(
      gameName: gameName,
      phase: _phase,
      started: _started,
      minPlayers: minPlayers,
      notice: _notice,
      config: _config,
      decks: _phase == Phase.lobby && !_started
          ? [
              for (final c in library.categories)
                DeckInfo(
                  name: c.name,
                  blackCount: c.black.length,
                  whiteCount: c.white.length,
                ),
            ]
          : const [],
      you: YouView(
        id: me.id,
        name: me.name,
        isHost: me.id == _hostId,
        isCzar: inRound && me.id == _czarId,
        hand: [for (final id in me.hand) CardView(id: id, text: _white[id])],
        hasSubmitted: mine != null,
        submitted: mine == null
            ? const []
            : [for (final id in mine.cardIds) _white[id]],
        canPlay: _phase == Phase.picking &&
            me.id != _czarId &&
            _participants.contains(me.id) &&
            mine == null,
      ),
      players: [
        for (final p in _players)
          PlayerView(
            id: p.id,
            name: p.name,
            score: p.score,
            connected: p.connected,
            isHost: p.id == _hostId,
            isCzar: inRound && p.id == _czarId,
            hasSubmitted: _hasSubmitted(p.id),
          ),
      ],
      round: inRound ? _roundView() : null,
    );
  }

  RoundView _roundView() {
    final over = _phase == Phase.roundEnd;
    final showAnswers = over || _phase == Phase.judging;
    final prompt = _black[_blackCard];
    return RoundView(
      number: _roundNumber,
      czarId: _czarId ?? '',
      prompt: prompt,
      pick: pickCount(prompt),
      submittedCount: _submissions.length,
      expectedCount: _participants.where((id) {
        final p = _playerOrNull(id);
        return p != null && (p.connected || _hasSubmitted(id));
      }).length,
      submissions: showAnswers
          ? [
              for (var i = 0; i < _submissions.length; i++)
                SubmissionView(
                  id: i,
                  answers: [for (final c in _submissions[i].cardIds) _white[c]],
                  playerId: over ? _submissions[i].playerId : null,
                  isWinner: over && i == _winningSubmission,
                ),
            ]
          : const [],
      winnerId: over ? _winnerId : null,
      gameWon: over && _gameWon,
    );
  }

  // ---------------------------------------------------------------------------
  // Round flow

  bool get _isRoundInProgress =>
      _phase == Phase.picking ||
      _phase == Phase.judging ||
      _phase == Phase.roundEnd;

  void _setupGame() {
    final pool = library.pool(_config.categories);
    final players = connectedCount;
    final needed = players * (_config.handSize + 3);
    if (pool.black.isEmpty) {
      throw GameError('The chosen decks have no prompts.');
    }
    if (pool.white.length < needed) {
      throw GameError(
        'Not enough answer cards for $players players. '
        'Choose more decks or lower the hand size.',
      );
    }
    _black = pool.black;
    _white = pool.white;
    _blackDraw = List<int>.generate(_black.length, (i) => i)..shuffle(_random);
    _whiteDraw = List<int>.generate(_white.length, (i) => i)..shuffle(_random);
    _blackDiscard = [];
    _whiteDiscard = [];
    for (final player in _players) {
      player.score = 0;
      player.hand.clear();
    }
    _roundNumber = 0;
    _czarCursor = -1;
    _czarId = null;
    _blackCard = -1;
    _participants.clear();
    _submissions.clear();
    _started = true;
  }

  void _startRound() {
    // Recycle the previous round's cards.
    for (final s in _submissions) {
      _whiteDiscard.addAll(s.cardIds);
    }
    _submissions.clear();
    if (_blackCard >= 0) _blackDiscard.add(_blackCard);

    _winnerId = null;
    _winningSubmission = -1;
    _gameWon = false;
    _roundNumber++;
    _czarId = _nextCzar();

    for (final p in _players) {
      if (p.connected) _refillHand(p);
    }
    _participants
      ..clear()
      ..addAll([
        for (final p in _players)
          if (p.connected && p.id != _czarId) p.id,
      ]);
    _blackCard = _drawBlack();
    _phase = Phase.picking;
  }

  /// Gives the cards of a cancelled round back to their owners.
  void _voidRound() {
    for (final s in _submissions) {
      final owner = _playerOrNull(s.playerId);
      if (owner != null) {
        owner.hand.addAll(s.cardIds);
      } else {
        _whiteDiscard.addAll(s.cardIds);
      }
    }
    _submissions.clear();
    if (_blackCard >= 0) {
      _blackDiscard.add(_blackCard);
      _blackCard = -1;
    }
    _participants.clear();
    _czarId = null;
    _winnerId = null;
    _winningSubmission = -1;
    _gameWon = false;
    if (_roundNumber > 0) _roundNumber--;
  }

  /// Back to the lobby with scores kept, until enough players return.
  void _pause(String message) {
    _phase = Phase.lobby;
    _notice = message;
  }

  void _checkPickingComplete() {
    if (_phase != Phase.picking) return;
    final stillWaiting = _participants.any((id) {
      final p = _playerOrNull(id);
      return p != null && p.connected && !_hasSubmitted(id);
    });
    if (stillWaiting) return;
    if (_submissions.isEmpty) {
      // Everybody who was meant to play left; start over with whoever is here.
      _voidRound();
      _notice = 'Nobody was left to answer, so the round started over.';
      _startRound();
      return;
    }
    _submissions.shuffle(_random);
    _phase = Phase.judging;
  }

  void _afterMembershipChange() {
    _ensureHost();
    if (!_started) return;
    if (_phase != Phase.picking && _phase != Phase.judging) return;
    if (connectedCount < minPlayers) {
      _voidRound();
      _pause('Too few players are connected, so the round was cancelled.');
      return;
    }
    final czar = _playerOrNull(_czarId);
    if (czar == null || !czar.connected) {
      _voidRound();
      _startRound();
      _notice = 'The Card Czar left, so the round started over.';
      return;
    }
    _checkPickingComplete();
  }

  String _nextCzar() {
    final count = _players.length;
    for (var step = 1; step <= count; step++) {
      final index = (_czarCursor + step) % count;
      if (_players[index].connected) {
        _czarCursor = index;
        return _players[index].id;
      }
    }
    throw StateError('No connected player can be the Card Czar.');
  }

  // ---------------------------------------------------------------------------
  // Cards

  int _drawBlack() {
    if (_blackDraw.isEmpty) {
      _blackDraw = _blackDiscard..shuffle(_random);
      _blackDiscard = [];
    }
    return _blackDraw.removeLast();
  }

  int? _drawWhite() {
    if (_whiteDraw.isEmpty) {
      _whiteDraw = _whiteDiscard..shuffle(_random);
      _whiteDiscard = [];
    }
    return _whiteDraw.isEmpty ? null : _whiteDraw.removeLast();
  }

  void _refillHand(_Player player) {
    while (player.hand.length < _config.handSize) {
      final card = _drawWhite();
      if (card == null) return;
      player.hand.add(card);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers

  void _clearNotice() => _notice = null;

  _Player? _playerOrNull(String? id) {
    if (id == null) return null;
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }

  _Player? _playerByToken(String token) {
    for (final p in _players) {
      if (p.token == token) return p;
    }
    return null;
  }

  _Player _requirePlayer(String id) {
    final player = _playerOrNull(id);
    if (player == null) throw GameError('You are not in this game.');
    return player;
  }

  void _requireHost(String id) {
    _requirePlayer(id);
    if (id != _hostId) throw GameError('Only the host can do that.');
  }

  _Submission? _submissionOf(String playerId) {
    for (final s in _submissions) {
      if (s.playerId == playerId) return s;
    }
    return null;
  }

  bool _hasSubmitted(String playerId) => _submissionOf(playerId) != null;

  /// Makes sure the host seat belongs to somebody who is still connected.
  void _ensureHost() {
    final current = _playerOrNull(_hostId);
    if (current != null && current.connected) return;
    for (final p in _players) {
      if (p.connected) {
        _hostId = p.id;
        return;
      }
    }
  }

  void _removePlayer(_Player player) {
    final index = _players.indexOf(player);
    if (index < 0) return;
    _players.removeAt(index);
    if (_czarCursor >= 0 && index <= _czarCursor) _czarCursor -= 1;
    _participants.remove(player.id);
    if (_phase == Phase.picking) {
      // Judging and results refer to submissions by position, so those are
      // only dropped while players are still choosing.
      final mine = _submissionOf(player.id);
      if (mine != null) {
        _whiteDiscard.addAll(mine.cardIds);
        _submissions.remove(mine);
      }
    }
    _whiteDiscard.addAll(player.hand);
    if (_hostId == player.id) _hostId = null;
  }

  String _uniqueName(String raw) {
    var base = raw.trim();
    if (base.length > 20) base = base.substring(0, 20);
    if (base.isEmpty) base = 'Player';
    bool taken(String candidate) => _players.any(
          (p) => p.name.toLowerCase() == candidate.toLowerCase(),
        );
    var candidate = base;
    var n = 2;
    while (taken(candidate)) {
      candidate = '$base ($n)';
      n++;
    }
    return candidate;
  }

  String _newToken() {
    final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int _clamp(int value, int low, int high) =>
      value < low ? low : (value > high ? high : value);
}
