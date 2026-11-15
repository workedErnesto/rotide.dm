import 'dart:typed_data';

import 'markdown_builder.dart';
import 'xml_tree.dart';
import 'zip_archive.dart';

/// A Word document (.docx) as Markdown: headings (by style or outline level), bold, italic, strikethrough, inline and
/// block code (by style or a monospaced font), links, bulleted, numbered and task lists with nesting, quotes, tables and
/// rules. What Markdown cannot hold is left out: fonts, sizes, colours, alignment, images, comments, headers and
/// footers, footnotes, tracked deletions.
abstract final class DocxReader {
  static String markdown(Uint8List bytes) {
    final zip = ZipReader(bytes);
    final document = zip.text('word/document.xml');
    if (document == null) throw const FormatException('в файле нет текста документа Word');
    final reader = _Reader(
      styles: _Styles.parse(zip.text('word/styles.xml')),
      links: _links(zip.text('word/_rels/document.xml.rels')),
      numbering: _Numbering.parse(zip.text('word/numbering.xml')),
    );
    final body = XmlElement.parse(document).child('w:document')?.child('w:body');
    if (body != null) reader.blocks(body);
    return MarkdownBuilder.build(reader.finish());
  }

  static Map<String, String> _links(String? xml) {
    if (xml == null) return const {};
    final root = XmlElement.parse(xml).child('Relationships');
    return {
      for (final relationship in root?.all('Relationship') ?? const <XmlElement>[])
        if ((relationship['Type'] ?? '').endsWith('/hyperlink') && relationship['Id'] != null && relationship['Target'] != null)
          relationship['Id']!: relationship['Target']!,
    };
  }
}

/// `<w:b/>` and `<w:b w:val="true"/>` turn a property on, `w:val="0"`, `"false"` and `"off"` turn it off.
bool? _toggle(XmlElement? properties, String name) {
  final element = properties?.child(name);
  if (element == null) return null;
  final value = element['w:val'];
  return value == null || !const {'0', 'false', 'off', 'none'}.contains(value.toLowerCase());
}

const _monospaced = ['mono', 'courier', 'consolas', 'menlo', 'monaco', 'lucida console', 'source code', 'fira code', 'jetbrains'];

bool _isMonospaced(XmlElement? properties) {
  final fonts = properties?.child('w:rFonts');
  final name = (fonts?['w:ascii'] ?? fonts?['w:hAnsi'] ?? '').toLowerCase();
  return name.isNotEmpty && _monospaced.any(name.contains);
}

final class _Style {
  _Style({required this.name, this.basedOn, this.outline, this.bold, this.italic, this.strike, this.code = false, this.numbering, this.leftBorder = false, this.bottomBorder = false});
  final String name;
  final String? basedOn;
  final int? outline;
  final bool? bold;
  final bool? italic;
  final bool? strike;
  final bool code;
  final (String, int)? numbering;
  final bool leftBorder;
  final bool bottomBorder;
}

final class _Styles {
  _Styles(this._styles, {this.defaultSize = 0});
  final Map<String, _Style> _styles;

  /// Size of text without its own size, in half-points; 0 when the document does not say.
  final int defaultSize;

  static _Styles parse(String? xml) {
    final styles = <String, _Style>{};
    var defaultSize = 0;
    if (xml != null) {
      final root = XmlElement.parse(xml).child('w:styles');
      defaultSize = int.tryParse(root?.child('w:docDefaults')?.child('w:rPrDefault')?.child('w:rPr')?.child('w:sz')?['w:val'] ?? '') ?? 0;
      for (final style in root?.all('w:style') ?? const <XmlElement>[]) {
        final id = style['w:styleId'];
        if (id == null) continue;
        final paragraph = style.child('w:pPr');
        final run = style.child('w:rPr');
        final name = (style.child('w:name')?['w:val'] ?? id).toLowerCase();
        final outline = int.tryParse(paragraph?.child('w:outlineLvl')?['w:val'] ?? '');
        final numPr = paragraph?.child('w:numPr');
        final numId = numPr?.child('w:numId')?['w:val'];
        final borders = paragraph?.child('w:pBdr');
        styles[id] = _Style(
          name: name,
          basedOn: style.child('w:basedOn')?['w:val'],
          outline: outline,
          bold: _toggle(run, 'w:b'),
          italic: _toggle(run, 'w:i'),
          strike: _toggle(run, 'w:strike'),
          code: name.contains('code') || name.contains('preformatted') || name == 'plain text' || _isMonospaced(run),
          numbering: numId == null ? null : (numId, int.tryParse(numPr?.child('w:ilvl')?['w:val'] ?? '') ?? 0),
          leftBorder: _border(borders?.child('w:left')),
          bottomBorder: _border(borders?.child('w:bottom')),
        );
      }
    }
    return _Styles(styles, defaultSize: defaultSize);
  }

  static bool _border(XmlElement? side) => side != null && !const {'nil', 'none'}.contains(side['w:val']);

