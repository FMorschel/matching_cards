// A headless Matching Cards host, for a spare PC or a Raspberry Pi.
//
//   dart run bin/server.dart --web ../../build/web
//
// The first player to join becomes the host and starts the game from their
// own screen. Players on the network find the game in the app's Join screen
// (it is announced by UDP broadcast) or open http://<this machine>:8080 in a
// browser when a web build is supplied with --web.

import 'dart:io';

import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:matching_cards_core/server.dart';

const _usage = '''
Usage: dart run bin/server.dart [options]

  --port <n>       Port to listen on (default $defaultGamePort)
  --name <text>    Name shown to players (default "Matching Cards")
  --decks <file>   A deck JSON file; repeat for several
                   (default: assets/decks/cards.json of this repository)
  --web <dir>      A Flutter web build to hand to browsers (build/web)
  --help           Show this text
''';

Future<void> main(List<String> args) async {
  var port = defaultGamePort;
  var name = 'Matching Cards';
  final deckPaths = <String>[];
  String? webDir;

  var index = 0;
  String valueOf(String option) {
    if (index >= args.length) {
      stderr.writeln('Missing value for $option\n\n$_usage');
      exit(64);
    }
    return args[index++];
  }

  while (index < args.length) {
    final arg = args[index++];
    switch (arg) {
      case '--help':
      case '-h':
        stdout.write(_usage);
        return;
      case '--port':
        final parsed = int.tryParse(valueOf(arg));
        if (parsed == null || parsed < 0 || parsed > 65535) {
          stderr.writeln('--port needs a number from 0 to 65535.');
          exit(64);
        }
        port = parsed;
      case '--name':
        name = valueOf(arg);
      case '--decks':
        deckPaths.add(valueOf(arg));
      case '--web':
        webDir = valueOf(arg);
      default:
        stderr.writeln('Unknown option: $arg\n\n$_usage');
        exit(64);
    }
  }

  if (deckPaths.isEmpty) {
    final found = _firstExisting([
      'assets/decks/cards.json',
      '../../assets/decks/cards.json',
    ]);
    if (found == null) {
      stderr.writeln('Could not find the decks. Pass --decks <file>.');
      exit(66);
    }
    deckPaths.add(found);
  }

  final library = _loadLibrary(deckPaths);

  StaticSource? source;
  final webPath = webDir;
  if (webPath != null) {
    final dir = Directory(webPath);
    if (!dir.existsSync()) {
      stderr.writeln('Web directory not found: $webPath');
      exit(66);
    }
    source = DirectoryStaticSource(dir);
  }

  final engine = GameEngine(library: library, gameName: name);
  final server = LanServer(
    engine: engine,
    staticSource: source,
    acceptRemote: true,
  );
  try {
    await server.start(port: port);
  } on SocketException catch (error) {
    stderr.writeln('Cannot listen on port $port: ${error.message}');
    exit(73);
  }

  final advertiser = LanAdvertiser(
    port: server.port,
    nameOf: () => engine.gameName,
    playersOf: () => engine.connectedCount,
  );
  try {
    await advertiser.start();
  } on SocketException catch (error) {
    stderr.writeln('Not announcing on the network: ${error.message}');
  }

  stdout.writeln('"$name" is running on port ${server.port}.');
  for (final address in await localIPv4Addresses()) {
    stdout.writeln('  http://$address:${server.port}');
  }
  if (source == null) {
    stdout.writeln('No --web build given: only the app can join.');
  }
  stdout.writeln('Press Ctrl+C to stop.');

  await ProcessSignal.sigint.watch().first;
  stdout.writeln('Stopping.');
  await advertiser.stop();
  await server.stop();
}

DeckLibrary _loadLibrary(List<String> paths) {
  try {
    return DeckLibrary.fromJsonStrings([
      for (final path in paths) File(path).readAsStringSync(),
    ]);
  } on FormatException catch (error) {
    stderr.writeln('Bad deck file: ${error.message}');
    exit(65);
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot read decks: ${error.message} (${error.path})');
    exit(66);
  }
}

String? _firstExisting(List<String> paths) {
  for (final path in paths) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
