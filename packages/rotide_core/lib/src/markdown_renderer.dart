import 'cmark.dart';
import 'emoji.dart';
import 'highlighter.dart';
import 'html_scan.dart';
import 'slugger.dart';

/// A heading of the document: the outline row and the anchor the preview scrolls to.
final class Heading {
  const Heading({required this.level, required this.title, required this.anchor, required this.line});

  final int level;
  final String title;

  /// GitHub-style anchor, unique in the document.
  final String anchor;

  /// 1-based source line, used to move the editor caret to the heading.
  final int line;

  @override
  bool operator ==(Object other) =>
      other is Heading && other.level == level && other.title == title && other.anchor == anchor && other.line == line;

  @override
  int get hashCode => Object.hash(level, title, anchor, line);

  @override
  String toString() => 'Heading($level, $title, #$anchor, line $line)';
}

final class RenderedMarkdown {
  const RenderedMarkdown({required this.html, required this.headings});

  /// Body HTML, without the page around it.
  final String html;
  final List<Heading> headings;

  static const empty = RenderedMarkdown(html: '', headings: []);
}

/// Markdown to HTML the way github.com renders a README: cmark-gfm with tables, strikethrough, autolinks, task
/// lists, footnotes and the tag filter, raw HTML kept (centered logos and badges are raw HTML), plus what GitHub adds
/// on top: heading anchors, alerts (`> [!NOTE]`), emoji shortcodes and highlighted code blocks.
abstract final class MarkdownRenderer {
  static RenderedMarkdown render(String markdown) => Cmark.withDocument(markdown, (root, parser) {
        final headings = _decorate(root);
        return RenderedMarkdown(html: Cmark.renderHtml(root, parser), headings: headings);
      });

  /// The document as plain text: markup removed, structure kept by line breaks.
  static String plainText(String markdown) => Cmark.withDocument(markdown, (root, _) {
        _simplifyForText(root);
        return Cmark.renderPlaintext(root);
      });

  static final _lineBreakTag = RegExp(r'^<br\s*/?>$', caseSensitive: false);

  /// What the plain text keeps of GitHub's additions: emoji, alert titles instead of `[!NOTE]`, the text of raw
  /// HTML (a centred `<h1>` title stays), strikethrough without tildes.
  static void _simplifyForText(Node root) {
    for (final node in root.descendants()) {
      switch (node.type) {
        case NodeType.text:
          _replaceEmoji(node);
        case NodeType.blockQuote:
          _titleAlert(node);
        case NodeType.htmlBlock:
          final text = HtmlScan.text(node.literal);
          if (text.isNotEmpty) {
            final paragraph = Node.create(NodeType.paragraph);
            final content = Node.create(NodeType.text)..literal = text;
            paragraph.appendChild(content);
            node.insertBefore(paragraph);
          }
          node.remove();
        case NodeType.htmlInline:
          if (_lineBreakTag.hasMatch(node.literal)) node.insertBefore(Node.create(NodeType.lineBreak));
          node.remove();
        default:
          if (node.typeName == 'strikethrough') {
            for (final child in node.children) {
              child.unlink();
              node.insertBefore(child);
            }
            node.remove();
          }
      }
    }
  }

  static void _titleAlert(Node quote) {
    final paragraph = quote.firstChild;
    if (paragraph == null || paragraph.type != NodeType.paragraph) return;
    final (marker, markerNodes, after) = _alertMarker(paragraph);
    if (after != null && after.type != NodeType.softBreak && after.type != NodeType.lineBreak) return;
    final kind = Alert.fromMarker(marker);
    if (kind == null) return;
    markerNodes.first.literal = kind.title;
    for (final node in markerNodes.skip(1)) {
      node.remove();
    }
    if (after != null && after.type == NodeType.softBreak) {
      after.insertBefore(Node.create(NodeType.lineBreak));
      after.remove();
    }
  }

  /// Text nodes from the start of a paragraph up to its first non-text node, joined, and that node.
  static (String, List<Node>, Node?) _alertMarker(Node paragraph) {
    final buffer = StringBuffer();
    final nodes = <Node>[];
    var child = paragraph.firstChild;
    while (child != null && child.type == NodeType.text) {
      buffer.write(child.literal);
      nodes.add(child);
      child = child.next;
    }
    return (buffer.toString(), nodes, child);
  }

  // GitHub additions

  static List<Heading> _decorate(Node root) {
    // Collect first: the tree must not change while the iterator walks it.
    final headings = <Node>[], quotes = <Node>[], code = <Node>[], texts = <Node>[];
    for (final node in root.descendants()) {
      switch (node.type) {
        case NodeType.heading:
          headings.add(node);
        case NodeType.blockQuote:
          quotes.add(node);
        case NodeType.codeBlock:
          code.add(node);
        case NodeType.text:
          texts.add(node);
      }
    }
    texts.forEach(_replaceEmoji);
    quotes.forEach(_makeAlert);
    code.forEach(_highlight);
    final slugger = Slugger();
    return [
      for (final node in headings)
        () {
          final title = _plainTitle(node);
          final anchor = slugger.slug(title);
          final link = Node.create(NodeType.htmlInline)
            ..literal = '<a class="anchor" id="$anchor" href="#$anchor" aria-hidden="true"></a>';
          node.prependChild(link);
          return Heading(level: node.headingLevel, title: title, anchor: anchor, line: node.startLine);
        }(),
    ];
  }

