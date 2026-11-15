import 'dart:io';
import 'dart:typed_data';

import 'cmark.dart';
import 'emoji.dart';
import 'highlighter.dart';
import 'html_scan.dart';
import 'image_info.dart';
import 'markdown_renderer.dart';
import 'page_builder.dart';
import 'zip_archive.dart';

/// Markdown to a Word document (.docx) built from the same parse as the preview: Word heading styles (so the
/// navigation pane shows the outline), real Word lists, tables, code blocks with the preview's highlighting, quotes
/// and GitHub alerts, links, and local images embedded at their size. Remote images, which Word would have to
/// download, keep their alt text.
abstract final class DocxWriter {
  static Uint8List document({required String markdown, required String title, String? baseDirectory}) {
    final builder = _Builder(baseDirectory);
    Cmark.withDocument(markdown, (root, _) => builder.blocks(root, const _Context()));
    return builder.package(title);
  }

  static const tokenColors = {
    'k': 'C2255C', 's': '0B4F8A', 'key': '0B4F8A', 'c': '7A7A80', 'n': '0B5CAD', 'attr': '0B5CAD', 'f': '6A3FC1', //
    't': '8A4B0B', 'meta': '8A4B0B', 'v': '9A4A00', 'tag': '1A7A3E', 'ins': '1A7F37', 'del': 'B42318', 'hunk': '88888E',
  };

  static const alertColors = {
    Alert.note: '0A5BD3', Alert.tip: '1A7F37', Alert.important: '7C3AED', Alert.warning: 'A15C07', Alert.caution: 'C81E1E',
  };
}

final class _Context {
  const _Context({
    this.listLevel = -1,
    this.numbering,
    this.quote,
    this.tight = false,
    this.center = false,
    this.taskBox = false,
  });

  final int listLevel;
  final int? numbering;
  final (String border, String text)? quote;
  final bool tight;
  final bool center;
  final bool taskBox;

  _Context copyWith({
    int? listLevel,
    int? Function()? numbering,
    (String, String)? quote,
    bool? tight,
    bool? center,
    bool? taskBox,
  }) =>
      _Context(
        listLevel: listLevel ?? this.listLevel,
        numbering: numbering == null ? this.numbering : numbering(),
        quote: quote ?? this.quote,
        tight: tight ?? this.tight,
        center: center ?? this.center,
        taskBox: taskBox ?? this.taskBox,
      );
}

final class _Run {
  const _Run({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.superscript = false,
    this.color,
  });

  final bool bold, italic, strike, code, superscript;
  final String? color;

  _Run copyWith({bool? bold, bool? italic, bool? strike, bool? code, bool? superscript, String? color}) => _Run(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        strike: strike ?? this.strike,
        code: code ?? this.code,
        superscript: superscript ?? this.superscript,
        color: color ?? this.color,
      );
}

typedef _Relationship = ({String id, String type, String target, bool external});

final class _Builder {
  _Builder(this.baseDirectory);

  final String? baseDirectory;
  final body = StringBuffer();
  var relationships = <_Relationship>[];
  var media = <(String, Uint8List)>[];
  final numberings = <(int, int)>[];
  final footnotes = <String>[];
  var drawingId = 0;

  // Blocks

  void blocks(Node parent, _Context context) {
    for (final node in parent.children) {
      block(node, context);
    }
  }

  void block(Node node, _Context context) {
    switch (node.type) {
      case NodeType.paragraph:
        paragraph(context.listLevel >= 0 ? 'ListParagraph' : null, context, inlines(node, quoteRun(context)));
      case NodeType.heading:
        paragraph('Heading${node.headingLevel}', context, inlines(node, const _Run()));
      case NodeType.blockQuote:
        quote(node, context);
      case NodeType.list:
        list(node, context);
      case NodeType.codeBlock:
        codeBlock(node, context);
      case NodeType.htmlBlock:
        htmlBlock(node.literal, context);
      case NodeType.thematicBreak:
        body.write('<w:p><w:pPr><w:pStyle w:val="Rule"/></w:pPr></w:p>');
      case NodeType.footnoteDefinition:
        final inner = _Builder(baseDirectory)
          ..relationships = relationships
          ..media = media
          ..drawingId = drawingId;
        final note = StringBuffer();
        for (final part in node.children) {
          if (part.type == NodeType.paragraph) note.write(inner.inlines(part, const _Run()));
        }
        relationships = inner.relationships;
        media = inner.media;
        drawingId = inner.drawingId;
        footnotes.add(note.toString());
      default:
        if (node.typeName == 'table') {
          table(node, context);
        } else {
          blocks(node, context);
        }
    }
  }

