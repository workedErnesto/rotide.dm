import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../document/document_controller.dart';
import 'command_menu.dart';
import 'find_bar.dart';
import 'markdown_styler.dart';

/// The source text with its inline styling, built for each frame from the text.
final class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  RotidePalette? palette;
  double size = 15;
  double lineHeight = 1.9;
  List<(int, int)> marks = const [];
  int? currentMark;
  StyledText? _styled;
  String? _styledText;
  Object? _styledKey;

  StyledText styled() {
    final key = (palette, size, lineHeight, marks, currentMark);
    if (_styled == null || _styledText != text || _styledKey != key) {
      _styled = MarkdownStyler.style(text, palette: palette!, size: size, lineHeight: lineHeight, marks: marks, currentMark: currentMark);
      _styledText = text;
      _styledKey = key;
    }
    return _styled!;
  }

  void restyle() {
    _styled = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (palette == null) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final span = styled().span;
    final composing = value.composing;
    if (!withComposing || !composing.isValid || composing.isCollapsed) return span;
    // Underline the marked text of an input method on top of the styling.
    return TextSpan(style: span.style, children: [
      for (final child in span.children!.cast<TextSpan>()) child,
    ]);
  }
}

/// Keeps typing inside styled text and lets deletion step over hidden markers, as the Swift editor did: text typed
/// right after a hidden closing marker goes before it, Backspace at hidden markers deletes the visible character
/// before them (a whole hidden heading marker at the start of a line goes at once).
final class ConcealedMarkers extends TextInputFormatter {
  ConcealedMarkers(this.controller);
  final MarkdownEditingController controller;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;
    if (!oldValue.selection.isValid || !oldValue.selection.isCollapsed) return newValue;
    final styled = controller._styledText == oldValue.text ? controller._styled : null;
    if (styled == null) return newValue;
    final old = oldValue.text;
    final p = oldValue.selection.start;
    final grown = newValue.text.length - old.length;

    // Insertion at the caret, right after a hidden closing marker.
    if (grown > 0 && newValue.selection.isCollapsed && newValue.selection.start == p + grown) {
      final inserted = newValue.text.substring(p, p + grown);
      if (newValue.text == old.substring(0, p) + inserted + old.substring(p) && p > 0 && styled.closing.contains(p - 1)) {
        var q = p;
        while (q > 0 && styled.closing.contains(q - 1)) {
          q--;
        }
        return TextEditingValue(text: old.substring(0, q) + inserted + old.substring(q), selection: TextSelection.collapsed(offset: q + grown));
      }
    }

    if (grown == -1 && newValue.selection.isCollapsed) {
      // Backspace.
      if (p > 0 && newValue.selection.start == p - 1 && newValue.text == old.substring(0, p - 1) + old.substring(p)) {
        var position = p;
        while (position > 0 && styled.concealed.contains(position - 1)) {
          position--;
        }
        if (position != p) {
          final lineStart = position == 0 ? 0 : old.lastIndexOf('\n', position - 1) + 1;
          final marker = old.substring(position, p);
          if (position == lineStart && marker.trim().split('').every((c) => c == '#')) {
            return TextEditingValue(text: old.substring(0, position) + old.substring(p), selection: TextSelection.collapsed(offset: position));
          }
          if (position == 0) return oldValue.copyWith(selection: const TextSelection.collapsed(offset: 0));
          return TextEditingValue(text: old.substring(0, position - 1) + old.substring(position), selection: TextSelection.collapsed(offset: position - 1));
        }
      }
      // Forward delete.
      if (newValue.selection.start == p && p < old.length && newValue.text == old.substring(0, p) + old.substring(p + 1)) {
        var position = p;
        while (position < old.length && styled.concealed.contains(position)) {
          position++;
        }
        if (position != p) {
          if (position >= old.length) return oldValue.copyWith(selection: TextSelection.collapsed(offset: position));
          return TextEditingValue(text: old.substring(0, position) + old.substring(position + 1), selection: TextSelection.collapsed(offset: position));
        }
      }
    }
    return newValue;
  }
}

