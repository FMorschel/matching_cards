/// Messages and view models exchanged between a host and its players.
///
/// The host is authoritative. A client sends small action messages and the
/// host answers every change with a full, per-player [GameView], so a client
/// never has to track game state itself and never sees hidden information
/// (other hands, or who wrote which answer while the Czar is still judging).
///
/// Client to host, all JSON objects with a `t` (type) field:
///
/// * `join`    `name`, optional `token` (to resume a seat after a drop)
/// * `config`  `config` (host, lobby only)
/// * `start`   (host)
/// * `submit`  `cards`: card ids from your hand, in blank order
/// * `pick`    `submission`: id of the winning submission (Card Czar)
/// * `next`    (host or Card Czar, after a round)
/// * `end`     (host) ends the running game
/// * `again`   (host) back to the lobby after a game
/// * `kick`    `player`: id to remove (host)
///
/// Host to client:
///
/// * `welcome` `playerId`, `token`, `protocol`
/// * `state`   a [GameView], flattened into the message
/// * `error`   `message`
library;

/// Bumped whenever the messages change in an incompatible way.
const int protocolVersion = 1;

/// The port a host tries first.
const int defaultGamePort = 8080;

/// Path of the WebSocket endpoint on a host.
const String webSocketPath = '/ws';

/// Where a game currently stands.
enum Phase {
  /// Before the first round, or paused because too few players are connected.
  lobby,

  /// Players choose their answers.
  picking,

  /// The Card Czar reads the anonymous answers.
  judging,

  /// The winner of the round is shown.
  roundEnd,

  /// Someone reached the target score, or the host ended the game.
  gameOver,
}

Phase _phaseFrom(Object? name) {
  for (final phase in Phase.values) {
    if (phase.name == name) return phase;
  }
  return Phase.lobby;
}

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

List<Map<String, dynamic>> _objects(Object? value) =>
    value is List ? [for (final e in value) e as Map<String, dynamic>] : [];

/// Settings the host chooses before the game starts.
class GameConfig {
  const GameConfig({
    this.pointsToWin = 5,
    this.handSize = 7,
    this.categories = const [],
  });

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig(
        pointsToWin: (json['pointsToWin'] as num?)?.toInt() ?? 5,
        handSize: (json['handSize'] as num?)?.toInt() ?? 7,
        categories: _strings(json['categories']),
      );

  static const int minPoints = 1;
  static const int maxPoints = 20;
  static const int minHandSize = 5;
  static const int maxHandSize = 12;

  final int pointsToWin;
  final int handSize;

  /// Names of the deck categories in play.
  final List<String> categories;

  GameConfig copyWith({
    int? pointsToWin,
    int? handSize,
    List<String>? categories,
  }) =>
      GameConfig(
        pointsToWin: pointsToWin ?? this.pointsToWin,
        handSize: handSize ?? this.handSize,
        categories: categories ?? this.categories,
      );

  Map<String, Object?> toJson() => {
        'pointsToWin': pointsToWin,
        'handSize': handSize,
        'categories': categories,
      };
}

/// A deck category as offered in the lobby.
class DeckInfo {
  const DeckInfo({
    required this.name,
    required this.blackCount,
    required this.whiteCount,
  });

  factory DeckInfo.fromJson(Map<String, dynamic> json) => DeckInfo(
        name: json['name'] as String,
        blackCount: (json['black'] as num).toInt(),
        whiteCount: (json['white'] as num).toInt(),
      );

  final String name;
  final int blackCount;
  final int whiteCount;

  Map<String, Object?> toJson() =>
      {'name': name, 'black': blackCount, 'white': whiteCount};
}

/// An answer card in somebody's hand.
class CardView {
  const CardView({required this.id, required this.text});

  factory CardView.fromJson(Map<String, dynamic> json) =>
      CardView(id: (json['id'] as num).toInt(), text: json['text'] as String);