  _Run quoteRun(_Context context) => _Run(color: context.quote?.$2);

  /// Paragraph properties go in the order the schema requires (Word refuses a file otherwise): style, keepNext,
  /// numbering, borders, spacing, indentation, alignment.
  void paragraph(String? style, _Context context, String runs, {bool keepNext = false, bool noBorder = false}) {
    final properties = StringBuffer();
    if (style != null) properties.write('<w:pStyle w:val="$style"/>');
    if (keepNext) properties.write('<w:keepNext/>');
    if (context.listLevel >= 0 && context.numbering != null) {
      properties.write('<w:numPr><w:ilvl w:val="${context.listLevel}"/><w:numId w:val="${context.numbering}"/></w:numPr>');
    }
    if (context.quote case final quote?) {
      properties.write('<w:pBdr><w:left w:val="single" w:sz="18" w:space="10" w:color="${quote.$1}"/></w:pBdr>');
    } else if (noBorder) {
      properties.write('<w:pBdr><w:bottom w:val="nil"/></w:pBdr>');
    }
    if (context.tight) properties.write('<w:spacing w:after="40"/>');
    properties.write(indentation(context));
    if (context.center) properties.write('<w:jc w:val="center"/>');
    body.write('<w:p>${properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>'}$runs</w:p>');
  }

  String indentation(_Context context) {
    final quoteIndent = context.quote == null ? 0 : 300;
    if (context.listLevel >= 0) {
      final left = 360 * (context.listLevel + 1) + quoteIndent;
      if (context.numbering != null) return '<w:ind w:left="$left" w:hanging="300"/>';
      // A task box stands where the bullet would; continuation paragraphs align with the item text.
      return '<w:ind w:left="${context.taskBox ? left - 300 : left}"/>';
    }
    return quoteIndent > 0 ? '<w:ind w:left="$quoteIndent"/>' : '';
  }

  void quote(Node node, _Context context) {
    final alert = alertKind(node);
    if (alert != null) {
      final inner = context.copyWith(quote: (alert.$2, '111113'));
      paragraph(null, inner, run(alert.$1.title, _Run(bold: true, color: alert.$2)), keepNext: true);
      stripAlertMarker(node);
      blocks(node, inner);
    } else {
      blocks(node, context.copyWith(quote: ('D0D0D3', '4D4D53')));
    }
  }

  void list(Node node, _Context context) {
    final ordered = node.orderedList;
    numberings.add((ordered ? 2 : 1, ordered ? node.listStart : 1));
    final numbering = numberings.length;
    for (final entry in node.children) {
      final level = context.listLevel + 1 > 8 ? 8 : context.listLevel + 1;
      if (entry.typeName == 'tasklist') {
        // Task items show a box instead of a bullet, as on GitHub.
        final inner = context.copyWith(listLevel: level, tight: node.listTight, numbering: () => null);
        final box = entry.taskChecked ? '☑' : '☐';
        var first = true;
        for (final part in entry.children) {
          if (first && part.type == NodeType.paragraph) {
            paragraph('ListParagraph', inner.copyWith(taskBox: true),
                run('$box ', quoteRun(inner)) + inlines(part, quoteRun(inner)));
          } else {
            block(part, inner);
          }
          first = false;
        }
      } else {
        final inner = context.copyWith(listLevel: level, tight: node.listTight, numbering: () => numbering);
        var first = true;
        for (final part in entry.children) {
          // Only the first paragraph of an item carries its bullet; the rest align under its text.
          final partContext = !first && part.type != NodeType.list ? inner.copyWith(numbering: () => null) : inner;
          block(part, partContext);
          first = false;
        }
      }
    }
  }

