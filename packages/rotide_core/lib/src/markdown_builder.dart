/// A piece of text with the inline formatting Markdown can hold.
final class TextRun {
  const TextRun(this.text, {this.bold = false, this.italic = false, this.strike = false, this.code = false, this.link, this.size = 0});
  final String text;

  /// Font size in half-points when the format gives one, 0 otherwise; finds headings drawn as large bold text.
  final int size;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  TextRun copyWith({String? text, bool? bold}) =>
      TextRun(text ?? this.text, bold: bold ?? this.bold, italic: italic, strike: strike, code: code, link: link, size: size);

  bool sameStyle(TextRun other) =>
      other.bold == bold && other.italic == italic && other.strike == strike && other.code == code && other.link == link;
}

/// A block of a document read from Word or RTF, before it is written as Markdown.
sealed class DocumentBlock {
  const DocumentBlock();
}

enum ParagraphKind { body, heading, quote, listItem }

final class ParagraphBlock extends DocumentBlock {
  const ParagraphBlock(this.runs, {this.kind = ParagraphKind.body, this.level = 0, this.ordered = false, this.checked, this.indent = 0});
  final List<TextRun> runs;
  final ParagraphKind kind;

  /// Heading level 1...6, or list nesting from 0; -1 for a list item whose nesting follows from [indent].
  final int level;

  /// Left indent in twips, for list items drawn by hand.
  final int indent;
  final bool ordered;

  /// A task list item: checked or not; null for other items.
  final bool? checked;

  String get plain => runs.map((run) => run.text).join();
}

final class CodeBlock extends DocumentBlock {
  const CodeBlock(this.code);
  final String code;
}

final class TableBlock extends DocumentBlock {
  const TableBlock(this.rows);

  /// Rows of cells; each cell is its paragraphs.
  final List<List<List<List<TextRun>>>> rows;
}

final class RuleBlock extends DocumentBlock {
  const RuleBlock();
}

