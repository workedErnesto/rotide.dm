import 'package:flutter/widgets.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// A snippet inserted by the `/` menu: the text and where the caret goes in it.
final class EditorCommand {
  const EditorCommand(this.name, this.text, this.cursor);
  final String name;
  final String text;
  final int cursor;
}

const editorCommands = [
  EditorCommand('заголовок', '# ', 2),
  EditorCommand('подзаголовок', '## ', 3),
  EditorCommand('список', '- ', 2),
  EditorCommand('нумерация', '1. ', 3),
  EditorCommand('задача', '- [ ] ', 6),
  EditorCommand('цитата', '> ', 2),
  EditorCommand('код', '```\n\n```', 4),
  EditorCommand('линия', '---\n', 4),
  EditorCommand('ссылка', '[текст](адрес)', 1),
  EditorCommand('жирный', '****', 2),
  EditorCommand('курсив', '**', 1),
  EditorCommand('таблица', '| столбец | столбец |\n| --- | --- |\n|  |  |', 2),
];

/// State of the `/` menu: where the slash is, the query typed after it and the highlighted command.
final class CommandMenuController extends ChangeNotifier {
  int? start;
  String query = '';
  int index = 0;
  TextEditingValue? _last;
  static final _word = RegExp(r'^[\p{L}\p{N}]*$', unicode: true);

  bool get open => start != null;

  List<EditorCommand> get filtered =>
      [for (final command in editorCommands) if (query.isEmpty || command.name.toLowerCase().contains(query.toLowerCase())) command];

  EditorCommand? get chosen {
    final list = filtered;
    return index >= 0 && index < list.length ? list[index] : null;
  }

  /// Opens the menu when a slash is typed at the start of a line; follows the query while it is letters and digits.
  void update(TextEditingValue value) {
    final previous = _last;
    _last = value;
    final selection = value.selection;
    if (start != null) {
      final slash = start!;
      if (!selection.isValid || !selection.isCollapsed || selection.baseOffset <= slash || selection.baseOffset > value.text.length ||
          slash >= value.text.length || value.text[slash] != '/') {
        return close();
      }
      final typed = value.text.substring(slash + 1, selection.baseOffset);
      if (!_word.hasMatch(typed)) return close();
      if (typed != query) {
        query = typed;
        index = 0;
        notifyListeners();
      }
      return;
    }
    if (previous == null || !selection.isValid || !selection.isCollapsed) return;
    final caret = selection.baseOffset;
    final typedSlash = value.text.length == previous.text.length + 1 && caret > 0 && value.text[caret - 1] == '/';
    if (!typedSlash) return;
    final lineStart = caret - 1 == 0 ? 0 : value.text.lastIndexOf('\n', caret - 2) + 1;
    if (lineStart != caret - 1) return;
    start = caret - 1;
    query = '';
    index = 0;
    notifyListeners();
  }

  void move(int delta) {
    final count = filtered.length;
    if (count == 0) return;
    index = (index + delta).clamp(0, count - 1);
    notifyListeners();
  }

  void close() {
    if (start == null) return;
    start = null;
    query = '';
    index = 0;
    notifyListeners();
  }
}

/// Shows the `/` menu next to the slash, below the line or above it when there is no room, with the options only.
final class CommandMenuAnchor extends StatefulWidget {
  const CommandMenuAnchor({super.key, required this.controller, required this.editable, required this.onChoose, required this.child});
  final CommandMenuController controller;
  final GlobalKey<EditableTextState> editable;
  final ValueChanged<EditorCommand> onChoose;
  final Widget child;

  @override
  State<CommandMenuAnchor> createState() => _CommandMenuAnchorState();
}