  void codeBlock(Node node, _Context context) {
    final language = MarkdownRenderer.codeLanguage(node.fenceInfo);
    var code = node.literal;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    final runs = StringBuffer();
    for (final token in Highlighter.tokens(code, language)) {
      final style = _Run(code: true, color: DocxWriter.tokenColors[token.kind ?? '']);
      final lines = token.text.split('\n');
      for (var index = 0; index < lines.length; index++) {
        if (index > 0) runs.write('<w:r><w:br/></w:r>');
        if (lines[index].isNotEmpty) runs.write(run(lines[index], style, codeStyle: false));
      }
    }
    paragraph('Code', context.copyWith(numbering: () => null), runs.toString());
  }

  void table(Node node, _Context context) {
    final columns = node.tableColumns;
    final alignments = node.tableAlignments;
    final rows = StringBuffer();
    for (final current in node.children) {
      final header = current.typeName == 'table_header' || current.tableRowIsHeader;
      final cells = StringBuffer();
      var column = 0;
      for (final entry in current.children) {
        final alignment = column < alignments.length ? alignments[column] : 0;
        final align = switch (alignment) { 0x63 => 'center', 0x72 => 'right', _ => 'left' };
        final shade = header ? '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F0"/>' : '';
        cells.write('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>$shade</w:tcPr><w:p><w:pPr><w:pStyle w:val="TableText"/>'
            '<w:jc w:val="$align"/></w:pPr>${inlines(entry, _Run(bold: header))}</w:p></w:tc>');
        column += 1;
      }
      while (column < columns) {
        cells.write('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p/></w:tc>');
        column += 1;
      }
      rows.write('<w:tr>${header ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}$cells</w:tr>');
    }
    const border = 'w:val="single" w:sz="4" w:space="0" w:color="CFCFD2"';
    final grid = '<w:gridCol/>' * (columns > 1 ? columns : 1);
    body.write('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top $border/><w:left $border/>'
        '<w:bottom $border/><w:right $border/><w:insideH $border/><w:insideV $border/></w:tblBorders>'
        '<w:tblLayout w:type="autofit"/><w:tblCellMar><w:left w:w="110" w:type="dxa"/><w:right w:w="110" w:type="dxa"/>'
        '</w:tblCellMar></w:tblPr><w:tblGrid>$grid</w:tblGrid>$rows</w:tbl>');
    // Word needs a paragraph between two tables and after a table at the end of a cell or the body.
    body.write('<w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>');
  }

  /// Raw HTML blocks of READMEs: centred logos, badges, `<h1 align="center">`, `<details>`. One Markdown HTML block
  /// often holds several HTML paragraphs (it runs to the next blank line), so it is split at block tags. Tags are
  /// dropped, local images embedded, the text kept, `align="center"` honoured.
  void htmlBlock(String html, _Context context) {
    for (final segment in HtmlScan.segments(html)) {
      final inner = context.copyWith(center: segment.center);
      final runs = StringBuffer();
      for (final part in segment.parts) {
        switch (part) {
          case HtmlText(:final text):
            runs.write(run(text, const _Run()));
          case HtmlImage():
            runs.write(image(part.source, part.alt, part.width, part.height));
          case HtmlLineBreak():
            runs.write('<w:r><w:br/></w:r>');
        }
      }
      if (runs.isEmpty) continue;
      final level = segment.heading;
      if (level != null) {
        paragraph('Heading$level', inner, runs.toString(), noBorder: segment.center);
      } else {
        paragraph(null, inner, runs.toString());
      }
    }
  }

  // Inlines

  String inlines(Node parent, _Run style) {
    final out = StringBuffer();
    for (final node in parent.children) {
      out.write(inline(node, style));
    }
    return out.toString();
  }

  static final _lineBreakTag = RegExp(r'^<br\s*/?>$', caseSensitive: false);

