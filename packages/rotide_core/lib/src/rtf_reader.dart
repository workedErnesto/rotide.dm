import 'markdown_builder.dart';

/// An RTF document as Markdown: bold, italic, strikethrough, links, monospaced text as code, headings (by outline
/// level, or a bold paragraph clearly larger than the body text), bulleted, numbered and task lists, quotes drawn with
/// a left rule (as rotide.dm writes them), and tables. Fonts, sizes, colours, alignment, images, headers and footers
/// are left out.
abstract final class RtfReader {
  static String markdown(String rtf) {
    if (!rtf.trimLeft().startsWith(r'{\rtf')) throw const FormatException('файл не похож на документ RTF');
    final parser = _Parser(rtf)..run();
    return MarkdownBuilder.build(parser.blocks());
  }
}

final class _State {
  _State();

  bool bold = false;
  bool italic = false;
  bool strike = false;
  int font = 0;
  int size = 24;
  String? link;

  /// Text of this group is not shown: font table, pictures, document info and other destinations.
  bool skip = false;

  /// What this group collects instead of document text.
  _Destination destination = _Destination.text;

  /// Characters to skip after `\u`.
  int unicodeSkip = 1;

  /// The instruction of a field (`HYPERLINK "url"`), set by its `\fldinst` group.
  String? fieldInstruction;

  _State copy() => _State()
    ..bold = bold
    ..italic = italic
    ..strike = strike
    ..font = font
    ..size = size
    ..link = link
    ..skip = skip
    ..destination = destination
    ..unicodeSkip = unicodeSkip;

  void plain() {
    bold = false;
    italic = false;
    strike = false;
    font = 0;
    size = 24;
  }
}

enum _Destination { text, fontTable, fieldInstruction, listText }

final class _Run {
  _Run(this.text, this.state) : size = state.size;
  String text;
  final _State state;
  final int size;
}

final class _Paragraph {
  final runs = <_Run>[];
  int leftIndent = 0;
  int? outline;
  bool leftBorder = false;
  bool bottomBorder = false;
  bool inTable = false;
  int? listLevel;
  String listText = '';

  String get plain => runs.map((run) => run.text).join();
}

final class _Parser {
  _Parser(this.source);
  final String source;

  var _position = 0;
  final _stack = <_State>[_State()];
  final _fonts = <int, String>{};
  final _monospacedFamily = <int>{};
  int? _fontEntry;
  final _fontName = StringBuffer();
  int _codepage = 1252;
  int _defaultFont = 0;

  /// Paragraph properties set since the last `\pard`.
  var _paragraph = _Paragraph();
  final _paragraphs = <Object>[];

  /// Paragraphs of the current cell, cells of the current row, rows of the current table.
  List<_Paragraph> _cell = [];
  List<List<_Paragraph>> _row = [];
  List<List<List<_Paragraph>>> _table = [];

  _State get _state => _stack.last;

  void run() {
    while (_position < source.length) {
      final char = source[_position];
      switch (char) {
        case '{':
          _stack.add(_state.copy());
          _position++;
          if (source.startsWith(r'\*', _position)) {
            _position += 2;
            // An ignorable destination; the field instruction is the one rotide.dm reads.
            final word = RegExp(r'\s*\\([a-z]+)').matchAsPrefix(source, _position);
            if (word != null && word.group(1) == 'fldinst') {
              _state.destination = _Destination.fieldInstruction;
              _instruction.clear();
            } else {
              _state.skip = true;
            }
          }
        case '}':
          _closeGroup();
          _position++;
        case '\\':
          _control();
        case '\r' || '\n':
          _position++;
        default:
          _text(char);
          _position++;
      }
    }
    _endParagraph();
    _endTable();
  }

  final _instruction = StringBuffer();

  void _closeGroup() {
    final closing = _state;
    if (_stack.length > 1) _stack.removeLast();
    if (closing.destination == _Destination.fontTable && _state.destination != _Destination.fontTable) _endFontEntry();
    if (closing.destination == _Destination.fieldInstruction && _state.destination != _Destination.fieldInstruction) {
      final match = RegExp(r'HYPERLINK\s+"([^"]+)"').firstMatch(_instruction.toString());
      _state.fieldInstruction = match?.group(1);
    }
  }

  void _text(String text) {
    final state = _state;
    if (state.skip) return;
    switch (state.destination) {
      case _Destination.fontTable:
        _fontName.write(text);
        if (text.contains(';')) _endFontEntry();
      case _Destination.fieldInstruction:
        _instruction.write(text);
      case _Destination.listText:
        _paragraph.listText += text;
      case _Destination.text:
        final runs = _paragraph.runs;
        if (runs.isNotEmpty && identical(runs.last.state, state)) {
          runs.last.text += text;
        } else {
          runs.add(_Run(text, state));
        }
    }
  }

