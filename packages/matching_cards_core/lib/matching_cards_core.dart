/// Platform-independent part of Matching Cards: decks, rules and wire protocol.
///
/// Safe to import from Flutter web. The `dart:io` pieces (server, discovery)
/// live in `package:matching_cards_core/server.dart`.
library;

export 'src/deck.dart';
export 'src/game_engine.dart';
export 'src/protocol.dart';