  /// The style and the ones it is based on, nearest first.
  Iterable<_Style> chain(String? id) sync* {
    final seen = <String>{};
    var current = id;
    while (current != null && seen.add(current)) {
      final style = _styles[current];
      if (style == null) return;
      yield style;
      current = style.basedOn;
    }
  }

  T? first<T>(String? id, T? Function(_Style style) value) {
    for (final style in chain(id)) {
      final result = value(style);
      if (result != null) return result;
    }
    return null;
  }

  int? headingLevel(String? id) {
    for (final style in chain(id)) {
      if (style.name == 'title') return 1;
      final named = RegExp(r'^heading (\d)$').firstMatch(style.name);
      if (named != null) return int.parse(named.group(1)!);
      if (style.outline case final outline? when outline < 9) return outline + 1;
    }
    return null;
  }
}

final class _Numbering {
  _Numbering(this._formats);

  /// numId to the formats of its levels.
  final Map<String, Map<int, String>> _formats;

  static _Numbering parse(String? xml) {
    if (xml == null) return _Numbering(const {});
    final root = XmlElement.parse(xml).child('w:numbering');
    final abstract = <String, Map<int, String>>{};
    for (final definition in root?.all('w:abstractNum') ?? const <XmlElement>[]) {
      final id = definition['w:abstractNumId'];
      if (id == null) continue;
      abstract[id] = {
        for (final level in definition.all('w:lvl'))
          int.tryParse(level['w:ilvl'] ?? '') ?? 0: level.child('w:numFmt')?['w:val'] ?? 'bullet',
      };
    }
    final formats = <String, Map<int, String>>{};
    for (final instance in root?.all('w:num') ?? const <XmlElement>[]) {
      final id = instance['w:numId'];
      final source = instance.child('w:abstractNumId')?['w:val'];
      if (id != null && source != null) formats[id] = abstract[source] ?? const {};
    }
    return _Numbering(formats);
  }

  /// Null when the paragraph is not a list item ("none" format or numbering 0).
  bool? ordered(String numId, int level) {
    if (numId == '0') return null;
    final format = _formats[numId]?[level] ?? 'bullet';
    if (format == 'none') return null;
    return format != 'bullet';
  }
}

final class _Reader {
  _Reader({required this.styles, required this.links, required this.numbering});
  final _Styles styles;
  final Map<String, String> links;
  final _Numbering numbering;
  final out = <DocumentBlock>[];

  /// Paragraphs that may be headings drawn as large bold text; decided once the body size is known.
  final _candidates = <int, List<TextRun>>{};

  List<DocumentBlock> finish() {
    final body = DrawnLayout.bodySize(out.whereType<ParagraphBlock>().expand((block) => block.runs));
    for (final MapEntry(key: index, value: runs) in _candidates.entries) {
      final level = DrawnLayout.heading(runs, body);
      if (level != null) out[index] = ParagraphBlock(runs, kind: ParagraphKind.heading, level: level);
    }
    return out;
  }

  void blocks(XmlElement parent) {
    for (final element in parent.elements) {
      switch (element.name) {
        case 'w:p':
          paragraph(element);
        case 'w:tbl':
          out.add(TableBlock(table(element)));
        case 'w:sdt':
          final content = element.child('w:sdtContent');
          if (content != null) blocks(content);
        case 'w:customXml' || 'w:ins' || 'w:smartTag':
          blocks(element);
      }
    }
  }

  List<List<List<List<TextRun>>>> table(XmlElement table) => [
        for (final row in table.all('w:tr'))
          [
            for (final cell in row.all('w:tc'))
              [
                for (final part in cell.elements)
                  if (part.name == 'w:p')
                    runs(part, styleCode: styles.first(part.child('w:pPr')?.child('w:pStyle')?['w:val'], (style) => style.code ? true : null) ?? false)
                  else if (part.name == 'w:tbl')
                    for (final nested in this.table(part))
                      for (final nestedCell in nested) ...nestedCell,
              ],
          ],
      ];

