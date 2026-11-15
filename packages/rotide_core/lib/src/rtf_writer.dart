import 'cmark.dart';
import 'docx_writer.dart' show DocxWriter;
import 'emoji.dart';
import 'highlighter.dart';
import 'html_scan.dart';
import 'markdown_renderer.dart';

/// Markdown to RTF from the same parse as the preview, written directly so it is identical on macOS and Windows:
/// heading sizes, bold, italic, strikethrough, links, lists, quotes and alerts, tables with borders and code blocks
/// with the preview's token colours. Images keep their alt text: plain RTF has no portable way to hold them.
abstract final class RtfWriter {
  static String document({required String markdown, required String title}) {
    final writer = _Writer();
    Cmark.withDocument(markdown, (root, _) => writer.blocks(root, const _Block()));
    return writer.finish(title);
  }
}

/// Colour table; indices start at 1 in RTF (0 is "auto").
const _colors = [
  '111113', // 1 ink
  '4D4D53', // 2 text2
  '0A5BD3', // 3 link
  'F6F6F4', // 4 code fill
  'CFCFD2', // 5 table border
  '88888E', // 6 text3
  'F2F2F0', // 7 header fill
  'C2255C', '0B4F8A', '7A7A80', '0B5CAD', '6A3FC1', '8A4B0B', '9A4A00', '1A7A3E', '1A7F37', 'B42318', // 8...17 tokens
  '7C3AED', 'A15C07', 'C81E1E', // 18...20 alerts
  'D0D0D3', // 21 quote rule
];

int _color(String hex) => _colors.indexOf(hex.toUpperCase()) + 1;

final class _Block {
  const _Block({this.indent = 0, this.quoteColor, this.textColor});
  final int indent;
  final String? quoteColor;
  final String? textColor;
}

final class _Inline {
  const _Inline({this.bold = false, this.italic = false, this.strike = false, this.code = false, this.color, this.superscript = false});
  final bool bold, italic, strike, code, superscript;
  final String? color;

  _Inline copyWith({bool? bold, bool? italic, bool? strike, bool? code, String? color, bool? superscript}) => _Inline(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        strike: strike ?? this.strike,
        code: code ?? this.code,
        color: color ?? this.color,
        superscript: superscript ?? this.superscript,
      );
}

final class _Writer {
  final out = StringBuffer();
  final footnotes = <String>[];

  // Sizes in half-points, as in the stylesheet of the former AppKit export.
  static const _body = 22;
  static const _headings = [44, 34, 27, 22, 22, 22];

  void blocks(Node parent, _Block context) {
    for (final node in parent.children) {
      block(node, context);
    }
  }

  String _paragraphStart(_Block context, {int after = 160, int before = 0}) {
    final buffer = StringBuffer(r'\pard\plain');
    if (context.indent > 0) buffer.write('\\li${context.indent}');
    if (context.quoteColor case final color?) buffer.write('\\brdrl\\brdrs\\brdrw30\\brsp200\\brdrcf${_color(color)}');
    buffer.write('\\sb$before\\sa$after\\sl348\\slmult1\\f0\\fs$_body');
    if (context.textColor case final color?) buffer.write('\\cf${_color(color)}');
    buffer.write(' ');
    return buffer.toString();
  }

  void block(Node node, _Block context) {
    switch (node.type) {
      case NodeType.paragraph:
        out
          ..write(_paragraphStart(context))
          ..write(inlines(node, _Inline(color: context.textColor)))
          ..write('\\par\n');
      case NodeType.heading:
        final level = node.headingLevel.clamp(1, 6);
        out
          ..write(_paragraphStart(context, before: level <= 2 ? 280 : 240, after: level <= 2 ? 160 : 80))
          ..write('\\b\\fs${_headings[level - 1]}${level == 6 ? '\\cf2' : ''} ')
          ..write(inlines(node, const _Inline(bold: true)))
          ..write('\\par\n');
      case NodeType.blockQuote:
        quote(node, context);
      case NodeType.list:
        list(node, context);
      case NodeType.codeBlock:
        codeBlock(node, context);
      case NodeType.htmlBlock:
        for (final segment in HtmlScan.segments(node.literal)) {
          final text = segment.parts.map((part) => switch (part) {
                HtmlText(:final text) => escape(text),
                HtmlImage(:final alt) => alt.isEmpty ? '' : '{\\i\\cf6 ${escape(alt)}}',
                HtmlLineBreak() => '\\line ',
              }).join();
          if (text.trim().isEmpty) continue;
          final heading = segment.heading;
          out
            ..write(_paragraphStart(context))
            ..write(segment.center ? r'\qc ' : '')
            ..write(heading != null ? '\\b\\fs${_headings[heading.clamp(1, 6) - 1]} ' : '')
            ..write(text)
            ..write('\\par\n');
        }
      case NodeType.thematicBreak:
        out.write('\\pard\\plain\\brdrb\\brdrs\\brdrw10\\brdrcf5\\sb120\\sa240\\fs8\\par\n');
      case NodeType.footnoteDefinition:
        footnotes.add(node.children.where((part) => part.type == NodeType.paragraph).map((part) => inlines(part, const _Inline())).join(' '));
      default:
        if (node.typeName == 'table') {
          table(node, context);
        } else {
          blocks(node, context);
        }
    }
  }

