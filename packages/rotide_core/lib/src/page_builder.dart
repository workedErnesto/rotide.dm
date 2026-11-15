import 'dart:convert';
import 'dart:io';

import 'markdown_renderer.dart' show Html;

enum PageTheme { auto, light }

/// The HTML page around a rendered body: the live preview, the HTML export and the page printed to PDF.
abstract final class PageBuilder {
  /// No script of the document runs: the preview drives the page from its own isolated script world, which a content
  /// security policy does not reach. Images and media may come from anywhere, as on GitHub.
  static const policy = "default-src 'none'; img-src * data: blob: rotide-local:; media-src * data: rotide-local:; "
      "style-src 'unsafe-inline'; font-src data:";

  static String page({
    required String title,
    required String body,
    required String css,
    PageTheme theme = PageTheme.auto,
    bool lockedDown = true,
  }) {
    final light = theme == PageTheme.light;
    return '''
<!doctype html>
<html lang="ru"${light ? ' data-theme="light"' : ''}>
<head>
<meta charset="utf-8">
${lockedDown ? '<meta http-equiv="Content-Security-Policy" content="$policy">' : ''}
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="${light ? 'light' : 'light dark'}">
<title>${Html.escape(title)}</title>
<style>
$css
</style>
</head>
<body>
<article class="markdown-body" id="content">
$body
</article>
</body>
</html>''';
  }

  static final _media = RegExp(r'''(<(?:img|source|video|audio)\b[^>]*?\bsrc\s*=\s*)(["'])([^"']+)\2''', caseSensitive: false);

  /// Replaces `src` of images and media that point to local files with `data:` URLs, so an exported page keeps its
  /// pictures wherever it is saved. Remote addresses, missing files and files over [limit] stay as they are.
  static String inlineLocalMedia(String html, String? baseDirectory, {int limit = 12000000}) {
    if (baseDirectory == null) return html;
    return html.replaceAllMapped(_media, (match) {
      final file = localFile(match.group(3)!, baseDirectory);
      if (file != null) {
        try {
          if (file.lengthSync() <= limit) {
            final data = base64Encode(file.readAsBytesSync());
            return '${match.group(1)}"data:${mimeType(extension(file.path))};base64,$data"';
          }
        } on FileSystemException {
          // Unreadable files keep their address.
        }
      }
      return match.group(0)!;
    });
  }

  /// The local file an image address points to, relative to [base], when it exists.
  static File? localFile(String address, String base) {
    final decoded = address.replaceAll('&amp;', '&');
    final schemeMatch = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):').firstMatch(decoded);
    // A one-letter "scheme" is a Windows drive (C:\...), not a URL.
    if (schemeMatch != null && schemeMatch.group(1)!.length > 1) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'file' && scheme != 'rotide-local') return null;
      final uri = Uri.tryParse(decoded);
      if (uri == null) return null;
      final file = File(Uri.file(Uri.decodeComponent(uri.path), windows: Platform.isWindows).toFilePath(windows: Platform.isWindows));
      return file.existsSync() ? file : null;
    }
    final path = decoded.split('#').first;
    try {
      final File file;
      if (schemeMatch != null || path.startsWith('/') || path.startsWith(r'\')) {
        file = File(Uri.decodeFull(path));
      } else {
        final directory = Uri.directory(base, windows: Platform.isWindows);
        file = File(directory.resolveUri(Uri(path: path.replaceAll(r'\', '/'))).toFilePath(windows: Platform.isWindows));
      }
      return file.existsSync() ? file : null;
    } on Object {
      return null;
    }
  }

  static String extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String mimeType(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'bmp' => 'image/bmp',
        'ico' => 'image/x-icon',
        'mp4' || 'm4v' => 'video/mp4',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'wav' => 'audio/wav',
        _ => 'application/octet-stream',
      };
}