  String inline(Node node, _Run style) {
    switch (node.type) {
      case NodeType.text:
        final value = node.literal;
        return run(Emoji.replacingShortcodes(value) ?? value, style);
      case NodeType.code:
        return run(node.literal, style.copyWith(code: true));
      case NodeType.softBreak:
        return run(' ', style);
      case NodeType.lineBreak:
        return '<w:r><w:br/></w:r>';
      case NodeType.emph:
        return inlines(node, style.copyWith(italic: true));
      case NodeType.strong:
        return inlines(node, style.copyWith(bold: true));
      case NodeType.link:
        final url = node.url;
        final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):').firstMatch(url)?.group(1)?.toLowerCase();
        if (!const {'http', 'https', 'mailto'}.contains(scheme)) return inlines(node, style);
        final content = inlines(node, style.copyWith(color: '0A5BD3'));
        final id = relationship('hyperlink', url, external: true);
        return '<w:hyperlink r:id="$id" w:history="1">$content</w:hyperlink>';
      case NodeType.image:
        final alt = node.children.map((part) => part.literal).join();
        return image(node.url, alt, null, null);
      case NodeType.htmlInline:
        final html = node.literal;
        if (_lineBreakTag.hasMatch(html)) return '<w:r><w:br/></w:r>';
        return HtmlScan.images(html).map((item) => image(item.source, item.alt, item.width, item.height)).join();
      case NodeType.footnoteReference:
        final label = node.literal;
        return run('[${label.isEmpty ? '${footnotes.length + 1}' : label}]', style.copyWith(superscript: true, color: '0A5BD3'));
      default:
        return inlines(node, node.typeName == 'strikethrough' ? style.copyWith(strike: true) : style);
    }
  }

  String run(String text, _Run style, {bool codeStyle = true}) {
    final properties = StringBuffer();
    if (style.code && codeStyle) properties.write('<w:rStyle w:val="InlineCode"/>');
    if (style.code && !codeStyle) properties.write('<w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/>');
    if (style.bold) properties.write('<w:b/>');
    if (style.italic) properties.write('<w:i/>');
    if (style.strike) properties.write('<w:strike/>');
    if (style.color case final color?) properties.write('<w:color w:val="$color"/>');
    if (style.superscript) properties.write('<w:vertAlign w:val="superscript"/>');
    return '<w:r>${properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>'}<w:t xml:space="preserve">${Xml.text(text)}</w:t></w:r>';
  }

  /// An image embedded at its own size (or the size the HTML gives), at most the text width. Images that are not
  /// local PNG, JPEG or GIF files keep their alt text.
  String image(String source, String alt, int? width, int? height) {
    const fallback = _Run(color: '88888E', italic: true);
    String alternative() => alt.isEmpty ? '' : run(alt, fallback);
    final base = baseDirectory;
    if (base == null) return alternative();
    final file = PageBuilder.localFile(source, base);
    if (file == null) return alternative();
    final ext = PageBuilder.extension(file.path);
    if (!const {'png', 'jpg', 'jpeg', 'gif'}.contains(ext)) return alternative();
    final Uint8List data;
    try {
      data = file.readAsBytesSync();
    } on FileSystemException {
      return alternative();
    }
    final info = ImageInfo.read(data);
    if (info == null || info.width <= 0 || info.height <= 0) return alternative();
    // Points: the HTML size, else the pixel size at the image's own density (72 dpi when it does not say).
    final dpi = info.dpi > 0 ? info.dpi : 72.0;
    var w = (width ?? 0).toDouble(), h = (height ?? 0).toDouble();
    final naturalW = info.width * 72 / dpi, naturalH = info.height * 72 / dpi;
    if (w == 0 && h == 0) {
      w = naturalW;
      h = naturalH;
    } else if (w == 0) {
      w = h * naturalW / naturalH;
    } else if (h == 0) {
      h = w * naturalH / naturalW;
    }
    const maxWidth = 6.3 * 72.0;
    if (w > maxWidth) {
      h = h * maxWidth / w;
      w = maxWidth;
    }
    final cx = (w * 12700).toInt(), cy = (h * 12700).toInt();
    final kind = ext == 'jpg' ? 'jpeg' : ext;
    final name = 'image${media.length + 1}.$kind';
    media.add((name, data));
    final id = relationship('image', 'media/$name', external: false);
    drawingId += 1;
    final description = Xml.attribute(alt);
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$drawingId" name="Picture $drawingId" descr="$description"/><wp:cNvGraphicFramePr>'
        '<a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic>'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr>'
        '<pic:cNvPr id="$drawingId" name="$name" descr="$description"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill>'
        '<a:blip r:embed="$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm>'
        '<a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  String relationship(String type, String target, {required bool external}) {
    final id = 'rId${relationships.length + 10}';
    relationships.add((id: id, type: type, target: target, external: external));
    return id;
  }

  // Helpers

  (Alert, String)? alertKind(Node quote) {
    final paragraph = quote.firstChild;
    if (paragraph == null || paragraph.type != NodeType.paragraph) return null;
    final marker = StringBuffer();
    var child = paragraph.firstChild;
    while (child != null && child.type == NodeType.text) {
      marker.write(child.literal);
      child = child.next;
    }
    if (child != null && child.type != NodeType.softBreak && child.type != NodeType.lineBreak) return null;
    final kind = Alert.fromMarker(marker.toString());
    if (kind == null) return null;
    return (kind, DocxWriter.alertColors[kind] ?? '88888E');
  }

  void stripAlertMarker(Node quote) {
    final paragraph = quote.firstChild;
    if (paragraph == null) return;
    for (var node = paragraph.firstChild; node != null && node.type == NodeType.text; node = paragraph.firstChild) {
      node.remove();
    }
    if (paragraph.firstChild case final node? when node.type == NodeType.softBreak || node.type == NodeType.lineBreak) {
      node.remove();
    }
    if (paragraph.firstChild == null) paragraph.remove();
  }

  // Package

  Uint8List package(String title) {
    final zip = ZipArchive();
    final types = StringBuffer('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>');
    final extensions = {for (final item in media) PageBuilder.extension(item.$1)}.toList()..sort();
    for (final ext in extensions) {
      types.write('<Default Extension="$ext" ContentType="image/$ext"/>');
    }
    types
      ..write('<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>')
      ..write('<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>')
      ..write('<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>')
      ..write('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>');
    zip
      ..addText('[Content_Types].xml', '${Xml.header}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">$types</Types>')
      ..addText('_rels/.rels', '${Xml.header}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '</Relationships>')
      ..addText('docProps/core.xml', '${Xml.header}<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${Xml.text(title)}</dc:title>'
          '<dc:creator>rotide.dm</dc:creator></cp:coreProperties>');
    final rels = StringBuffer('<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>');
    for (final rel in relationships) {
      rels.write('<Relationship Id="${rel.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/${rel.type}" '
          'Target="${Xml.attribute(rel.target)}"${rel.external ? ' TargetMode="External"' : ''}/>');
    }
    zip.addText('word/_rels/document.xml.rels',
        '${Xml.header}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>');
    for (final item in media) {
      zip.add('word/media/${item.$1}', item.$2);
    }
    zip
      ..addText('word/styles.xml', DocxParts.styles)
      ..addText('word/numbering.xml', DocxParts.numbering(numberings));
    final content = StringBuffer(body.toString());
    if (footnotes.isNotEmpty) {
      content.write('<w:p><w:pPr><w:pStyle w:val="Rule"/></w:pPr></w:p>');
      for (var index = 0; index < footnotes.length; index++) {
        content.write('<w:p><w:pPr><w:pStyle w:val="Footnote"/></w:pPr>${run('${index + 1}. ', const _Run())}${footnotes[index]}</w:p>');
      }
    }
    if (content.isEmpty) content.write('<w:p/>');
    zip.addText('word/document.xml', '${Xml.header}<w:document ${DocxParts.namespaces}><w:body>$content<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
        'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>');
    return zip.finish();
  }
}