  void paragraph(XmlElement element) {
    final properties = element.child('w:pPr');
    final styleId = properties?.child('w:pStyle')?['w:val'];
    final styleCode = styles.first(styleId, (style) => style.code ? true : null) ?? false;
    final content = runs(element, styleCode: styleCode);
    final text = content.map((run) => run.text).join();

    if (text.trim().isEmpty) {
      final borders = properties?.child('w:pBdr');
      final rule = (borders != null && _Styles._border(borders.child('w:bottom'))) || (styles.first(styleId, (style) => style.bottomBorder ? true : null) ?? false);
      if (rule) out.add(const RuleBlock());
      return;
    }

    // Code: a code style, or every character in a monospaced font.
    if (styleCode || content.every((run) => run.code || run.text.trim().isEmpty)) {
      out.add(CodeBlock(text));
      return;
    }

    final outline = int.tryParse(properties?.child('w:outlineLvl')?['w:val'] ?? '');
    final heading = outline != null && outline < 9 ? outline + 1 : styles.headingLevel(styleId);
    if (heading != null) {
      out.add(ParagraphBlock(content, kind: ParagraphKind.heading, level: heading.clamp(1, 6)));
      return;
    }

    final numPr = properties?.child('w:numPr');
    final numId = numPr?.child('w:numId')?['w:val'];
    final listing = numId != null ? (numId, int.tryParse(numPr?.child('w:ilvl')?['w:val'] ?? '') ?? 0) : styles.first(styleId, (style) => style.numbering);
    if (listing != null) {
      final ordered = numbering.ordered(listing.$1, listing.$2);
      if (ordered != null) {
        out.add(_listItem(content, level: listing.$2, ordered: ordered));
        return;
      }
    }

    final indent = int.tryParse(properties?.child('w:ind')?['w:left'] ?? properties?.child('w:ind')?['w:start'] ?? '') ?? 0;
    final drawn = DrawnLayout.listItem(content, indent: indent) ?? _ballot(content, indent);
    if (drawn != null) {
      out.add(drawn);
      return;
    }

    final quoteStyle = styles.first(styleId, (style) => style.name.contains('quote') || style.leftBorder ? true : null) ?? false;
    final leftBorder = properties?.child('w:pBdr')?.child('w:left');
    if (quoteStyle || (leftBorder != null && _Styles._border(leftBorder))) {
      out.add(ParagraphBlock(content, kind: ParagraphKind.quote));
      return;
    }
    _candidates[out.length] = content;
    out.add(ParagraphBlock(content));
  }

  /// A paragraph that starts with a ballot box is a task, as rotide.dm writes task items.
  static ParagraphBlock? _ballot(List<TextRun> content, int indent) {
    if (content.isEmpty || !RegExp(r'^\s*[☐☑☒]').hasMatch(content.first.text)) return null;
    final item = _listItem(content, level: -1, ordered: false);
    return ParagraphBlock(item.runs, kind: ParagraphKind.listItem, level: -1, checked: item.checked, indent: indent);
  }

  /// rotide.dm writes task items as a ballot box before the text.
  static ParagraphBlock _listItem(List<TextRun> content, {required int level, required bool ordered}) {
    if (content.isNotEmpty) {
      final first = content.first.text;
      final match = RegExp(r'^\s*([☐☑☒])\s*').firstMatch(first);
      if (match != null) {
        final rest = [content.first.copyWith(text: first.substring(match.end)), ...content.skip(1)];
        return ParagraphBlock(rest, kind: ParagraphKind.listItem, level: level, ordered: ordered, checked: match.group(1) != '☐');
      }
    }
    return ParagraphBlock(content, kind: ParagraphKind.listItem, level: level, ordered: ordered);
  }

  List<TextRun> runs(XmlElement parent, {bool styleCode = false, String? link}) {
    final out = <TextRun>[];
    for (final element in parent.elements) {
      switch (element.name) {
        case 'w:r':
          out.addAll(run(element, link: link, styleCode: styleCode));
        case 'w:hyperlink':
          final target = element['r:id'] == null ? null : links[element['r:id']];
          out.addAll(runs(element, styleCode: styleCode, link: target ?? link));
        case 'w:ins' || 'w:smartTag' || 'w:fldSimple' || 'w:customXml' || 'w:dir' || 'w:bdo':
          out.addAll(runs(element, styleCode: styleCode, link: link));
        case 'w:sdt':
          final content = element.child('w:sdtContent');
          if (content != null) out.addAll(runs(content, styleCode: styleCode, link: link));
      }
    }
    return out;
  }

  Iterable<TextRun> run(XmlElement element, {String? link, bool styleCode = false}) sync* {
    final properties = element.child('w:rPr');
    final characterStyle = properties?.child('w:rStyle')?['w:val'];
    final bold = _toggle(properties, 'w:b') ?? styles.first(characterStyle, (style) => style.bold) ?? false;
    final italic = _toggle(properties, 'w:i') ?? styles.first(characterStyle, (style) => style.italic) ?? false;
    final strike = _toggle(properties, 'w:strike') ?? _toggle(properties, 'w:dstrike') ?? styles.first(characterStyle, (style) => style.strike) ?? false;
    final size = int.tryParse(properties?.child('w:sz')?['w:val'] ?? '') ?? styles.defaultSize;
    final code = styleCode || _isMonospaced(properties) || (styles.first(characterStyle, (style) => style.code ? true : null) ?? false);
    final text = StringBuffer();
    for (final part in element.elements) {
      switch (part.name) {
        case 'w:t':
          text.write(part.text);
        case 'w:tab' || 'w:ptab':
          text.write('\t');
        case 'w:br':
          final type = part['w:type'];
          if (type == null || type == 'textWrapping') text.write('\n');
        case 'w:cr':
          text.write('\n');
        case 'w:noBreakHyphen':
          text.write('‑');
        case 'w:softHyphen':
          break;
      }
    }
    if (text.isEmpty) return;
    yield TextRun(text.toString(), bold: bold, italic: italic, strike: strike, code: code, link: link, size: size);
  }
}
