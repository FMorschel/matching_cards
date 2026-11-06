// Builds the web client and copies it into assets/web_client/, so a host
// running the native app can hand it to browsers on the network.
//
//   dart run tool/bundle_web.dart
//
// Run it from the repository root, then build the native app as usual.

import 'dart:io';

const _begin = '# <web_client>';
const _end = '# </web_client>';

Future<void> main() async {
  final bundle = Directory('assets/web_client');
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exit(64);
  }
  bundle.createSync(recursive: true);

  // Start from an empty bundle, keeping only the placeholder.
  for (final entity in bundle.listSync()) {
    if (entity.uri.pathSegments.where((s) => s.isNotEmpty).last == '.gitkeep') {
      continue;
    }
    entity.deleteSync(recursive: true);
  }
  // The bundle directory must exist as an asset while building.
  _writeAssetList(const ['assets/web_client/']);

  final build = await Process.start(
    'flutter',
    ['build', 'web', '--release', '--no-web-resources-cdn'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  if (await build.exitCode != 0) {
    stderr.writeln('flutter build web failed.');
    exit(1);
  }

  final out = Directory('build/web');
  final directories = <String>{};
  var count = 0;
  for (final entity in out.listSync(recursive: true)) {
    final relative = entity.path.substring(out.path.length + 1).replaceAll(r'\', '/');
    if (relative.split('/').any((part) => part.startsWith('.'))) continue;
    final target = '${bundle.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
      count++;
    }
  }

  for (final entity in bundle.listSync(recursive: true)) {
    if (entity is Directory) {
      directories.add('${entity.path.replaceAll(r'\', '/')}/');
    }
  }
  _writeAssetList([
    'assets/web_client/',
    ...(directories.toList()..sort()),
  ]);
  stdout.writeln('Bundled $count files into ${bundle.path}. '
      'Rebuild the native app to include them.');
}

void _writeAssetList(List<String> directories) {
  final file = File('pubspec.yaml');
  final lines = file.readAsLinesSync();
  final start = lines.indexWhere((l) => l.trim() == _begin);
  final end = lines.indexWhere((l) => l.trim() == _end);
  if (start < 0 || end < start) {
    stderr.writeln('pubspec.yaml lost its $_begin markers.');
    exit(65);
  }
  final indent = lines[start].substring(0, lines[start].indexOf('#'));
  final replaced = [
    ...lines.sublist(0, start + 1),
    for (final d in directories) '$indent- $d',
    ...lines.sublist(end),
  ];
  file.writeAsStringSync('${replaced.join('\n')}\n');
}
