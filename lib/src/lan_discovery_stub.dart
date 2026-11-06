import 'package:matching_cards_core/matching_cards_core.dart';

/// Browsers cannot receive UDP broadcasts, so there is nothing to scan.
const bool lanScanSupported = false;

Stream<List<DiscoveredGame>> findLanGames() => const Stream.empty();