/// Writes blocks read from another format as GitHub Markdown: headings, emphasis, links, lists, quotes, code and
/// tables. Text is escaped so that it reads back as the same text.
abstract final class MarkdownBuilder {
  static String build(List<DocumentBlock> source) {
    final blocks = _nestByIndent(source);
    final out = StringBuffer();
    final markers = <int>[];
    final counters = <int, int>{};
    final kinds = <int, bool>{};
    var previousList = false;
    var pendingCode = <String>[];

    void separate({required bool list}) {
      if (out.isEmpty) return;
      out.write(list && previousList ? '\n' : '\n\n');
    }

    void flushCode() {
      if (pendingCode.isEmpty) return;
      separate(list: false);
      out.write(_fence(pendingCode.join('\n')));
      pendingCode = [];
      previousList = false;
    }

    for (final block in blocks) {
      if (block is CodeBlock) {
        pendingCode.add(block.code);
        continue;
      }
      flushCode();
      switch (block) {
        case ParagraphBlock(kind: ParagraphKind.listItem):
          final level = block.level < 0 ? 0 : block.level;
          if (!previousList) {
            markers.clear();
            counters.clear();
            kinds.clear();
          }
          // A level deeper than the one above nests right under it.
          final depth = level > markers.length ? markers.length : level;
          markers.length = depth;
          counters.removeWhere((key, _) => key > depth);
          // A bulleted list after a numbered one at the same depth (or the other way) is a new list.
          if (kinds[depth] != block.ordered) counters.remove(depth);
          kinds[depth] = block.ordered;
          kinds.removeWhere((key, _) => key > depth);
          final number = (counters[depth] ?? 0) + 1;
          counters[depth] = number;
          final marker = block.ordered ? '$number. ' : '- ';
          final indent = markers.fold(0, (sum, width) => sum + width);
          markers.add(marker.length);
          final task = switch (block.checked) { true => '[x] ', false => '[ ] ', null => '' };
          final text = inline(block.runs);
          separate(list: true);
          out
            ..write(' ' * indent)
            ..write(marker)
            ..write(task)
            ..write(text.replaceAll('\n', '\n${' ' * (indent + marker.length)}'));
          previousList = true;
          continue;
        case ParagraphBlock(kind: ParagraphKind.heading):
          final text = inline(block.runs.map((run) => run.copyWith(bold: false)).toList()).replaceAll('\\\n', ' ').replaceAll('\n', ' ');
          if (text.trim().isEmpty) continue;
          separate(list: false);
          out.write('${'#' * block.level.clamp(1, 6)} ${text.trim()}');
        case ParagraphBlock(kind: ParagraphKind.quote):
          final text = inline(block.runs);
          if (text.trim().isEmpty) continue;
          separate(list: false);
          out.write(text.split('\n').map((line) => '> $line').join('\n'));
        case ParagraphBlock():
          final text = inline(block.runs);
          if (text.trim().isEmpty) continue;
          separate(list: false);
          out.write(text);
        case TableBlock(:final rows):
          if (rows.isEmpty) continue;
          separate(list: false);
          out.write(_table(rows));
        case RuleBlock():
          separate(list: false);
          out.write('---');
        case CodeBlock():
          break;
      }
      previousList = false;
    }
    flushCode();
    if (out.isNotEmpty) out.write('\n');
    return out.toString();
  }

  /// List items with unknown nesting take their depth from the order of the distinct indents in their list.
  static List<DocumentBlock> _nestByIndent(List<DocumentBlock> blocks) {
    final out = List<DocumentBlock>.of(blocks);
    var start = 0;
    while (start < out.length) {
      bool isItem(DocumentBlock block) => block is ParagraphBlock && block.kind == ParagraphKind.listItem;
      if (!isItem(out[start])) {
        start++;
        continue;
      }
      var end = start;
      while (end < out.length && isItem(out[end])) {
        end++;
      }
      final items = out.sublist(start, end).cast<ParagraphBlock>();
      final indents = (items.where((item) => item.level < 0).map((item) => item.indent).toSet().toList())..sort();
      for (var index = start; index < end; index++) {
        final item = out[index] as ParagraphBlock;
        if (item.level >= 0) continue;
        out[index] = ParagraphBlock(item.runs, kind: item.kind, level: indents.indexOf(item.indent), ordered: item.ordered, checked: item.checked, indent: item.indent);
      }
      start = end;
    }
    return out;
  }

  static String _fence(String code) {
    var longest = 0;
    for (final match in RegExp('`+').allMatches(code)) {
      if (match.end - match.start > longest) longest = match.end - match.start;
    }
    final fence = '`' * (longest >= 3 ? longest + 1 : 3);
    return '$fence\n$code\n$fence';
  }

  static String _table(List<List<List<List<TextRun>>>> rows) {
    final columns = rows.fold(0, (most, row) => row.length > most ? row.length : most);
    String cell(List<List<TextRun>> paragraphs) => paragraphs
        .map((runs) => inline(runs).replaceAll('\\\n', '<br>').replaceAll('\n', '<br>').replaceAll('|', r'\|').trim())
        .where((text) => text.isNotEmpty)
        .join('<br>');
    String line(List<String> cells) => '| ${cells.join(' | ')} |';
    final out = <String>[];
    // A header row drawn bold reads as the Markdown header without the asterisks.
    final headerRuns = rows.first.expand((paragraphs) => paragraphs.expand((runs) => runs)).where((run) => run.text.trim().isNotEmpty);
    if (headerRuns.isNotEmpty && headerRuns.every((run) => run.bold)) {
      rows = [
        [for (final cellParagraphs in rows.first) [for (final runs in cellParagraphs) [for (final run in runs) run.copyWith(bold: false)]]],
        ...rows.skip(1),
      ];
    }
    for (var index = 0; index < rows.length; index++) {
      final cells = [for (var column = 0; column < columns; column++) column < rows[index].length ? cell(rows[index][column]) : ''];
      out.add(line(cells));
      if (index == 0) out.add(line(List.filled(columns, '---')));
    }
    return out.join('\n');
  }

  /// Inline Markdown for runs: adjacent runs with the same style merge, markers hug the text (spaces stay outside, as
  /// emphasis requires), line breaks become hard breaks.
  static String inline(List<TextRun> runs) {
    final merged = <TextRun>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      if (merged.isNotEmpty && merged.last.sameStyle(run)) {
        final last = merged.removeLast();
        merged.add(last.copyWith(text: last.text + run.text));
      } else {
        merged.add(run);
      }
    }

    final out = StringBuffer();
    // Open markers from the outside in: link, strikethrough, bold, italic.
    final open = <String>[];
    String? openLink;

    String closer(String marker) => marker == '[' ? '](${_url(openLink!)})' : marker;

    void closeTo(int keep) {
      if (open.length <= keep) return;
      // Trailing spaces go after the closing markers.
      final text = out.toString();
      final trimmed = text.trimRight();
      final spaces = text.substring(trimmed.length);
      out
        ..clear()
        ..write(trimmed);
      while (open.length > keep) {
        out.write(closer(open.removeLast()));
      }
      if (!open.contains('[')) openLink = null;
      out.write(spaces);
    }

    for (final run in merged) {
      final wanted = [
        if (run.link != null) '[',
        if (run.strike) '~~',
        if (run.bold) '**',
        if (run.italic) '*',
      ];
      final whitespace = run.text.trim().isEmpty;
      if (!whitespace || run.code) {
        var keep = 0;
        while (keep < open.length && keep < wanted.length && open[keep] == wanted[keep] && (open[keep] != '[' || openLink == run.link)) {
          keep++;
        }
        closeTo(keep);
      }
      var text = run.text;
      if (whitespace && !run.code) {
        out.write(text.replaceAll('\n', '\\\n'));
        continue;
      }
      // Leading spaces go before the opening markers.
      final leading = text.length - text.trimLeft().length;
      out.write(text.substring(0, leading).replaceAll('\n', '\\\n'));
      text = text.substring(leading);
      for (final marker in wanted.skip(open.length)) {
        open.add(marker);
        out.write(marker);
        if (marker == '[') openLink = run.link;
      }
      out.write(run.code ? _code(text) : escape(text));
    }
    closeTo(0);
    return _escapeLineStarts(out.toString().trimRight());
  }

