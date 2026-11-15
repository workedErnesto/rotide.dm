import 'dart:convert';
import 'dart:io';

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