  void quote(Node node, _Block context) {
    final paragraph = node.firstChild;
    Alert? alert;
    if (paragraph != null && paragraph.type == NodeType.paragraph) {
      final marker = StringBuffer();
      var child = paragraph.firstChild;
      while (child != null && child.type == NodeType.text) {
        marker.write(child.literal);
        child = child.next;
      }
      if (child == null || child.type == NodeType.softBreak || child.type == NodeType.lineBreak) {
        alert = Alert.fromMarker(marker.toString());
      }
    }
    if (alert != null) {
      final color = DocxWriter.alertColors[alert]!;
      final inner = _Block(indent: context.indent + 300, quoteColor: color, textColor: '111113');
      out.write('${_paragraphStart(inner, after: 60)}{\\b\\cf${_color(color)} ${alert.title}}\\par\n');
      for (var first = paragraph!.firstChild; first != null && first.type == NodeType.text; first = paragraph.firstChild) {
        first.remove();
      }
      if (paragraph.firstChild case final first? when first.type == NodeType.softBreak || first.type == NodeType.lineBreak) {
        first.remove();
      }
      if (paragraph.firstChild == null) paragraph.remove();
      blocks(node, inner);
    } else {
      blocks(node, _Block(indent: context.indent + 300, quoteColor: 'D0D0D3', textColor: '4D4D53'));
    }
  }

  void list(Node node, _Block context, [int depth = 0]) {
    var number = node.listStart;
    final ordered = node.orderedList;
    final left = context.indent + 360;
    for (final item in node.children) {
      final String marker;
      if (item.typeName == 'tasklist') {
        marker = item.taskChecked ? '☑' : '☐';
      } else if (ordered) {
        marker = '$number.';
      } else {
        marker = const ['•', '◦', '▪'][depth % 3];
      }
      number += 1;
      var first = true;
      for (final part in item.children) {
        if (part.type == NodeType.list) {
          list(part, _Block(indent: left, quoteColor: context.quoteColor, textColor: context.textColor), depth + 1);
        } else if (first && part.type == NodeType.paragraph) {
          out
            ..write(_paragraphStart(_Block(indent: left, quoteColor: context.quoteColor, textColor: context.textColor),
                after: node.listTight ? 40 : 120))
            ..write('\\fi-300 ${escape(marker)}\\tab ')
            ..write(inlines(part, _Inline(color: context.textColor)))
            ..write('\\par\n');
        } else {
          block(part, _Block(indent: left, quoteColor: context.quoteColor, textColor: context.textColor));
        }
        first = false;
      }
    }
  }

  void codeBlock(Node node, _Block context) {
    var code = node.literal;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    final language = MarkdownRenderer.codeLanguage(node.fenceInfo);
    final buffer = StringBuffer();
    for (final token in Highlighter.tokens(code, language)) {
      final color = DocxWriter.tokenColors[token.kind ?? ''];
      final text = token.text.split('\n').map(escape).join('\\line ');
      buffer.write(color == null ? text : '{\\cf${_color(color)} $text}');
    }
    out.write('\\pard\\plain\\li${context.indent + 140}\\ri140\\sb60\\sa200\\cbpat4\\f1\\fs19 $buffer\\par\n');
  }

  void table(Node node, _Block context) {
    final columns = node.tableColumns < 1 ? 1 : node.tableColumns;
    final alignments = node.tableAlignments;
    const width = 9000;
    final cell = width ~/ columns;
    for (final row in node.children) {
      final header = row.typeName == 'table_header' || row.tableRowIsHeader;
      out.write('\\trowd\\trgaph110\\trleft${context.indent}');
      for (var column = 1; column <= columns; column++) {
        out.write('${header ? r'\clcbpat7' : ''}\\clbrdrt\\brdrs\\brdrw10\\brdrcf5\\clbrdrl\\brdrs\\brdrw10\\brdrcf5'
            '\\clbrdrb\\brdrs\\brdrw10\\brdrcf5\\clbrdrr\\brdrs\\brdrw10\\brdrcf5\\cellx${context.indent + cell * column}');
      }
      var column = 0;
      for (final entry in row.children) {
        final alignment = column < alignments.length ? alignments[column] : 0;
        final align = switch (alignment) { 0x63 => r'\qc', 0x72 => r'\qr', _ => r'\ql' };
        out.write('\\pard\\intbl$align\\f0\\fs$_body ${inlines(entry, _Inline(bold: header))}\\cell ');
        column += 1;
      }
      while (column < columns) {
        out.write(r'\pard\intbl\cell ');
        column += 1;
      }
      out.write('\\row\n');
    }
    out.write('\\pard\\plain\\sa0\\fs8\\par\n');
  }