  static String _plainTitle(Node heading) {
    final title = StringBuffer();
    for (final node in heading.descendants()) {
      switch (node.type) {
        case NodeType.text || NodeType.code:
          title.write(node.literal);
        case NodeType.softBreak || NodeType.lineBreak:
          title.write(' ');
      }
    }
    return title.toString().trim();
  }

  static void _replaceEmoji(Node node) {
    final text = node.literal;
    if (!text.contains(':')) return;
    final replaced = Emoji.replacingShortcodes(text);
    if (replaced != null) node.literal = replaced;
  }

  /// `> [!NOTE]` on the first line of a quote turns it into a GitHub alert. The marker can arrive split into several
  /// text nodes (`[`, `!NOTE`, `]`), so the text up to the first line break is joined before matching.
  static void _makeAlert(Node quote) {
    final paragraph = quote.firstChild;
    if (paragraph == null || paragraph.type != NodeType.paragraph) return;
    final (marker, markerNodes, after) = _alertMarker(paragraph);
    final breakNode = after != null && (after.type == NodeType.softBreak || after.type == NodeType.lineBreak) ? after : null;
    if (after != null && breakNode == null) return;
    final kind = Alert.fromMarker(marker);
    if (kind == null) return;
    for (final node in markerNodes) {
      node.remove();
    }
    breakNode?.remove();
    if (paragraph.firstChild == null) paragraph.remove();

    final open = Node.create(NodeType.htmlBlock)
      ..literal = '<div class="markdown-alert markdown-alert-${kind.name}"><p class="markdown-alert-title">'
          '${kind.icon}${kind.title}</p>\n';
    quote.insertBefore(open);
    var anchor = open;
    for (final node in quote.children) {
      node.unlink();
      anchor.insertAfter(node);
      anchor = node;
    }
    final close = Node.create(NodeType.htmlBlock)..literal = '</div>\n';
    anchor.insertAfter(close);
    quote.remove();
  }

  static void _highlight(Node block) {
    final language = codeLanguage(block.fenceInfo, splitOnBrace: true);
    final html = Highlighter.html(block.literal, language);
    final attribute = language == null ? '' : ' data-lang="${Html.escape(language)}"';
    final codeClass = language == null ? '' : ' class="language-${Html.escape(language)}"';
    final replacement = Node.create(NodeType.htmlBlock)
      ..literal = '<div class="highlight"$attribute><pre><code$codeClass>$html</code></pre></div>\n';
    block.insertBefore(replacement);
    block.remove();
  }

  /// The language word of a fence info string, lowercased, or null.
  static String? codeLanguage(String info, {bool splitOnBrace = false}) {
    final word = info.split(splitOnBrace ? RegExp(r'[ {]') : RegExp(' ')).firstWhere((part) => part.isNotEmpty, orElse: () => '');
    return word.isEmpty ? null : word.toLowerCase();
  }
}

/// GitHub alert kinds. Titles stay in English as on github.com; the icons are drawn for rotide.dm.
enum Alert {
  note,
  tip,
  important,
  warning,
  caution;

  static Alert? fromMarker(String marker) {
    final trimmed = marker.trim();
    if (!trimmed.startsWith('[!') || !trimmed.endsWith(']')) return null;
    final name = trimmed.substring(2, trimmed.length - 1).toLowerCase();
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  String get title => name[0].toUpperCase() + name.substring(1);

  String get icon {
    final shape = switch (this) {
      note => '<circle cx="8" cy="8" r="6.25"/><path d="M8 7.25v4"/><path d="M8 4.9v.1"/>',
      tip => '<path d="M5.5 10.5c-1-.8-1.75-2-1.75-3.5a4.25 4.25 0 0 1 8.5 0c0 1.5-.75 2.7-1.75 3.5v1.25h-5z"/>'
          '<path d="M6.25 14h3.5"/>',
      important => '<path d="M2.25 3.25h11.5v8h-6.5l-3 2.5v-2.5h-2z"/><path d="M8 5.25v3"/><path d="M8 9.9v.1"/>',
      warning => '<path d="M8 2.25 14.25 13.5H1.75z"/><path d="M8 6.5v3"/><path d="M8 11.4v.1"/>',
      caution => '<path d="M5.5 1.75h5l3.75 3.75v5l-3.75 3.75h-5L1.75 10.5v-5z"/><path d="M8 5v3.5"/>'
          '<path d="M8 10.9v.1"/>',
    };
    return '<svg class="alert-icon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" fill="none" '
        'stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">$shape</svg>';
  }
}

abstract final class Html {
  static String escape(String text) {
    final out = StringBuffer();
    for (final unit in text.runes) {
      switch (unit) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0x22:
          out.write('&quot;');
        case 0x27:
          out.write('&#39;');
        default:
          out.writeCharCode(unit);
      }
    }
    return out.toString();
  }
}
