import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_core/src/zip_archive.dart';
import 'package:test/test.dart';

void main() {
  group('renderer', () {
    test('tables, strikethrough, tasks and autolinks', () {
      final html = MarkdownRenderer.render('| a | b |\n|---|:-:|\n| 1 | 2 |\n\n~~old~~ www.example.com\n\n- [x] done\n- [ ] todo').html;
      expect(html, contains('<table>'));
      expect(html, contains('<th align="center">b</th>'));
      expect(html, contains('<del>old</del>'));
      expect(html, contains('<a href="http://www.example.com">www.example.com</a>'));
      expect(html, contains('type="checkbox" checked="" disabled=""'));
    });

    test('raw HTML is kept but dangerous tags are filtered', () {
      final html = MarkdownRenderer.render('<p align="center"><img src="logo.png" width="80"></p>\n\n<script>alert(1)</script>').html;
      expect(html, contains('<p align="center"><img src="logo.png" width="80"></p>'));
      expect(html, isNot(contains('<script>')));
    });

    test('heading anchors follow GitHub', () {
      final rendered = MarkdownRenderer.render('# Hello, World!\n\n## Установка и запуск\n\n## Hello, World!\n\n### `code` part');
      expect(rendered.headings.map((h) => h.anchor), ['hello-world', 'установка-и-запуск', 'hello-world-1', 'code-part']);
      expect(rendered.headings.map((h) => h.level), [1, 2, 2, 3]);
      expect(rendered.headings.map((h) => h.line), [1, 3, 5, 7]);
      expect(rendered.headings[3].title, 'code part');
      expect(rendered.html,
          contains('<h1><a class="anchor" id="hello-world" href="#hello-world" aria-hidden="true"></a>Hello, World!</h1>'));
    });

    test('alerts', () {
      final html = MarkdownRenderer.render('> [!WARNING]\n> Back up first.\n\n> [!tip]\n>\n> Second paragraph.\n\n> Plain quote [!NOTE]').html;
      expect(html, contains('markdown-alert markdown-alert-warning'));
      expect(html, contains('Warning</p>'));
      expect(html, contains('<p>Back up first.</p>'));
      expect(html, contains('markdown-alert-tip'));
      expect(html, contains('<p>Second paragraph.</p>'));
      expect(html, contains('<blockquote>\n<p>Plain quote [!NOTE]</p>'));
      expect(html, isNot(contains('[!WARNING]')));
    });

    test('emoji outside code', () {
      expect(MarkdownRenderer.render('Ship it :rocket: :unknown: `:tada:`').html, contains('Ship it 🚀 :unknown: <code>:tada:</code>'));
      expect(Emoji.replacingShortcodes('time 10:30 :tada:'), 'time 10:30 🎉');
    });

    test('footnotes', () {
      final html = MarkdownRenderer.render('Text[^1].\n\n[^1]: The note.').html;
      expect(html, contains('class="footnotes"'));
      expect(html, contains('The note.'));
    });

    test('code blocks are highlighted', () {
      final html = MarkdownRenderer.render('```swift\nlet x = "hi" // note\n```\n\n```\n<b>\n```').html;
      expect(html, contains('<div class="highlight" data-lang="swift"><pre><code class="language-swift">'));
      expect(html, contains('<span class="tok-k">let</span>'));
      expect(html, contains('<span class="tok-s">&quot;hi&quot;</span>'));
      expect(html, contains('<span class="tok-c">// note</span>'));
      expect(html, contains('<div class="highlight"><pre><code>&lt;b&gt;\n</code></pre></div>'));
    });

    test('plain text', () {
      final text = MarkdownRenderer.plainText('# Title\n\nSome **bold** and [link](https://a.b).\n\n- one\n- two');
      expect(text, contains('Title'));
      expect(text, contains('Some bold and link.'));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('https://a.b')));
    });

    test('plain text keeps GitHub additions readable', () {
      final text = MarkdownRenderer.plainText(
          '<h1 align="center">Logo &amp; title</h1>\n\n> [!NOTE]\n> Read this.\n\nShip :rocket: ~~old~~ new');
      expect(text, contains('Logo & title'));
      expect(text, contains('Note\nRead this.'));
      expect(text, isNot(contains('[!NOTE]')));
      expect(text, contains('Ship 🚀 old new'));
    });
  });

  group('highlighter', () {
    test('languages', () {
      expect(Highlighter.html('def f(x):\n    return None  # done', 'python'), contains('<span class="tok-c"># done</span>'));
      expect(Highlighter.html('{"name": "rotide", "n": 2}', 'json'), contains('<span class="tok-key">&quot;name&quot;</span>'));
      expect(Highlighter.html(r'echo $HOME # where', 'bash'), contains(r'<span class="tok-v">$HOME</span>'));
      expect(Highlighter.html('SELECT id FROM users', 'sql'), contains('<span class="tok-k">SELECT</span>'));
      expect(Highlighter.html('<a href="x">t</a>', 'html'), contains('<span class="tok-attr">href</span>'));
      expect(Highlighter.html('+added\n-removed', 'diff'), contains('<span class="tok-del">-removed</span>'));
      expect(Highlighter.html('<x>', 'brainfudge'), '&lt;x&gt;');
    });

    test('unterminated string stops at line end', () {
      expect(Highlighter.html('let s = "open\nlet t = 1', 'swift'), contains('<span class="tok-k">let</span> t'));
    });
  });

  group('page', () {
    test('slugger', () {
      final slugger = Slugger();
      expect(slugger.slug('API v2.0 (beta)'), 'api-v20-beta');
      expect(slugger.slug('a'), 'a');
      expect(slugger.slug('a'), 'a-1');
      expect(slugger.slug('a-1'), 'a-1-1');
    });

    test('inline local images', () {
      final folder = Directory.systemTemp.createTempSync('rotide');
      addTearDown(() => folder.deleteSync(recursive: true));
      Directory('${folder.path}/img').createSync();
      File('${folder.path}/img/a b.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
      const html = '<img src="img/a%20b.png" alt="x"><img src=\'https://example.com/x.png\'><img src="missing.png">';
      final inlined = PageBuilder.inlineLocalMedia(html, folder.path);
      expect(inlined, contains('src="data:image/png;base64,iVBORw=="'));
      expect(inlined, contains("src='https://example.com/x.png'"));
      expect(inlined, contains('src="missing.png"'));
    });

    test('stats', () {
      final stats = TextStats('Привет, мир! Hello world');
      expect(stats.words, 4);
      expect(stats.readingMinutes, 1);
      expect(TextStats('').readingMinutes, 0);
    });
  });

  group('docx', () {
    test('package parts', () {
      final folder = Directory.systemTemp.createTempSync('rotide');
      addTearDown(() => folder.deleteSync(recursive: true));
      File('${folder.path}/dot.png').writeAsBytesSync(
          base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
      const markdown = '# Title & co\n\n![dot](dot.png) [link](https://example.com)\n\n- a\n  1. b\n- [x] done\n\n'
          '| x | y |\n|---|--:|\n| 1 | 2 |\n\n> [!TIP]\n> Hint\n\n```swift\nlet a = 1\n```';
      final data = DocxWriter.document(markdown: markdown, title: 'T', baseDirectory: folder.path);
      expect(data.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final text = utf8.decode(data, allowMalformed: true);
      for (final part in ['[Content_Types].xml', 'word/document.xml', 'word/styles.xml', 'word/numbering.xml', 'word/media/image1.png', 'word/_rels/document.xml.rels']) {
        expect(text, contains(part), reason: part);
      }
      expect(text, contains('<w:pStyle w:val="Heading1"/>'));
      expect(text, contains('Title &amp; co'));
      expect(text, contains('TargetMode="External"'));
      expect(text, contains('<w:tbl>'));
      expect(text, contains('<w:jc w:val="right"/>'));
      expect(text, contains('☑ '));
      expect(text, contains('>Tip<'));
      expect(text, contains('<w:color w:val="C2255C"/></w:rPr><w:t xml:space="preserve">let</w:t>'));
      expect(text, contains('<w:ilvl w:val="1"/>'));
    });

    test('HTML block splits into paragraphs', () {
      final segments = HtmlScan.segments('<p align="center"><img src="a.png" alt="logo"></p>\n<h1 align="center">Name &amp; co</h1>\n<p>plain<br>text</p>');
      expect(segments, hasLength(3));
      expect(segments[0].center, isTrue);
      expect(segments[1].heading, 1);
      expect(segments[1].center, isTrue);
      expect((segments[1].parts.first as dynamic).text, 'Name & co');
      expect(segments[2].center, isFalse);
      expect(segments[2].parts, hasLength(3));
    });

    test('CRC32', () => expect(Crc32.checksum(utf8.encode('123456789')), 0xCBF43926));
  });

  group('rtf', () {
    test('document structure and escapes', () {
      final rtf = RtfWriter.document(
          markdown: '# Заголовок {x}\n\n**bold** [link](https://a.b)\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet a = 1\n```',
          title: 'T');
      expect(rtf, startsWith(r'{\rtf1'));
      expect(rtf, endsWith('}'));
      expect(rtf, contains(r'\u1047?'));
      expect(rtf, contains(r'\{x\}'));
      expect(rtf, contains('HYPERLINK "https://a.b"'));
      expect(rtf, contains(r'\trowd'));
      expect(rtf, contains(r'{\cf8 let}'));
      expect('{'.allMatches(rtf).length - r'\{'.allMatches(rtf).length, '}'.allMatches(rtf).length - r'\}'.allMatches(rtf).length);
    });
  });

  group('reading other formats', () {
    const markdown = '# Title\n\nSome **bold** and *it* and ~~gone~~, [link](https://example.com), `code`, a_b.\n\n## Lists\n\n'
        '- one\n- two\n  - nested\n- [x] done\n\n1. first\n2. second\n\n> quoted text\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n'
        '```swift\nlet x = 1\nprint(x)\n```\n\n---\n\nEnd.\n';

    void expectSameStructure(String read) {
      expect(read, startsWith('# Title\n\nSome **bold** and *it* and ~~gone~~, [link](https://example.com), `code`, a_b.\n\n## Lists\n\n'));
      expect(read, contains('- one\n- two\n  - nested\n- [x] done\n'));
      expect(read, contains('1. first\n2. second'));
      expect(read, contains('> quoted text'));
      expect(read, contains('| a | b |\n| --- | --- |\n| 1 | 2 |'));
      expect(read, contains('```\nlet x = 1\nprint(x)\n```'));
      expect(read, contains('---\n\nEnd.\n'));
      // The Markdown renders to the same blocks as the original.
      final html = MarkdownRenderer.render(read).html;
      expect(html, contains('<del>gone</del>'));
      expect(html, contains('<table>'));
      expect('<li>'.allMatches(html).length, 6);
    }

    test('Word written by rotide.dm reads back as the same Markdown', () {
      expectSameStructure(DocxReader.markdown(DocxWriter.document(markdown: markdown, title: 'T')));
    });

    test('RTF written by rotide.dm reads back as the same Markdown', () {
      expectSameStructure(RtfReader.markdown(RtfWriter.document(markdown: markdown, title: 'T')));
    });

    test('deflated Word package with styles, numbering and drawn structure', () {
      const w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
      const document = '<?xml version="1.0"?><w:document $w><w:body>'
          '<w:p><w:pPr><w:pStyle w:val="1"/></w:pPr><w:r><w:t>Глава</w:t></w:r></w:p>'
          '<w:p><w:r><w:rPr><w:b/><w:sz w:val="40"/></w:rPr><w:t>Big bold</w:t></w:r></w:p>'
          '<w:p><w:r><w:t xml:space="preserve">Text with </w:t></w:r><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>plain</w:t></w:r>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"> bold </w:t></w:r><w:hyperlink r:id="rId9"><w:r><w:t>site</w:t></w:r></w:hyperlink>'
          '<w:del><w:r><w:delText>removed</w:delText></w:r></w:del><w:r><w:br/><w:t>next &amp; line</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="3"/></w:numPr></w:pPr><w:r><w:t>numbered</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr></w:pPr><w:r><w:t>inner</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:ind w:left="720"/></w:pPr><w:r><w:tab/><w:t>•</w:t><w:tab/><w:t>drawn</w:t></w:r></w:p>'
          '<w:p><w:r><w:rPr><w:rFonts w:ascii="Courier New"/></w:rPr><w:t>mono()</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>*not* # markup</w:t></w:r></w:p>'
          '<w:sectPr/></w:body></w:document>';
      const styles = '<w:styles $w><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:styleId="1"><w:name w:val="heading 1"/></w:style></w:styles>';
      const numbering = '<w:numbering $w><w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl>'
          '<w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum><w:num w:numId="3"><w:abstractNumId w:val="7"/></w:num></w:numbering>';
      const relationships = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
          'Target="https://example.com/a b" TargetMode="External"/></Relationships>';
      final parts = {'word/document.xml': document, 'word/styles.xml': styles, 'word/numbering.xml': numbering, 'word/_rels/document.xml.rels': relationships};
      final archive = BytesBuilder();
      final directory = BytesBuilder();
      void add(BytesBuilder to, int bytes, int value) {
        final data = ByteData(bytes);
        bytes == 2 ? data.setUint16(0, value, Endian.little) : data.setUint32(0, value, Endian.little);
        to.add(data.buffer.asUint8List());
      }
      for (final MapEntry(key: name, value: content) in parts.entries) {
        final raw = utf8.encode(content);
        final packed = ZLibEncoder(raw: true).convert(raw);
        final offset = archive.length;
        final nameBytes = utf8.encode(name);
        for (final (builder, central) in [(archive, false), (directory, true)]) {
          add(builder, 4, central ? 0x02014b50 : 0x04034b50);
          if (central) add(builder, 2, 20);
          for (final value in [20, 0, 8, 0, 0]) {
            add(builder, 2, value);
          }
          add(builder, 4, Crc32.checksum(raw));
          add(builder, 4, packed.length);
          add(builder, 4, raw.length);
          add(builder, 2, nameBytes.length);
          add(builder, 2, 0);
          if (central) {
            for (final value in [0, 0, 0]) {
              add(builder, 2, value);
            }
            add(builder, 4, 0);
            add(builder, 4, offset);
          }
          builder.add(nameBytes);
          if (!central) builder.add(packed);
        }
      }
      final start = archive.length;
      final size = directory.length;
      archive.add(directory.takeBytes());
      add(archive, 4, 0x06054b50);
      for (final value in [0, 0, parts.length, parts.length]) {
        add(archive, 2, value);
      }
      add(archive, 4, size);
      add(archive, 4, start);
      add(archive, 2, 0);

      final read = DocxReader.markdown(archive.takeBytes());
      expect(
          read,
          '# Глава\n\n# Big bold\n\nText with plain **bold** [site](<https://example.com/a b>)\\\nnext & line\n\n'
          '1. numbered\n   - inner\n- drawn\n\n```\nmono()\n```\n\n\\*not\\* # markup\n');
    });

    test('RTF from TextEdit: code page, Unicode, lists, fields and tables', () {
      const rtf = r'''{\rtf1\ansi\ansicpg1251\cocoartf2822{\fonttbl\f0\fswiss Helvetica;\f1\fmodern Menlo-Regular;}'''
          r'''{\colortbl;\red0\green0\blue0;}{\*\expandedcolortbl;;}{\info{\title secret}}'''
          r'''\pard\f0\fs24 \b\fs48 \u1047?\'e0\'e3\'ee\'eb\'ee\'e2\'ee\'ea\b0\fs24 \par'''
          r'''\pard \'cf\'f0\'e8\'e2\'e5\'f2, {\i \u1084\'3f\'e8\'f0} {\field{\*\fldinst{HYPERLINK "https://example.com/"}}{\fldrslt link}}\par'''
          r'''\pard\li720\fi-720\ls1\ilvl0{\listtext\uc0\u8226 \tab}one\par'''
          r'''{\listtext\uc0\u8226 \tab}two\par'''
          r'''\pard\li1440\fi-720\ls1\ilvl1{\listtext 1.\tab}deep\par'''
          r'''\pard\f1 code \{x\}\par'''
          r'''\pard\f0\trowd\cellx1000\cellx2000\pard\intbl a\cell b\cell\row\trowd\cellx1000\cellx2000\pard\intbl 1\cell 2\cell\row'''
          r'''\pard after\par}''';
      expect(
          RtfReader.markdown(rtf),
          '# Заголовок\n\nПривет, *мир* [link](https://example.com/)\n\n- one\n- two\n  1. deep\n\n```\ncode {x}\n```\n\n'
          '| a | b |\n| --- | --- |\n| 1 | 2 |\n\nafter\n');
    });

    test('plain text shows as written', () {
      final markdown = MarkdownBuilder.fromPlainText('\n# not a heading\n  indented *x*\n1. not a list\n\n\nnext\n');
      expect(markdown, '\\# not a heading\\\n  indented \\*x\\*\\\n1\\. not a list\n\nnext');
      final html = MarkdownRenderer.render(markdown).html;
      expect(html, isNot(contains('<h1>')));
      expect(html, isNot(contains('<ol>')));
      expect(html, contains('# not a heading<br />'));
    });

    test('a file that is not a package or not RTF is refused', () {
      expect(() => DocxReader.markdown(Uint8List.fromList(utf8.encode('hello'))), throwsFormatException);
      expect(() => RtfReader.markdown('hello'), throwsFormatException);
    });
  });

  group('history', () {
    // Absolute paths in the host's own form: history stores them normalised, with a drive letter on Windows.
    String doc(String name) => Platform.isWindows ? r'C:\docs\' '$name.md' : '/tmp/$name.md';

    test('persistence, ordering, migration and clear', () {
      final store = _MapStore();
      final history = RecentDocumentHistory(store)..migrateIfNeeded([doc('first'), doc('second'), doc('first')]);
      expect(history.paths, [doc('first'), doc('second')]);
      history.record(doc('second'));
      expect(RecentDocumentHistory(store).paths, [doc('second'), doc('first')]);
      history
        ..clear()
        ..migrateIfNeeded([doc('first')]);
      expect(history.paths, isEmpty);
    });

    test('limit', () {
      final history = RecentDocumentHistory(_MapStore());
      for (var index = 0; index < 25; index++) {
        history.record(doc('$index'));
      }
      expect(history.paths, hasLength(20));
      expect(history.paths.first, doc('24'));
      expect(history.paths.last, doc('5'));
    });
  });
}

final class _MapStore implements PreferenceStore {
  final _values = <String, Object?>{};
  @override
  Object? read(String key) => _values[key];
  @override
  void write(String key, Object? value) => _values[key] = value;
}