/// Fixed parts of the package: styles in the preview's palette and the two list definitions.
abstract final class DocxParts {
  static const namespaces = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

  static String _heading(int level, int size, bool border, [String color = '111113']) {
    final rule = border ? '<w:pBdr><w:bottom w:val="single" w:sz="4" w:space="4" w:color="DADADC"/></w:pBdr>' : '';
    return '<w:style w:type="paragraph" w:styleId="Heading$level"><w:name w:val="heading $level"/><w:basedOn w:val="Normal"/>'
        '<w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/>$rule'
        '<w:spacing w:before="${level <= 2 ? 360 : 280}" w:after="140" w:line="240" w:lineRule="auto"/>'
        '<w:outlineLvl w:val="${level - 1}"/></w:pPr><w:rPr><w:b/><w:color w:val="$color"/><w:sz w:val="$size"/>'
        '<w:szCs w:val="$size"/></w:rPr></w:style>';
  }

  static final String styles = () {
    const font = '<w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue" w:eastAsia="Helvetica Neue" w:cs="Arial"/>';
    const mono = '<w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:eastAsia="Menlo" w:cs="Menlo"/>';
    return '${Xml.header}<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults>'
        '<w:rPrDefault><w:rPr>$font<w:color w:val="111113"/><w:sz w:val="22"/><w:szCs w:val="22"/>'
        '<w:lang w:val="ru-RU" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>'
        '<w:spacing w:after="140" w:line="288" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:rPr>$font</w:rPr></w:style>'
        '${_heading(1, 44, true)}${_heading(2, 34, true)}${_heading(3, 27, false)}${_heading(4, 22, false)}'
        '${_heading(5, 20, false)}${_heading(6, 20, false, '4D4D53')}'
        '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>'
        '<w:uiPriority w:val="34"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:contextualSpacing/></w:pPr></w:style>'
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F6F6F4"/><w:spacing w:before="60" w:after="200" w:line="252" '
        'w:lineRule="auto"/><w:ind w:left="140" w:right="140"/></w:pPr><w:rPr>$mono<w:sz w:val="18"/><w:szCs w:val="18"/>'
        '</w:rPr></w:style>'
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="TableText"><w:name w:val="Table Text"/>'
        '<w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="40" w:after="40" w:line="252" w:lineRule="auto"/></w:pPr></w:style>'
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Rule"><w:name w:val="Rule"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="DADADC"/></w:pBdr><w:spacing w:before="120" '
        'w:after="240"/></w:pPr><w:rPr><w:sz w:val="8"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Footnote"><w:name w:val="Footnote"/>'
        '<w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:color w:val="4D4D53"/>'
        '<w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style>'
        '<w:style w:type="character" w:customStyle="1" w:styleId="InlineCode"><w:name w:val="Inline Code"/><w:rPr>$mono'
        '<w:sz w:val="19"/><w:szCs w:val="19"/><w:shd w:val="clear" w:color="auto" w:fill="EFEFED"/></w:rPr></w:style>'
        '</w:styles>';
  }();