  final int id;
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

/// One seat at the table, as everybody sees it.
class PlayerView {
  const PlayerView({
    required this.id,
    required this.name,
    required this.score,
    required this.connected,
    required this.isHost,
    required this.isCzar,
    required this.hasSubmitted,
  });

  factory PlayerView.fromJson(Map<String, dynamic> json) => PlayerView(
        id: json['id'] as String,
        name: json['name'] as String,
        score: (json['score'] as num).toInt(),
        connected: json['connected'] as bool,
        isHost: json['isHost'] as bool,
        isCzar: json['isCzar'] as bool,
        hasSubmitted: json['hasSubmitted'] as bool,
      );

  final String id;
  final String name;
  final int score;
  final bool connected;
  final bool isHost;
  final bool isCzar;
  final bool hasSubmitted;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'score': score,
        'connected': connected,
        'isHost': isHost,
        'isCzar': isCzar,
        'hasSubmitted': hasSubmitted,
      };
}

/// The private part of the view: your own seat and hand.
class YouView {
  const YouView({
    required this.id,
    required this.name,
    required this.isHost,
    required this.isCzar,
    required this.hand,
    required this.hasSubmitted,
    required this.submitted,
    required this.canPlay,
  });

  factory YouView.fromJson(Map<String, dynamic> json) => YouView(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        isCzar: json['isCzar'] as bool,
        hand: [for (final c in _objects(json['hand'])) CardView.fromJson(c)],
        hasSubmitted: json['hasSubmitted'] as bool,
        submitted: _strings(json['submitted']),
        canPlay: json['canPlay'] as bool,
      );

  final String id;
  final String name;
  final bool isHost;
  final bool isCzar;
  final List<CardView> hand;
  final bool hasSubmitted;

  /// The answers you played this round, in blank order.
  final List<String> submitted;

  /// True while it is your turn to choose answers.
  final bool canPlay;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
        'isCzar': isCzar,
        'hand': [for (final c in hand) c.toJson()],
        'hasSubmitted': hasSubmitted,
        'submitted': submitted,
        'canPlay': canPlay,
      };
}

/// One played answer (or set of answers, for prompts with several blanks).
class SubmissionView {
  const SubmissionView({
    required this.id,
    required this.answers,
    this.playerId,
    this.isWinner = false,
  });

  factory SubmissionView.fromJson(Map<String, dynamic> json) => SubmissionView(
        id: (json['id'] as num).toInt(),
        answers: _strings(json['answers']),
        playerId: json['playerId'] as String?,
        isWinner: json['isWinner'] as bool? ?? false,
      );

  /// What to send back in a `pick` message.
  final int id;

  /// Answer texts, in blank order.
  final List<String> answers;

  /// Who wrote it. Only revealed once the round is over.
  final String? playerId;

  final bool isWinner;

  Map<String, Object?> toJson() => {
        'id': id,
        'answers': answers,
        'playerId': playerId,
        'isWinner': isWinner,
      };
}

/// The round in progress (or just finished).
class RoundView {
  const RoundView({
    required this.number,
    required this.czarId,
    required this.prompt,
    required this.pick,
    required this.submittedCount,
    required this.expectedCount,
    required this.submissions,
    this.winnerId,
    this.gameWon = false,
  });

  factory RoundView.fromJson(Map<String, dynamic> json) => RoundView(
        number: (json['number'] as num).toInt(),
        czarId: json['czarId'] as String,
        prompt: json['prompt'] as String,
        pick: (json['pick'] as num).toInt(),
        submittedCount: (json['submittedCount'] as num).toInt(),
        expectedCount: (json['expectedCount'] as num).toInt(),
        submissions: [
          for (final s in _objects(json['submissions']))
            SubmissionView.fromJson(s),
        ],
        winnerId: json['winnerId'] as String?,
        gameWon: json['gameWon'] as bool? ?? false,
      );

  final int number;
  final String czarId;

  /// The prompt text, with `_____` where answers go.
  final String prompt;

  /// How many answer cards each player must play.
  final int pick;

  final int submittedCount;
  final int expectedCount;

