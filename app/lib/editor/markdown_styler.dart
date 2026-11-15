
import 'package:flutter/painting.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// The font of a character, replaced as a whole the way NSTextStorage replaces `.font`.
final class _Font {
  const _Font({required this.scale, this.weight = FontWeight.w400, this.italic = false, this.mono = false, this.concealed = false});
  final double scale;
  final FontWeight weight;
  final bool italic;
  final bool mono;
  final bool concealed;

  @override
  bool operator ==(Object other) =>
      other is _Font && other.scale == scale && other.weight == weight && other.italic == italic && other.mono == mono && other.concealed == concealed;

  @override
  int get hashCode => Object.hash(scale, weight, italic, mono, concealed);
}

enum _Ink { ink, text2, text3, link, clear }

/// Result of styling: the spans to draw and the hidden markers the editor steps over.
final class StyledText {
  const StyledText({required this.span, required this.concealed, required this.closing});
  final TextSpan span;

  /// Offsets of hidden Markdown markers (`**`, `#`, `[`, `](url)`).
  final Set<int> concealed;

  /// Offsets of hidden closing markers: typing right after them goes before them, inside the styled text.
  final Set<int> closing;
}

/// Source-preserving presentation of common inline Markdown, ported from the Swift EditorStyle: headings, emphasis,
/// strikethrough, code, links and quotes are styled in place and their supported markers hidden. Unsupported
/// constructs stay visible as source.
abstract final class MarkdownStyler {
  static RegExp _re(String pattern) => RegExp(pattern, multiLine: true);

