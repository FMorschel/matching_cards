import 'dart:io';

/// A file the host can hand to a browser.
class StaticFile {
  const StaticFile(this.bytes, this.contentType);

  final List<int> bytes;
  final String contentType;
}

/// Where a host gets the web client from (a folder, or the app's own assets).
abstract class StaticSource {
  /// Returns the file at [segments], or null when there is none.
  ///
  /// [segments] are already URL-decoded and never contain `..`, separators or
  /// empty parts, so implementations can join them safely.
  Future<StaticFile?> read(List<String> segments);
}

/// Serves files from a folder on disk, such as Flutter's `build/web`.
class DirectoryStaticSource implements StaticSource {
  DirectoryStaticSource(this.root);

  final Directory root;

  @override
  Future<StaticFile?> read(List<String> segments) async {
    final path = [root.path, ...segments].join(Platform.pathSeparator);
    final file = File(path);
    if (!await file.exists()) return null;
    return StaticFile(await file.readAsBytes(), contentTypeFor(segments.last));
  }
}

/// A best-effort MIME type from a file name.
String contentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (extension) {
    case 'html':
      return 'text/html; charset=utf-8';
    case 'js':
    case 'mjs':
      return 'text/javascript; charset=utf-8';
    case 'css':
      return 'text/css; charset=utf-8';
    case 'json':
      return 'application/json; charset=utf-8';
    case 'wasm':
      return 'application/wasm';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    case 'ico':
      return 'image/x-icon';
    case 'txt':
      return 'text/plain; charset=utf-8';
    case 'ttf':
      return 'font/ttf';
    case 'otf':
      return 'font/otf';
    case 'woff':
      return 'font/woff';
    case 'woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}