  void _endFontEntry() {
    final index = _fontEntry;
    if (index == null) return;
    _fonts[index] = _fontName.toString().replaceAll(';', '').trim().toLowerCase();
    _fontEntry = null;
    _fontName.clear();
  }

  static const _skipped = {
    'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'header', 'headerl', 'headerr', 'headerf', 'footer', 'footerl',
    'footerr', 'footerf', 'footnote', 'listtable', 'listoverridetable', 'rsidtbl', 'generator', 'themedata',
    'colorschememapping', 'latentstyles', 'datastore', 'xmlnstbl', 'mmathPr', 'pgdsctbl', 'object', 'shppict', 'nonshppict',
    'revtbl', 'filetbl', 'expandedcolortbl', 'annotation', 'atnid', 'atnauthor', 'bkmkstart', 'bkmkend',
  };

  void _control() {
    _position++;
    if (_position >= source.length) return;
    final next = source[_position];
    if (next == "'") {
      final hex = source.substring(_position + 1, (_position + 3).clamp(0, source.length));
      _position += 3;
      final byte = int.tryParse(hex, radix: 16);
      if (byte != null) _text(String.fromCharCode(_decodeByte(byte)));
      return;
    }
    if (!RegExp('[a-zA-Z]').hasMatch(next)) {
      _position++;
      switch (next) {
        case '\\' || '{' || '}':
          _text(next);
        case '~':
          _text(' ');
        case '_':
          _text('‑');
        case '\n' || '\r':
          _endParagraph();
      }
      return;
    }
    final match = RegExp(r'([a-zA-Z]+)(-?\d+)? ?').matchAsPrefix(source, _position)!;
    _position = match.end;
    final word = match.group(1)!;
    final parameter = match.group(2) == null ? null : int.tryParse(match.group(2)!);
    _word(word, parameter);
  }

  void _word(String word, int? parameter) {
    final state = _state;
    if (_skipped.contains(word)) {
      if (word == 'fonttbl') {
        state.destination = _Destination.fontTable;
      } else {
        state.skip = true;
      }
      return;
    }
    if (state.destination == _Destination.fontTable) {
      switch (word) {
        case 'f':
          _endFontEntry();
          _fontEntry = parameter ?? 0;
        case 'fmodern':
          if (_fontEntry != null) _monospacedFamily.add(_fontEntry!);
      }
      return;
    }
    switch (word) {
      case 'ansicpg':
        _codepage = parameter ?? 1252;
      case 'deff':
        _defaultFont = parameter ?? 0;
      case 'uc':
        state.unicodeSkip = parameter ?? 1;
      case 'u':
        var code = parameter ?? 0;
        if (code < 0) code += 65536;
        _text(String.fromCharCode(code));
        _skipFallback(state.unicodeSkip);
      case 'par' || 'sect':
        _endParagraph();
      case 'line':
        _text('\n');
      case 'tab':
        _text('\t');
      case 'emdash':
        _text('—');
      case 'endash':
        _text('–');
      case 'bullet':
        _text('•');
      case 'lquote':
        _text('‘');
      case 'rquote':
        _text('’');
      case 'ldblquote':
        _text('“');
      case 'rdblquote':
        _text('”');
      case 'b':
        _set((s) => s.bold = parameter != 0);
      case 'i':
        _set((s) => s.italic = parameter != 0);
      case 'strike' || 'striked':
        _set((s) => s.strike = parameter != 0);
      case 'f':
        _set((s) => s.font = parameter ?? 0);
      case 'fs':
        _set((s) => s.size = parameter ?? 24);
      case 'plain':
        _set((s) => s.plain());
      case 'pard':
        _paragraph.leftIndent = 0;
        _paragraph.outline = null;
        _paragraph.leftBorder = false;
        _paragraph.bottomBorder = false;
        _paragraph.inTable = false;
        _paragraph.listLevel = null;
      case 'li':
        _paragraph.leftIndent = parameter ?? 0;
      case 'outlinelevel':
        _paragraph.outline = parameter;
      case 'brdrl':
        _paragraph.leftBorder = true;
      case 'brdrb':
        _paragraph.bottomBorder = true;
      case 'ls':
        _paragraph.listLevel ??= 0;
      case 'ilvl':
        _paragraph.listLevel = parameter ?? 0;
      case 'listtext' || 'pntext':
        state.destination = _Destination.listText;
      case 'fldrslt':
        final link = _stack.length > 1 ? _stack[_stack.length - 2].fieldInstruction : null;
        if (link != null) state.link = link;
      case 'intbl':
        _paragraph.inTable = true;
      case 'fldinst':
        state.destination = _Destination.fieldInstruction;
        _instruction.clear();
      case 'cell':
        _endParagraph(force: true);
        _row.add(_cell);
        _cell = [];
      case 'row':
        _table.add(_row);
        _row = [];
      case 'bin':
        _position += parameter ?? 0;
    }
  }

