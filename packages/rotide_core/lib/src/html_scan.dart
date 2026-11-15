/// Small readers for raw HTML in Markdown.
abstract final class HtmlScan {
  static final _imageTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);

  static List<HtmlImage> images(String html) => [
        for (final match in _imageTag.allMatches(html))
          if (_image(match.group(0)!) case final image?) image,
      ];

  static HtmlImage? _image(String element) {
    final src = attribute('src', element);
    if (src == null) return null;
    return HtmlImage(
      source: src,
      alt: entities(attribute('alt', element) ?? ''),
      width: _number(attribute('width', element)),
      height: _number(attribute('height', element)),
    );
  }

  static int? _number(String? value) {
    if (value == null) return null;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  static String? attribute(String name, String element) {
    final match = RegExp('\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(element);
    if (match == null) return null;
    return match.group(1) ?? match.group(2) ?? match.group(3);
  }

  static const blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'details', 'summary', 'table', 'tr', 'li', 'ul', 'ol', //
    'blockquote', 'pre', 'section', 'header', 'footer', 'center', 'hr', 'figure', 'figcaption', 'dl', 'dt', 'dd',
  };

  static final _tag = RegExp(r'<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)\b[^>]*>');
  static final _spaces = RegExp(r'\s+');

  /// Splits raw HTML into paragraphs at block tags; each keeps its heading level and centring.
  static List<HtmlSegment> segments(String html) {
    final segments = <HtmlSegment>[];
    final alignStack = <bool>[];
    var current = HtmlSegment(center: false);

    void flush() {
      if (current.parts.any((part) => part is! HtmlLineBreak)) segments.add(current);
      current = HtmlSegment(center: alignStack.isNotEmpty && alignStack.last);
    }

    void addText(String raw) {
      final text = entities(raw).replaceAll(_spaces, ' ');
      if (text.trim().isEmpty) return;
      if (current.parts.isNotEmpty && current.parts.last is HtmlText) {
        final previous = current.parts.last as HtmlText;
        current.parts[current.parts.length - 1] = HtmlText(previous.text + text);
      } else {
        current.parts.add(HtmlText(current.parts.isEmpty ? text.replaceFirst(RegExp(r'^ +'), '') : text));
      }
    }

    var last = 0;
    for (final match in _tag.allMatches(html)) {
      addText(html.substring(last, match.start));
      last = match.end;
      final nameGroup = match.group(2);
      if (nameGroup == null) continue;
      final element = match.group(0)!;
      final name = nameGroup.toLowerCase();
      final closing = (match.group(1) ?? '').isNotEmpty;
      if (name == 'img') {
        final image = _image(element);
        if (image != null) current.parts.add(image);
      } else if (name == 'br') {
        current.parts.add(const HtmlLineBreak());
      } else if (blockTags.contains(name)) {
        flush();
        if (closing) {
          if (alignStack.isNotEmpty) alignStack.removeLast();
          current.center = alignStack.isNotEmpty && alignStack.last;
        } else {
          final centred = name == 'center' ||
              attribute('align', element)?.toLowerCase() == 'center' ||
              (alignStack.isNotEmpty && alignStack.last);
          if (name != 'hr') alignStack.add(centred);
          current.center = centred;
          if (name.length == 2 && name.startsWith('h')) current.heading = int.tryParse(name.substring(1));
        }
      }
    }
    addText(html.substring(last));
    flush();
    return segments;
  }

  /// Text content: tags and comments removed, entities decoded, whitespace collapsed.
  static String text(String html) {
    var stripped = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    stripped = stripped.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    stripped = stripped.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return entities(stripped)
        .split('\n')
        .map((line) => line.replaceAll(_spaces, ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static const _named = [
    ('&nbsp;', ' '), ('&lt;', '<'), ('&gt;', '>'), ('&quot;', '"'), ('&#39;', "'"), ('&apos;', "'"), //
    ('&mdash;', '—'), ('&ndash;', '–'), ('&copy;', '©'), ('&hellip;', '…'),
  ];
  static final _numeric = RegExp(r'&#(x?)([0-9a-fA-F]+);');

  static String entities(String text) {
    if (!text.contains('&')) return text;
    var out = text;
    for (final (entity, value) in _named) {
      out = out.replaceAll(entity, value);
    }
    out = out.replaceAllMapped(_numeric, (match) {
      final code = int.tryParse(match.group(2)!, radix: match.group(1)!.isNotEmpty ? 16 : 10);
      if (code == null || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return '';
      return String.fromCharCode(code);
    });
    return out.replaceAll('&amp;', '&');
  }
}

sealed class HtmlPart {
  const HtmlPart();
}

final class HtmlText extends HtmlPart {
  const HtmlText(this.text);
  final String text;
}

final class HtmlLineBreak extends HtmlPart {
  const HtmlLineBreak();
}

final class HtmlImage extends HtmlPart {
  const HtmlImage({required this.source, required this.alt, this.width, this.height});
  final String source;
  final String alt;
  final int? width;
  final int? height;
}

final class HtmlSegment {
  HtmlSegment({required this.center});
  int? heading;
  bool center;
  final parts = <HtmlPart>[];
}

abstract final class Xml {
  static const header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  /// Escapes markup and drops the control characters XML 1.0 does not allow.
  static String text(String value) {
    final out = StringBuffer();
    for (final rune in value.runes) {
      switch (rune) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0x09 || 0x0A || 0x0D:
          out.writeCharCode(rune);
        default:
          if (rune < 0x20 || rune == 0xFFFE || rune == 0xFFFF) continue;
          out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static String attribute(String value) => text(value).replaceAll('"', '&quot;').replaceAll('\n', ' ');
}