/// The source editor: one text column at most 760 pt wide, centred in a wide card, inline styling, undo, find, and
/// the `/` command menu at the start of a line.
final class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({super.key, required this.controller, required this.blocked});
  final DocumentController controller;
  final bool blocked;

  @override
  State<MarkdownEditor> createState() => MarkdownEditorState();
}

class MarkdownEditorState extends State<MarkdownEditor> implements TextSelectionGestureDetectorBuilderDelegate {
  final _text = MarkdownEditingController();
  final _focus = FocusNode(debugLabel: 'markdown editor');
  final _scroll = ScrollController();
  final _undo = UndoHistoryController();
  final _editable = GlobalKey<EditableTextState>();
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  late final StreamSubscription<Heading> _reveal;
  final _commands = CommandMenuController();
  final _find = FindController();
  int _revision = -1;

  DocumentController get _document => widget.controller;

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editable;
  @override
  bool get forcePressEnabled => false;
  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _reveal = _document.reveal.listen(_revealLine);
    _find.addListener(_findChanged);
    _sync();
    if (_document.mode == ViewMode.edit) WidgetsBinding.instance.addPostFrameCallback((_) => focus());
  }

  @override
  void didUpdateWidget(MarkdownEditor old) {
    super.didUpdateWidget(old);
    _sync();
    if (widget.blocked && !old.blocked) _commands.close();
  }

  @override
  void dispose() {
    _reveal.cancel();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    _undo.dispose();
    _commands.dispose();
    _find.dispose();
    super.dispose();
  }

  void focus() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  /// Loads the document text after opening or reverting.
  void _sync() {
    if (_revision == _document.revision) return;
    _revision = _document.revision;
    _text.value = TextEditingValue(text: _document.text, selection: const TextSelection.collapsed(offset: 0));
    _undo.value = UndoHistoryValue.empty;
  }

  void _changed() {
    _document.editorChanged(_text.text);
    _commands.update(_text.value);
    if (_find.visible) _find.search(_text.text, keepIndex: true);
  }

  void _findChanged() {
    _text
      ..marks = _find.visible ? _find.matches : const []
      ..currentMark = _find.visible ? _find.current : null
      ..restyle();
    final current = _find.currentRange;
    if (current != null && _find.selectCurrent) {
      _text.selection = TextSelection(baseOffset: current.$1, extentOffset: current.$2);
      _find.selectCurrent = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _editable.currentState?.bringIntoView(TextPosition(offset: current.$1)));
    }
  }

  /// Menu commands of the find submenu.
  void find(String command) {
    switch (command) {
      case 'find':
        _find.show(replace: false);
      case 'replace':
        _find.show(replace: true);
      case 'findNext':
        _find.next();
      case 'findPrevious':
        _find.previous();
      case 'findSelection':
        final selection = _text.selection;
        if (selection.isValid && !selection.isCollapsed) _find.show(replace: false, query: selection.textInside(_text.text));
    }
    if (_find.visible) _find.search(_text.text);
  }

  void _replace(String replacement, {required bool all}) {
    final text = _text.text;
    if (all) {
      final matches = _find.matches;
      if (matches.isEmpty) return;
      final buffer = StringBuffer();
      var last = 0;
      for (final (start, end) in matches) {
        buffer
          ..write(text.substring(last, start))
          ..write(replacement);
        last = end;
      }
      buffer.write(text.substring(last));
      _text.value = TextEditingValue(text: buffer.toString(), selection: TextSelection.collapsed(offset: math.min(last, buffer.length)));
    } else {
      final current = _find.currentRange;
      if (current == null) return;
      final updated = text.replaceRange(current.$1, current.$2, replacement);
      _text.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: current.$1 + replacement.length));
      _find.search(_text.text);
      _find.selectCurrent = true;
      _find.next(fromCaret: current.$1 + replacement.length);
    }
  }

  /// Puts the heading line at the top of the card and the caret at its start.
  void _revealLine(Heading heading) {
    if (_document.mode != ViewMode.edit) return;
    final text = _text.text;
    var offset = 0;
    for (var line = 1; line < heading.line && offset < text.length; line++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) {
        offset = text.length;
        break;
      }
      offset = next + 1;
    }
    _text.selection = TextSelection.collapsed(offset: offset);
    focus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editable = _editable.currentState;
      if (editable == null || !_scroll.hasClients) return;
      final caret = editable.renderEditable.getLocalRectForCaret(TextPosition(offset: offset));
      final target = (caret.top + _EditorLayout.top - 16).clamp(0.0, _scroll.position.maxScrollExtent);
      if (RotideTheme.reduceMotionOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _insertCommand(EditorCommand command) {
    final start = _commands.start;
    final caret = _text.selection.baseOffset;
    _commands.close();
    if (start == null || caret <= start || caret > _text.text.length || _text.text[start] != '/') return;
    final updated = _text.text.replaceRange(start, caret, command.text);
    _text.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: start + command.cursor));
    focus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_commands.open) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _commands.close();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _commands.move(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _commands.move(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
          final chosen = _commands.chosen;
          if (chosen != null) {
            _insertCommand(chosen);
            return KeyEventResult.handled;
          }
          _commands.close();
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _find.visible) {
      _find.hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Natural line height of the system font, so 1.6 means what NSParagraphStyle.lineHeightMultiple means.
  static double _lineHeightFor(double size) {
    final painter = TextPainter(text: TextSpan(text: 'Ag', style: RotideFonts.system(size)), textDirection: TextDirection.ltr)..layout();
    return painter.preferredLineHeight / size * 1.6;
  }

  static double? _cachedRatio;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final size = 15 * _document.zoom;
    _cachedRatio ??= _lineHeightFor(15);
    _text
      ..palette = palette
      ..size = size
      ..lineHeight = _cachedRatio!;
    final baseStyle = RotideFonts.system(size, color: palette.ink, height: _cachedRatio);
    return Focus(
      onKeyEvent: _key,
      child: Column(
        children: [
          ListenableBuilder(
            listenable: _find,
            builder: (context, _) => FindBar(
              controller: _find,
              onReplace: _replace,
              onClose: () {
                _find.hide();
                focus();
              },
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              // NSTextView keeps a 5 pt line fragment padding inside the container inset.
              final side = math.max(28.0, (constraints.maxWidth - Chrome.editorColumn) / 2) + 5;
              return CommandMenuAnchor(
                controller: _commands,
                editable: _editable,
                onChoose: _insertCommand,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    // A click below the text puts the caret at the end, as in NSTextView.
                    final editable = _editable.currentState;
                    if (editable == null) return;
                    final box = editable.renderEditable;
                    final local = box.globalToLocal(details.globalPosition);
                    if (local.dy > box.size.height) {
                      _text.selection = TextSelection.collapsed(offset: _text.text.length);
                      focus();
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(side, _EditorLayout.top, side, _EditorLayout.top),
                    child: _gestures.buildGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      child: EditableText(
                        key: _editable,
                        controller: _text,
                        focusNode: _focus,
                        undoController: _undo,
                        style: baseStyle,
                        strutStyle: StrutStyle.disabled,
                        cursorColor: palette.ink,
                        backgroundCursorColor: palette.text3,
                        selectionColor: palette.textSelection,
                        cursorWidth: 1.5,
                        cursorOpacityAnimates: false,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        inputFormatters: [ConcealedMarkers(_text)],
                        rendererIgnoresPointer: true,
                        enableInteractiveSelection: true,
                        selectionControls: emptyTextSelectionControls,
                        contextMenuBuilder: (context, state) => EditorContextMenu(state: state),
                        scrollPhysics: const NeverScrollableScrollPhysics(),
                        readOnly: widget.blocked,
                        showCursor: !widget.blocked,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

abstract final class _EditorLayout {
  static const top = 24.0;
}