  /// Formatting changes start a new run: the state of the group is replaced by a copy so earlier runs keep theirs.
  void _set(void Function(_State state) change) {
    final updated = _state.copy();
    change(updated);
    _stack[_stack.length - 1] = updated;
  }

  void _skipFallback(int count) {
    var left = count;
    while (left > 0 && _position < source.length) {
      final char = source[_position];
      if (char == '\\' && source.startsWith("\\'", _position)) {
        _position += 4;
      } else if (char == '{' || char == '}' || char == '\\') {
        return;
      } else {
        _position++;
      }
      left--;
    }
  }

  void _endParagraph({bool force = false}) {
    final paragraph = _paragraph;
    final next = _Paragraph()
      ..leftIndent = paragraph.leftIndent
      ..outline = paragraph.outline
      ..leftBorder = paragraph.leftBorder
      ..bottomBorder = paragraph.bottomBorder
      ..inTable = paragraph.inTable
      ..listLevel = paragraph.listLevel;
    _paragraph = next;
    if (paragraph.inTable) {
      if (paragraph.runs.isNotEmpty || force) _cell.add(paragraph);
      return;
    }
    _endTable();
    _paragraphs.add(paragraph);
  }

  void _endTable() {
    if (_cell.isNotEmpty) {
      _row.add(_cell);
      _cell = [];
    }
    if (_row.isNotEmpty) {
      _table.add(_row);
      _row = [];
    }
    if (_table.isEmpty) return;
    _paragraphs.add(_table);
    _table = [];
  }

  int _decodeByte(int byte) {
    if (byte < 0x80) return byte;
    if (_codepage == 1251) {
      if (byte >= 0xC0) return 0x410 + byte - 0xC0;
      return _cp1251High.codeUnitAt(byte - 0x80);
    }
    if (_codepage == 10000 || _codepage == 1252) {
      if (byte >= 0x80 && byte < 0xA0 && _codepage == 1252) return _cp1252High.codeUnitAt(byte - 0x80);
    }
    return byte;
  }

  static const _cp1251High = 'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї';
  static const _cp1252High = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F\u0090‘’“”•–—˜™š›œ\u009DžŸ';

  bool _monospaced(int font) {
    final name = _fonts[font] ?? '';
    if (_monospacedFamily.contains(font)) return true;
    return const ['mono', 'courier', 'consolas', 'menlo', 'monaco', 'lucida console'].any(name.contains);
  }

  List<TextRun> _runs(_Paragraph paragraph) => [
        for (final run in paragraph.runs)
          TextRun(
            run.text,
            bold: run.state.bold,
            italic: run.state.italic,
            strike: run.state.strike,
            code: _monospaced(run.state.font == 0 ? _defaultFont : run.state.font) && run.text.trim().isNotEmpty,
            link: run.state.link,
            size: run.size,
          ),
      ];

  List<DocumentBlock> blocks() {
    final out = <DocumentBlock>[];
    final body = DrawnLayout.bodySize(_paragraphs.whereType<_Paragraph>().expand(_runs));

    for (final item in _paragraphs) {
      if (item is List<List<List<_Paragraph>>>) {
        out.add(TableBlock([
          for (final row in item) [for (final cell in row) [for (final paragraph in cell) _runs(paragraph)]],
        ]));
        continue;
      }
      final paragraph = item as _Paragraph;
      final runs = _runs(paragraph);
      final text = paragraph.plain;
      if (text.trim().isEmpty) {
        if (paragraph.bottomBorder) out.add(const RuleBlock());
        continue;
      }
      if (runs.every((run) => run.code || run.text.trim().isEmpty)) {
        out.add(CodeBlock(text));
        continue;
      }
      final listItem = DrawnLayout.listItem(runs, indent: paragraph.leftIndent, marker: paragraph.listText, level: paragraph.listLevel ?? -1) ??
          (paragraph.listLevel != null ? DrawnLayout.listItem(runs, indent: paragraph.leftIndent, marker: '•', level: paragraph.listLevel!) : null);
      if (listItem != null) {
        out.add(listItem);
        continue;
      }
      final outline = paragraph.outline;
      final heading = outline != null && outline < 9 ? outline + 1 : DrawnLayout.heading(runs, body);
      if (heading != null) {
        out.add(ParagraphBlock(runs, kind: ParagraphKind.heading, level: heading));
      } else if (paragraph.leftBorder) {
        out.add(ParagraphBlock(runs, kind: ParagraphKind.quote));
      } else {
        out.add(ParagraphBlock(runs));
      }
    }
    return out;
  }
}
