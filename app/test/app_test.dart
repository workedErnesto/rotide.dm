import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_dm/document/document_controller.dart';
import 'package:rotide_dm/editor/command_menu.dart';
import 'package:rotide_dm/editor/markdown_editor.dart';
import 'package:rotide_dm/editor/markdown_styler.dart';
import 'package:rotide_dm/shell/text_utils.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

void main() {
  group('decoding', () {
    test('UTF-8 with and without a byte order mark', () {
      expect(DocumentController.decode([0xEF, 0xBB, 0xBF, ...utf8.encode('# Привет')]), '# Привет');
      expect(DocumentController.decode(utf8.encode('текст')), 'текст');
    });

    test('UTF-16 with a mark', () {
      final little = [0xFF, 0xFE, 0x3F, 0x04, 0x40, 0x04]; // "пр"
      expect(DocumentController.decode(little), 'пр');
    });

    test('Windows-1251 for old Russian files, Latin-1 otherwise', () {
      expect(DocumentController.decode([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x2C, 0x20, 0xB8, 0xE6]), 'Привет, ёж');
      expect(DocumentController.decode([0x63, 0x61, 0x66, 0xE9]), 'café');
    });
  });

  group('formats', () {
    test('by extension', () {
      expect(DocumentFormat.of(null), DocumentFormat.markdown);
      expect(DocumentFormat.of('/a/README.MD'), DocumentFormat.markdown);
      expect(DocumentFormat.of('/a/notes.txt'), DocumentFormat.plainText);
      expect(DocumentFormat.of('/a/server.log'), DocumentFormat.plainText);
      expect(DocumentFormat.of(r'C:\docs\Отчёт.DOCX'), DocumentFormat.word);
      expect(DocumentFormat.of('/a/letter.rtf'), DocumentFormat.rtf);
      expect(DocumentFormat.word.converted, isTrue);
      expect(DocumentFormat.plainText.converted, isFalse);
    });

    test('Word and RTF open as Markdown, text as it is', () {
      final docx = DocxWriter.document(markdown: '# Отчёт\n\n**итог**', title: 'T');
      expect(DocumentController.read(docx, DocumentFormat.word), '# Отчёт\n\n**итог**\n');
      final rtf = latin1.encode(RtfWriter.document(markdown: '# Отчёт\n\n*итог*', title: 'T'));
      expect(DocumentController.read(rtf, DocumentFormat.rtf), '# Отчёт\n\n*итог*\n');
      expect(DocumentController.read(utf8.encode('# not a heading'), DocumentFormat.plainText), '# not a heading');
    });
  });

  group('editor styling', () {
    final palette = RotidePalette(dark: false, contrast: false);
    StyledText style(String text) => MarkdownStyler.style(text, palette: palette, size: 15, lineHeight: 1.9);

    test('hides supported markers and marks closing ones', () {
      final styled = style('a **bold** b');
      expect(styled.concealed, containsAll([2, 3, 8, 9]));
      expect(styled.closing, containsAll([8, 9]));
      expect(styled.closing, isNot(contains(2)));
    });

    test('heading marker is hidden, text inside code fences is not styled', () {
      expect(style('# Title').concealed, containsAll([0, 1]));
      expect(style('```\n**not bold**\n```').concealed, isEmpty);
    });

    test('plain text shows every character', () {
      final styled = MarkdownStyler.style('# not **bold** [x](y)', palette: palette, size: 15, lineHeight: 1.9, plain: true);
      expect(styled.concealed, isEmpty);
      expect(styled.span.children, hasLength(1));
    });

    test('image syntax stays visible', () {
      expect(style('![alt](a.png)').concealed, isEmpty);
      expect(style('[text](https://a.b)').concealed, contains(0));
    });
  });

  group('hidden markers while typing', () {
    final palette = RotidePalette(dark: false, contrast: false);

    MarkdownEditingController controller(String text) {
      final value = MarkdownEditingController(text: text)..palette = palette;
      value.styled();
      return value;
    }

    test('typing right after a hidden closing marker goes inside the styled text', () {
      final editing = controller('**bold**');
      final formatter = ConcealedMarkers(editing);
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: '**bold**', selection: TextSelection.collapsed(offset: 8)),
        const TextEditingValue(text: '**bold**x', selection: TextSelection.collapsed(offset: 9)),
      );
      expect(result.text, '**boldx**');
      expect(result.selection.baseOffset, 7);
    });

    test('Backspace at a hidden heading marker removes the whole marker', () {
      final editing = controller('# Title');
      final formatter = ConcealedMarkers(editing);
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: '# Title', selection: TextSelection.collapsed(offset: 2)),
        const TextEditingValue(text: '#Title', selection: TextSelection.collapsed(offset: 1)),
      );
      expect(result.text, 'Title');
      expect(result.selection.baseOffset, 0);
    });

    test('Backspace after a hidden closing marker deletes the visible character before it', () {
      final editing = controller('**bold**');
      final formatter = ConcealedMarkers(editing);
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: '**bold**', selection: TextSelection.collapsed(offset: 8)),
        const TextEditingValue(text: '**bold*', selection: TextSelection.collapsed(offset: 7)),
      );
      expect(result.text, '**bol**');
    });
  });

  group('slash commands', () {
    test('open at the start of a line, filter by the query, close on a space', () {
      final menu = CommandMenuController();
      menu.update(const TextEditingValue(text: 'a\n', selection: TextSelection.collapsed(offset: 2)));
      menu.update(const TextEditingValue(text: 'a\n/', selection: TextSelection.collapsed(offset: 3)));
      expect(menu.open, isTrue);
      expect(menu.filtered, hasLength(editorCommands.length));
      menu.update(const TextEditingValue(text: 'a\n/заг', selection: TextSelection.collapsed(offset: 6)));
      expect(menu.filtered.map((c) => c.name), ['заголовок', 'подзаголовок']);
      menu.update(const TextEditingValue(text: 'a\n/заг ', selection: TextSelection.collapsed(offset: 7)));
      expect(menu.open, isFalse);
    });

    test('the pointer picks the command Return inserts', () {
      final menu = CommandMenuController();
      menu.update(const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)));
      menu.update(const TextEditingValue(text: '/', selection: TextSelection.collapsed(offset: 1)));
      menu.select(3);
      expect(menu.chosen?.name, 'нумерация');
      menu.select(editorCommands.length);
      expect(menu.index, 3);
    });

    test('a slash inside a line does not open the menu', () {
      final menu = CommandMenuController();
      menu.update(const TextEditingValue(text: 'a', selection: TextSelection.collapsed(offset: 1)));
      menu.update(const TextEditingValue(text: 'a/', selection: TextSelection.collapsed(offset: 2)));
      expect(menu.open, isFalse);
    });
  });

  group('menu highlight', () {
    Widget menu(double? top, {bool reduced = false}) => Directionality(
          textDirection: TextDirection.ltr,
          child: RotideTheme(
            dark: false,
            accessibility: RotideAccessibility(reduceMotion: reduced),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 200, child: MenuHighlight(top: top, height: 30, child: const SizedBox(height: 120))),
            ),
          ),
        );
    Positioned plate(WidgetTester tester) =>
        tester.widget<Positioned>(find.descendant(of: find.byType(MenuHighlight), matching: find.byType(Positioned)));
    double alpha(WidgetTester tester) =>
        (tester.widget<DecoratedBox>(find.descendant(of: find.byType(MenuHighlight), matching: find.byType(DecoratedBox))).decoration
                as ShapeDecoration)
            .color!
            .a;

    testWidgets('slides between rows on a spring and fades out when the pointer leaves', (tester) async {
      await tester.pumpWidget(menu(0));
      await tester.pumpWidget(menu(60));
      await tester.pump(const Duration(milliseconds: 40));
      expect(plate(tester).top, inExclusiveRange(0, 60));
      await tester.pumpAndSettle();
      expect(plate(tester).top, 60);
      await tester.pumpWidget(menu(null));
      await tester.pumpAndSettle();
      expect(alpha(tester), 0);
      // A faded-out plate appears at the new row instead of sliding from the old one.
      await tester.pumpWidget(menu(0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(plate(tester).top, 0);
      await tester.pumpAndSettle();
      expect(alpha(tester), greaterThan(0));
    });

    testWidgets('moves at once with Reduce Motion', (tester) async {
      await tester.pumpWidget(menu(0, reduced: true));
      await tester.pumpWidget(menu(90, reduced: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(plate(tester).top, 90);
    });
  });

  group('text', () {
    test('Russian plural and grouping', () {
      expect(Russian.plural(1, 'слово', 'слова', 'слов'), 'слово');
      expect(Russian.plural(3, 'слово', 'слова', 'слов'), 'слова');
      expect(Russian.plural(12, 'слово', 'слова', 'слов'), 'слов');
      expect(Russian.plural(21, 'слово', 'слова', 'слов'), 'слово');
      expect(Russian.grouped(12345), '12 345');
    });
  });

  group('motion', () {
    test('SwiftUI spring parameters convert to the same physics', () {
      final description = MotionTokens.snappy.description;
      expect(description.mass, 1);
      expect(description.stiffness, closeTo(438.6, 0.1));
      expect(description.damping, closeTo(36.0, 0.1));
      expect(MotionTokens.snappy.value(2), closeTo(1, 0.001));
    });
  });
}