  static String _url(String url) => url.contains(RegExp(r'[\s()<>]')) ? '<${url.replaceAll('>', '%3E')}>' : url;

  static String _code(String text) {
    final lines = text.split('\n');
    return lines.map((line) {
      if (line.isEmpty) return '';
      var longest = 0;
      for (final match in RegExp('`+').allMatches(line)) {
        if (match.end - match.start > longest) longest = match.end - match.start;
      }
      final ticks = '`' * (longest + 1);
      final pad = line.startsWith('`') || line.endsWith('`') ? ' ' : '';
      return '$ticks$pad$line$pad$ticks';
    }).join('\\\n');
  }

  /// Escapes characters that would start Markdown inside a line: emphasis, code, links, HTML, strikethrough, and an
  /// underscore that is not inside a word.
  static String escape(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      switch (char) {
        case '\\' || '`' || '*' || '[' || ']' || '<' || '~':
          out.write('\\$char');
        case '_':
          final before = i > 0 && _word.hasMatch(text[i - 1]);
          final after = i + 1 < text.length && _word.hasMatch(text[i + 1]);
          out.write(before && after ? '_' : r'\_');
        case '&':
          out.write(RegExp(r'^&(#\d+|#x[0-9a-fA-F]+|\w+);').hasMatch(text.substring(i)) ? r'\&' : '&');
        case '\n':
          out.write('\\\n');
        default:
          out.write(char);
      }
    }
    return out.toString();
  }

  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _blockStart = RegExp(r'^(#{1,6}(?=\s|$)|>|[-+](?=\s)|=+\s*$|\d{1,9}(?=[.)](\s|$))|\|)');

  /// A line that starts like a block (a heading, quote, list item or table) gets its first character escaped.
  static String _escapeLineStarts(String text) => text.split('\n').map((line) {
        final trimmed = line.trimLeft();
        final match = _blockStart.firstMatch(trimmed);
        if (match == null) return trimmed;
        final number = match.group(0)!;
        if (RegExp(r'^\d').hasMatch(number)) return '$number\\${trimmed.substring(number.length)}';
        return '\\$trimmed';
      }).join('\n');

  /// Plain text as Markdown that renders as the same text: every line break is kept, runs of spaces stay, nothing is
  /// read as markup.
  static String fromPlainText(String text) {
    final paragraphs = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n(?:[ \t]*\n)+'));
    return paragraphs.where((paragraph) => paragraph.trim().isNotEmpty).map((paragraph) {
      // A line break at the start or end of the file is not a line of the paragraph.
      final kept = paragraph.split('\n');
      while (kept.first.trim().isEmpty) {
        kept.removeAt(0);
      }
      while (kept.last.trim().isEmpty) {
        kept.removeLast();
      }
      final lines = kept.map((line) {
        // Leading spaces and tabs would make an indented code block; keep them as non-breaking spaces.
        final indent = line.length - line.trimLeft().length;
        final lead = line.substring(0, indent).replaceAll('\t', '    ').replaceAll(' ', ' ');
        final body = escape(line.substring(indent).replaceAll('\t', '    ')).replaceAll('  ', '  ');
        // Dart's trim takes non-breaking spaces too, so the indent is added after the line start is escaped.
        return indent == 0 ? _escapeLineStarts(body) : '$lead$body';
      });
      return lines.join('\\\n');
    }).join('\n\n');
  }
}