  static final _fence = _re(r'^[ \t]{0,3}(```|~~~)[^\n]*\n[\s\S]*?(^[ \t]{0,3}\1[ \t]*$|(?![\s\S]))');
  static final _heading = _re(r'^[ \t]{0,3}(#{1,6})([ \t].*)?$');
  static final _setext = _re(r'^[ \t]{0,3}(=+|-{2,})[ \t]*$');
  static final _quote = _re(r'^[ \t]{0,3}(>[ \t]?)+.*$');
  static final _list = _re(r'^[ \t]*([-*+]|\d{1,9}[.)])(?=[ \t])( \[[ xX]\])?');
  static final _rule = _re(r'^[ \t]{0,3}([-*_])([ \t]*\1){2,}[ \t]*$');
  static final _strong = _re(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1');
  static final _emphasis = _re(r'(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])');
  static final _strike = _re(r'~~(?=\S)(.+?)(?<=\S)~~');
  static final _code = _re(r'(`+)(?!`)(.+?)(?<!`)\1(?!`)');
  static final _link = _re(r'(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))');
  static final _autolink = _re(r'<(https?://|mailto:)[^>\s]+>|https?://[^\s)>\]]+');
  static final _html = _re(r'</?[A-Za-z][A-Za-z0-9-]*(\s[^<>\n]*)?/?>|<!--[\s\S]*?-->');

  /// Group start offsets: Dart's RegExpMatch has no group ranges, so they are found inside the match.
  static (int, int) _group(RegExpMatch match, int index, {bool fromEnd = false}) {
    final value = match.group(index);
    if (value == null) return (-1, 0);
    final whole = match.group(0)!;
    final at = fromEnd ? whole.lastIndexOf(value) : whole.indexOf(value);
    return (match.start + at, value.length);
  }

  /// [plain] text gets no Markdown styling: every character shows as typed, only find highlights are drawn.
  static StyledText style(String text,
      {required RotidePalette palette, required double size, required double lineHeight, List<(int, int)> marks = const [], int? currentMark, bool plain = false}) {
    final length = text.length;
    final fonts = List<_Font>.filled(length, const _Font(scale: 1));
    final inks = List<_Ink>.filled(length, _Ink.ink);
    final codeFill = List<bool>.filled(length, false);
    final strike = List<bool>.filled(length, false);
    final concealed = <int>{};
    final closing = <int>{};

    void font(int start, int count, _Font value) {
      for (var i = start; i < start + count && i < length; i++) {
        if (i >= 0) fonts[i] = value;
      }
    }

    void ink(int start, int count, _Ink value) {
      for (var i = start; i < start + count && i < length; i++) {
        if (i >= 0) inks[i] = value;
      }
    }

    void conceal(int start, int count, {bool isClosing = false}) {
      if (start < 0 || count <= 0) return;
      for (var i = start; i < start + count && i < length; i++) {
        concealed.add(i);
        if (isClosing) closing.add(i);
        fonts[i] = const _Font(scale: 1, concealed: true);
        inks[i] = _Ink.clear;
      }
    }

    if (!plain) {
      for (final match in _heading.allMatches(text)) {
        final level = match.group(1)!.length;
        final scale = level == 1 ? 2.0 : level == 2 ? 1.5 : 1.2;
        font(match.start, match.end - match.start, _Font(scale: scale, weight: FontWeight.w600));
        final (markerStart, markerLength) = _group(match, 1);
        ink(markerStart, markerLength, _Ink.text3);
        conceal(match.start, (level + 1).clamp(0, match.end - match.start));
      }
      for (final match in _setext.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.text3);
      }
      for (final match in _quote.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.text2);
      }
      for (final match in _list.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.text3);
      }
      for (final match in _rule.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.text3);
      }
      for (final match in _strong.allMatches(text)) {
        font(match.start, match.end - match.start, const _Font(scale: 1, weight: FontWeight.w600));
        final open = match.group(1)!.length;
        ink(match.start, open, _Ink.text3);
        ink(match.end - open, open, _Ink.text3);
        conceal(match.start, open);
        conceal(match.end - open, open, isClosing: true);
      }
      for (final match in _emphasis.allMatches(text)) {
        font(match.start, match.end - match.start, const _Font(scale: 1, italic: true));
        conceal(match.start, 1);
        conceal(match.end - 1, 1, isClosing: true);
      }
      for (final match in _strike.allMatches(text)) {
        final (innerStart, innerLength) = (match.start + 2, match.end - match.start - 4);
        for (var i = innerStart; i < innerStart + innerLength; i++) {
          strike[i] = true;
        }
        ink(match.start, match.end - match.start, _Ink.text2);
        conceal(match.start, 2);
        conceal(match.end - 2, 2, isClosing: true);
      }
      for (final match in _html.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.text3);
      }
      for (final match in _link.allMatches(text)) {
        final open = match.group(1)!, label = match.group(2)!, middle = match.group(3)!, url = match.group(4)!;
        final openAt = match.start;
        final labelAt = openAt + open.length;
        final middleAt = labelAt + label.length;
        final urlAt = middleAt + middle.length;
        final closeAt = urlAt + url.length;
        ink(openAt, open.length, _Ink.text3);
        ink(labelAt, label.length, _Ink.link);
        ink(middleAt, middle.length, _Ink.text3);
        ink(urlAt, url.length, _Ink.text3);
        ink(closeAt, 1, _Ink.text3);
        if (!open.startsWith('!')) {
          conceal(openAt, open.length);
          conceal(middleAt, middle.length, isClosing: true);
          conceal(urlAt, url.length, isClosing: true);
          conceal(closeAt, 1, isClosing: true);
        }
      }
      for (final match in _autolink.allMatches(text)) {
        ink(match.start, match.end - match.start, _Ink.link);
      }
      for (final match in _code.allMatches(text)) {
        font(match.start, match.end - match.start, const _Font(scale: 0.9, mono: true));
        ink(match.start, match.end - match.start, _Ink.text2);
        for (var i = match.start; i < match.end; i++) {
          codeFill[i] = true;
        }
        final open = match.group(1)!.length;
        conceal(match.start, open);
        conceal(match.end - open, open, isClosing: true);
      }
      // Fences last: nothing inside a code block is Markdown.
      for (final match in _fence.allMatches(text)) {
        for (var i = match.start; i < match.end; i++) {
          fonts[i] = const _Font(scale: 1);
          inks[i] = _Ink.text2;
          codeFill[i] = false;
          strike[i] = false;
          concealed.remove(i);
          closing.remove(i);
        }
      }
    }

    // Find highlights.
    final marked = List<int>.filled(length, 0);
    for (var index = 0; index < marks.length; index++) {
      final (start, end) = marks[index];
      for (var i = start; i < end && i < length; i++) {
        marked[i] = index == currentMark ? 2 : 1;
      }
    }

    Color color(_Ink value) => switch (value) {
          _Ink.ink => palette.ink,
          _Ink.text2 => palette.text2,
          _Ink.text3 => palette.text3,
          _Ink.link => palette.link,
          _Ink.clear => const Color(0x00000000),
        };

    TextStyle styleFor(int i) {
      final f = fonts[i];
      final background = marked[i] == 2
          ? const Color(0xFFFFE066)
          : marked[i] == 1
              ? const Color(0x66FFE066)
              : codeFill[i]
                  ? palette.codeFill
                  : null;
      if (f.concealed) {
        return TextStyle(fontFamily: RotideFonts.sans, fontSize: 0.1, color: const Color(0x00000000), height: 1, background: null);
      }
      return TextStyle(
        fontFamily: f.mono ? RotideFonts.mono : RotideFonts.sans,
        fontFamilyFallback: f.mono ? RotideFonts.monoFallback : RotideFonts.sansFallback,
        fontSize: size * f.scale,
        fontWeight: f.weight,
        fontVariations: f.mono ? null : RotideFonts.opticalSize(size * f.scale),
        letterSpacing: f.mono ? null : RotideFonts.tracking(size * f.scale),
        fontStyle: f.italic ? FontStyle.italic : FontStyle.normal,
        color: color(inks[i]),
        backgroundColor: background,
        decoration: strike[i] ? TextDecoration.lineThrough : TextDecoration.none,
        decorationColor: color(inks[i]),
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.proportional,
      );
    }

    final children = <TextSpan>[];
    var start = 0;
    while (start < length) {
      final style = styleFor(start);
      var end = start + 1;
      while (end < length && fonts[end] == fonts[start] && inks[end] == inks[start] && codeFill[end] == codeFill[start] &&
          strike[end] == strike[start] && marked[end] == marked[start]) {
        end++;
      }
      children.add(TextSpan(text: text.substring(start, end), style: style));
      start = end;
    }
    final base = TextStyle(
      fontFamily: RotideFonts.sans,
      fontFamilyFallback: RotideFonts.sansFallback,
      fontSize: size,
      color: palette.ink,
      height: lineHeight,
      leadingDistribution: TextLeadingDistribution.proportional,
    );
    return StyledText(span: TextSpan(style: base, children: children), concealed: concealed, closing: closing);
  }
}
