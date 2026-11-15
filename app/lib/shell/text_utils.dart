import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract final class Russian {
  /// 1 слово, 2 слова, 5 слов, 21 слово.
  static String plural(int n, String one, String few, String many) {
    final tens = n % 100, ones = n % 10;
    if (tens >= 11 && tens <= 14) return many;
    if (ones == 1) return one;
    if (ones >= 2 && ones <= 4) return few;
    return many;
  }

  /// 12 345 with a narrow no-break space, as `formatted(.number)` writes in the Russian locale.
  static String grouped(int n) {
    final digits = n.abs().toString();
    final buffer = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// Keyboard shortcut hints in the host's notation.
String shortcutHint(String mac) {
  if (defaultTargetPlatform == TargetPlatform.macOS) return mac;
  final parts = <String>[];
  if (mac.contains('⌃')) parts.add('Ctrl');
  if (mac.contains('⌥')) parts.add('Alt');
  if (mac.contains('⇧')) parts.add('Shift');
  if (mac.contains('⌘') && !parts.contains('Ctrl')) parts.add('Ctrl');
  final key = mac.replaceAll(RegExp('[⌃⌥⇧⌘]'), '');
  return [...parts, key].join('+');
}

/// A single line that gives up characters in the middle when it does not fit (`truncationMode(.middle)`).
final class MiddleEllipsisText extends StatelessWidget {
  const MiddleEllipsisText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final max = constraints.maxWidth;
        String fitted = text;
        if (max.isFinite && _width(text) > max) {
          final characters = text.runes.toList();
          var low = 0, high = characters.length;
          while (low < high) {
            final keep = (low + high + 1) ~/ 2;
            final candidate = _cut(characters, keep);
            if (_width(candidate) <= max) {
              low = keep;
            } else {
              high = keep - 1;
            }
          }
          fitted = _cut(characters, low);
        }
        return Text(fitted, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);
      });

  String _cut(List<int> characters, int keep) {
    if (keep >= characters.length) return String.fromCharCodes(characters);
    final head = (keep + 1) ~/ 2, tail = keep ~/ 2;
    return '${String.fromCharCodes(characters.sublist(0, head))}…${String.fromCharCodes(characters.sublist(characters.length - tail))}';
  }

  double _width(String value) {
    final painter = TextPainter(text: TextSpan(text: value, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    return painter.width;
  }
}

/// A single line that gives up characters at its start (`truncationMode(.head)`), for folder paths.
final class HeadEllipsisText extends StatelessWidget {
  const HeadEllipsisText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final max = constraints.maxWidth;
        var fitted = text;
        double width(String value) => (TextPainter(text: TextSpan(text: value, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout()).width;
        if (max.isFinite && width(text) > max) {
          final characters = text.runes.toList();
          var low = 0, high = characters.length;
          while (low < high) {
            final keep = (low + high + 1) ~/ 2;
            if (width('…${String.fromCharCodes(characters.sublist(characters.length - keep))}') <= max) {
              low = keep;
            } else {
              high = keep - 1;
            }
          }
          fitted = '…${String.fromCharCodes(characters.sublist(characters.length - low))}';
        }
        return Text(fitted, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);
      });
}