/// Structure drawn with formatting instead of styles, as TextEdit, Pages and many converters write it: a heading is a
/// short bold paragraph in a larger size, a list item is a marker character followed by a tab.
abstract final class DrawnLayout {
  static final _marker = RegExp(r'^\s*([•◦▪●○■□·\-–*☐☑☒]|\d{1,9}[.)]?|[a-zA-Z][.)]|[ivxIVX]{1,5}[.)])[ ]*\t\s*');
  static final _bullet = RegExp(r'^[•◦▪●○■□·\-–*]$');

  /// The most common size of regular (not bold) text, the body size headings are compared with; the smallest size
  /// when everything is bold.
  static int bodySize(Iterable<TextRun> runs) {
    final counts = <int, int>{};
    var smallest = 0;
    for (final run in runs) {
      if (run.size <= 0 || run.text.trim().isEmpty) continue;
      if (smallest == 0 || run.size < smallest) smallest = run.size;
      if (!run.bold) counts[run.size] = (counts[run.size] ?? 0) + run.text.length;
    }
    if (counts.isEmpty) return smallest;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Heading level for a bold paragraph clearly larger than the body: 1 from 1.8 times, 2 from 1.45, 3 from 1.2.
  static int? heading(List<TextRun> runs, int body) {
    final visible = runs.where((run) => run.text.trim().isNotEmpty).toList();
    if (body <= 0 || visible.isEmpty || !visible.every((run) => run.bold)) return null;
    if (visible.any((run) => run.text.contains('\n'))) return null;
    final size = visible.fold(0, (most, run) => run.size > most ? run.size : most);
    final ratio = size / body;
    if (ratio < 1.2) return null;
    return ratio >= 1.8 ? 1 : ratio >= 1.45 ? 2 : 3;
  }

  /// A list item when the text starts with a marker and a tab, or [marker] is known from the format's list text.
  static ParagraphBlock? listItem(List<TextRun> runs, {required int indent, String marker = '', int level = -1}) {
    var content = runs;
    var found = marker.trim();
    if (found.isEmpty) {
      final match = _marker.firstMatch(runs.map((run) => run.text).join());
      if (match == null) return null;
      found = match.group(1)!;
      content = dropPrefix(runs, match.end);
    }
    final checked = switch (found) { '☐' || '□' => false, '☑' || '☒' => true, _ => null };
    final ordered = checked == null && !_bullet.hasMatch(found);
    return ParagraphBlock(content, kind: ParagraphKind.listItem, level: level, ordered: ordered, checked: checked, indent: indent);
  }

  static List<TextRun> dropPrefix(List<TextRun> runs, int count) {
    final out = <TextRun>[];
    var left = count;
    for (final run in runs) {
      if (left >= run.text.length) {
        left -= run.text.length;
        continue;
      }
      out.add(left > 0 ? run.copyWith(text: run.text.substring(left)) : run);
      left = 0;
    }
    return out;
  }
}