  /// Empty while players are still choosing; shuffled and anonymous while
  /// judging; with authors revealed once the round is over.
  final List<SubmissionView> submissions;

  final String? winnerId;

  /// True when this round's winner has reached the target score.
  final bool gameWon;

  SubmissionView? get winningSubmission {
    for (final s in submissions) {
      if (s.isWinner) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'number': number,
        'czarId': czarId,
        'prompt': prompt,
        'pick': pick,
        'submittedCount': submittedCount,
        'expectedCount': expectedCount,
        'submissions': [for (final s in submissions) s.toJson()],
        'winnerId': winnerId,
        'gameWon': gameWon,
      };
}

/// Everything one player is allowed to know about the game right now.
class GameView {
  const GameView({
    required this.gameName,
    required this.phase,
    required this.started,
    required this.minPlayers,
    required this.config,
    required this.decks,
    required this.you,
    required this.players,
    this.round,
    this.notice,
  });

  factory GameView.fromJson(Map<String, dynamic> json) => GameView(
        gameName: json['gameName'] as String,
        phase: _phaseFrom(json['phase']),
        started: json['started'] as bool,
        minPlayers: (json['minPlayers'] as num).toInt(),
        config: GameConfig.fromJson(json['config'] as Map<String, dynamic>),
        decks: [for (final d in _objects(json['decks'])) DeckInfo.fromJson(d)],
        you: YouView.fromJson(json['you'] as Map<String, dynamic>),
        players: [
          for (final p in _objects(json['players'])) PlayerView.fromJson(p),
        ],
        round: json['round'] == null
            ? null
            : RoundView.fromJson(json['round'] as Map<String, dynamic>),
        notice: json['notice'] as String?,
      );

  final String gameName;
  final Phase phase;

  /// True once a game has begun. A lobby with `started` set is a paused game.
  final bool started;

  final int minPlayers;
  final GameConfig config;

  /// Categories the host can pick from. Only sent before a game starts.
  final List<DeckInfo> decks;

  final YouView you;
  final List<PlayerView> players;

  /// Present while a round is being played or shown.
  final RoundView? round;

  /// A short message about something that just happened, such as a cancelled
  /// round.
  final String? notice;

  int get connectedCount => players.where((p) => p.connected).length;

  PlayerView? playerById(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'gameName': gameName,
        'phase': phase.name,
        'started': started,
        'minPlayers': minPlayers,
        'config': config.toJson(),
        'decks': [for (final d in decks) d.toJson()],
        'you': you.toJson(),
        'players': [for (final p in players) p.toJson()],
        'round': round?.toJson(),
        'notice': notice,
      };
}

/// A game found on the local network.
class DiscoveredGame {
  const DiscoveredGame({
    required this.name,
    required this.host,
    required this.port,
    required this.players,
  });

  final String name;
  final String host;
  final int port;
  final int players;

  /// Where a native client connects.
  Uri get webSocketUri =>
      Uri(scheme: 'ws', host: host, port: port, path: webSocketPath);

  /// Where a browser can load the web client from.
  Uri get webUri => Uri(scheme: 'http', host: host, port: port);

  @override
  bool operator ==(Object other) =>
      other is DiscoveredGame && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Turns what a person typed (`192.168.1.20`, `192.168.1.20:8080`,
/// `http://host:8080/`, ...) into the WebSocket address of a host.
///
/// Returns null when the text is not an address.
Uri? parseGameAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'ws://$text';
  final parsed = Uri.tryParse(text);
  if (parsed == null || parsed.host.isEmpty) return null;
  final String scheme;
  switch (parsed.scheme) {
    case 'http':
    case 'ws':
      scheme = 'ws';
    case 'https':
    case 'wss':
      scheme = 'wss';
    default:
      return null;
  }
  final port = parsed.hasPort
      ? parsed.port
      : (scheme == 'wss' ? 443 : defaultGamePort);
  return Uri(scheme: scheme, host: parsed.host, port: port, path: webSocketPath);
}