  String inlines(Node parent, _Inline style) => parent.children.map((node) => inline(node, style)).join();

  String inline(Node node, _Inline style) {
    switch (node.type) {
      case NodeType.text:
        final value = node.literal;
        return span(Emoji.replacingShortcodes(value) ?? value, style);
      case NodeType.code:
        return span(node.literal, style.copyWith(code: true));
      case NodeType.softBreak:
        return span(' ', style);
      case NodeType.lineBreak:
        return r'\line ';
      case NodeType.emph:
        return inlines(node, style.copyWith(italic: true));
      case NodeType.strong:
        return inlines(node, style.copyWith(bold: true));
      case NodeType.link:
        final url = node.url;
        final content = inlines(node, style.copyWith(color: '0A5BD3'));
        if (!RegExp(r'^(https?|mailto):', caseSensitive: false).hasMatch(url)) return inlines(node, style);
        return '{\\field{\\*\\fldinst{HYPERLINK "${escape(url).replaceAll('"', '%22')}"}}{\\fldrslt $content}}';
      case NodeType.image:
        final alt = node.children.map((part) => part.literal).join();
        return alt.isEmpty ? '' : span(alt, style.copyWith(italic: true, color: '88888E'));
      case NodeType.htmlInline:
        final html = node.literal;
        if (RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(html)) return r'\line ';
        return HtmlScan.images(html).where((image) => image.alt.isNotEmpty).map((image) => span(image.alt, style.copyWith(italic: true, color: '88888E'))).join();
      case NodeType.footnoteReference:
        final label = node.literal;
        return span('[${label.isEmpty ? '${footnotes.length + 1}' : label}]', style.copyWith(superscript: true, color: '0A5BD3'));
      default:
        return inlines(node, node.typeName == 'strikethrough' ? style.copyWith(strike: true) : style);
    }
  }

  String span(String text, _Inline style) {
    final codes = StringBuffer();
    if (style.bold) codes.write(r'\b');
    if (style.italic) codes.write(r'\i');
    if (style.strike) codes.write(r'\strike');
    if (style.superscript) codes.write(r'\super');
    if (style.code) codes.write(r'\f1\fs19\highlight4');
    if (style.color case final color?) codes.write('\\cf${_color(color)}');
    if (codes.isEmpty) return escape(text);
    return '{$codes ${escape(text)}}';
  }

  /// RTF escapes; non-ASCII as \uN with an ASCII fallback, surrogate pairs for characters past the BMP.
  static String escape(String text) {
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      if (unit == 0x5C || unit == 0x7B || unit == 0x7D) {
        buffer
          ..write('\\')
          ..writeCharCode(unit);
      } else if (unit == 0x0A) {
        buffer.write(r'\line ');
      } else if (unit == 0x09) {
        buffer.write(r'\tab ');
      } else if (unit < 0x80) {
        buffer.writeCharCode(unit);
      } else {
        buffer.write('\\u${unit > 0x7FFF ? unit - 0x10000 : unit}?');
      }
    }
    return buffer.toString();
  }

  String finish(String title) {
    final colorTable = _colors.map((hex) {
      final value = int.parse(hex, radix: 16);
      return '\\red${value >> 16}\\green${(value >> 8) & 0xFF}\\blue${value & 0xFF};';
    }).join();
    final notes = StringBuffer();
    if (footnotes.isNotEmpty) {
      notes.write('\\pard\\plain\\brdrb\\brdrs\\brdrw10\\brdrcf5\\sb120\\sa240\\fs8\\par\n');
      for (var index = 0; index < footnotes.length; index++) {
        notes.write('\\pard\\plain\\sa60\\f0\\fs19\\cf2 ${index + 1}. ${footnotes[index]}\\par\n');
      }
    }
    return '{\\rtf1\\ansi\\ansicpg1252\\uc1\\deff0'
        '{\\fonttbl{\\f0\\fswiss\\fcharset0 Helvetica Neue;}{\\f1\\fmodern\\fcharset0 Menlo;}}'
        '{\\colortbl;$colorTable}'
        '{\\info{\\title ${escape(title)}}{\\author rotide.dm}}'
        '\\viewkind4\\paperw11906\\paperh16838\\margl1134\\margr1134\\margt1134\\margb1134\n'
        '$out$notes}';
  }
}
