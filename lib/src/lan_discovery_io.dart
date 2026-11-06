import 'dart:async';
import 'dart:io';

import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:matching_cards_core/server.dart';

const bool lanScanSupported = true;

/// Games announced on the local network, as a live list. Cancelling the
/// subscription stops listening. Emits an empty list when listening is not
/// possible.
Stream<List<DiscoveredGame>> findLanGames() {
  final scanner = LanScanner();
  late StreamController<List<DiscoveredGame>> controller;
  StreamSubscription<List<DiscoveredGame>>? subscription;
  controller = StreamController<List<DiscoveredGame>>(
    onListen: () async {
      controller.add(const []);
      try {
        await scanner.start();
        subscription = scanner.games.listen(controller.add);
      } on SocketException {
        // The port is blocked; typed addresses still work.
      }
    },
    onCancel: () async {
      await subscription?.cancel();
      await scanner.stop();
    },
  );
  return controller.stream;
}