class _CommandMenuAnchorState extends State<CommandMenuAnchor> {
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final visible = widget.controller.open && widget.controller.filtered.isNotEmpty;
    if (visible && !_portal.isShowing) _portal.show();
    if (!visible && _portal.isShowing) _portal.hide();
    if (mounted) setState(() {});
  }

  Rect? _caret() {
    final start = widget.controller.start;
    final editable = widget.editable.currentState;
    if (start == null || editable == null) return null;
    final box = editable.renderEditable;
    final local = box.getLocalRectForCaret(TextPosition(offset: start));
    return MatrixUtils.transformRect(box.getTransformTo(null), local);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final caret = _caret();
          if (caret == null) return const SizedBox.shrink();
          final screen = MediaQuery.sizeOf(context);
          final bounds = Rect.fromLTWH(8, 8, screen.width - 16, screen.height - 16);
          final commands = widget.controller.filtered;
          final desired = 2 * Radii.panelPadding + 30.0 * (commands.isEmpty ? 1 : commands.length);
          final below = (bounds.bottom - caret.bottom - 6).clamp(0.0, double.infinity);
          final above = (caret.top - bounds.top - 6).clamp(0.0, double.infinity);
          final opensBelow = below >= (desired < above ? desired : above);
          final height = (desired < (opensBelow ? below : above) ? desired : (opensBelow ? below : above));
          if (height < 2 * Radii.panelPadding + 30) return const SizedBox.shrink();
          const width = 220.0;
          final x = caret.left.clamp(bounds.left, bounds.right - width);
          final y = opensBelow ? caret.bottom + 6 : caret.top - 6 - height;
          return Positioned(
            left: x,
            top: y,
            width: width,
            height: height,
            child: _CommandList(controller: widget.controller, onChoose: widget.onChoose),
          );
        },
        child: widget.child,
      );
}

final class _CommandList extends StatefulWidget {
  const _CommandList({required this.controller, required this.onChoose});
  final CommandMenuController controller;
  final ValueChanged<EditorCommand> onChoose;

  @override
  State<_CommandList> createState() => _CommandListState();
}

class _CommandListState extends State<_CommandList> {
  final _scroll = ScrollController();
  int? _hovered;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final controller = widget.controller;
    final commands = controller.filtered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final top = controller.index * 30.0;
      final position = _scroll.position;
      if (top < position.pixels) _scroll.jumpTo(top);
      if (top + 30 > position.pixels + position.viewportDimension) _scroll.jumpTo(top + 30 - position.viewportDimension);
    });
    return RaisedSurface(
      child: Padding(
        padding: const EdgeInsets.all(Radii.panelPadding),
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemExtent: 30,
          itemCount: commands.length,
          itemBuilder: (context, index) => MouseRegion(
            onEnter: (_) => setState(() => _hovered = index),
            onExit: (_) => setState(() => _hovered = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onChoose(commands[index]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: continuousDecoration(radius: Radii.row, color: (_hovered ?? controller.index) == index ? palette.hover : null),
                child: LabelText(commands[index].name, style: RotideFonts.system(13, color: palette.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The editor's right-click menu in the shell style: cut, copy, paste, select all.
final class EditorContextMenu extends StatelessWidget {
  const EditorContextMenu({super.key, required this.state});
  final EditableTextState state;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final anchor = state.contextMenuAnchors.primaryAnchor;
    final screen = MediaQuery.sizeOf(context);
    final items = <(String, VoidCallback?)>[
      ('вырезать', state.cutEnabled ? () => state.cutSelection(SelectionChangedCause.toolbar) : null),
      ('скопировать', state.copyEnabled ? () => state.copySelection(SelectionChangedCause.toolbar) : null),
      ('вставить', state.pasteEnabled ? () => state.pasteText(SelectionChangedCause.toolbar) : null),
      ('выбрать все', state.selectAllEnabled ? () => state.selectAll(SelectionChangedCause.toolbar) : null),
    ];
    const width = 200.0;
    final height = 2 * Radii.panelPadding + 30.0 * items.length;
    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => state.hideToolbar())),
        Positioned(
          left: anchor.dx.clamp(8, screen.width - width - 8),
          top: anchor.dy + height > screen.height - 8 ? anchor.dy - height : anchor.dy,
          width: width,
          child: RaisedSurface(
            child: Padding(
              padding: const EdgeInsets.all(Radii.panelPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (title, run) in items)
                    Interactive(
                      onTap: run == null
                          ? null
                          : () {
                              run();
                              state.hideToolbar();
                            },
                      enabled: run != null,
                      semanticLabel: title,
                      builder: (context, hover, pressed) => Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        decoration: continuousDecoration(radius: Radii.row, color: hover ? palette.hover : null),
                        child: LabelText(title, style: RotideFonts.system(13, color: run == null ? palette.text3 : palette.ink)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