  /// Abstract list 1: bullets, 2: decimal with roman and letter sub-levels, as GitHub nests ordered lists.
  static String numbering(List<(int, int)> lists) {
    String levels({required bool ordered}) => [
          for (var level = 0; level < 9; level++)
            () {
              final left = 360 * (level + 1);
              final format = ordered ? const ['decimal', 'lowerRoman', 'lowerLetter'][level % 3] : 'bullet';
              final text = ordered ? '%${level + 1}.' : const ['•', '◦', '▪'][level % 3];
              return '<w:lvl w:ilvl="$level"><w:start w:val="1"/><w:numFmt w:val="$format"/><w:lvlText w:val="$text"/>'
                  '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="$left" w:hanging="300"/></w:pPr></w:lvl>';
            }(),
        ].join();
    final xml = StringBuffer('${Xml.header}<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">')
      ..write('<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>${levels(ordered: false)}</w:abstractNum>')
      ..write('<w:abstractNum w:abstractNumId="2"><w:multiLevelType w:val="hybridMultilevel"/>${levels(ordered: true)}</w:abstractNum>');
    for (var index = 0; index < lists.length; index++) {
      final (abstract, start) = lists[index];
      // Each list is its own instance so numbering restarts; the start override carries `3.` style starts.
      xml.write('<w:num w:numId="${index + 1}"><w:abstractNumId w:val="$abstract"/>');
      if (abstract == 2) xml.write('<w:lvlOverride w:ilvl="0"><w:startOverride w:val="$start"/></w:lvlOverride>');
      xml.write('</w:num>');
    }
    xml.write('</w:numbering>');
    return xml.toString();
  }
}
