import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// Search in the source text: matches of the query, case-insensitive, and the current one.
final class FindController extends ChangeNotifier {
  final query = TextEditingController();
  final replacement = TextEditingController();
  final queryFocus = FocusNode(debugLabel: 'find');
  final replacementFocus = FocusNode(debugLabel: 'replace');
  bool visible = false;
  bool replacing = false;
  List<(int, int)> matches = const [];
  int? current;

  /// Set when the current match should become the editor selection.
  bool selectCurrent = false;
  String _text = '';

  (int, int)? get currentRange => current == null || current! >= matches.length ? null : matches[current!];

  void show({required bool replace, String? query}) {
    visible = true;
    replacing = replace;
    if (query != null) this.query.text = query;
    selectCurrent = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      queryFocus.requestFocus();
      this.query.selection = TextSelection(baseOffset: 0, extentOffset: this.query.text.length);
    });
  }

  void hide() {
    visible = false;
    matches = const [];
    current = null;
    notifyListeners();
  }

  void search(String text, {bool keepIndex = false}) {
    _text = text;
    final needle = query.text.toLowerCase();
    final found = <(int, int)>[];
    if (needle.isNotEmpty) {
      final haystack = text.toLowerCase();
      var from = 0;
      while (true) {
        final at = haystack.indexOf(needle, from);
        if (at < 0) break;
        found.add((at, at + needle.length));
        from = at + needle.length;
      }
    }
    matches = found;
    if (found.isEmpty) {
      current = null;
    } else if (!keepIndex || current == null || current! >= found.length) {
      current = 0;
    }
    notifyListeners();
  }

  void next({int? fromCaret}) {
    if (matches.isEmpty) return search(_text);
    if (fromCaret != null) {
      final index = matches.indexWhere((match) => match.$1 >= fromCaret);
      current = index < 0 ? 0 : index;
    } else {
      current = ((current ?? -1) + 1) % matches.length;
    }
    selectCurrent = true;
    notifyListeners();
  }

  void previous() {
    if (matches.isEmpty) return;
    current = ((current ?? 0) - 1 + matches.length) % matches.length;
    selectCurrent = true;
    notifyListeners();
  }

  @override
  void dispose() {
    query.dispose();
    replacement.dispose();
    queryFocus.dispose();
    replacementFocus.dispose();
    super.dispose();
  }
}

/// The find bar over the source, in the shell's style: query field, match count, previous and next, replace.
final class FindBar extends StatelessWidget {
  const FindBar({super.key, required this.controller, required this.onReplace, required this.onClose});
  final FindController controller;
  final void Function(String replacement, {required bool all}) onReplace;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Presence(
      visible: controller.visible,
      spring: MotionTokens.snappy,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.hairline))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.normal, vertical: Space.small),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      controller: controller.query,
                      focusNode: controller.queryFocus,
                      hint: 'найти',
                      onChanged: (_) {
                        controller.selectCurrent = true;
                        controller.search(controller._text);
                      },
                      onSubmitted: () => controller.next(),
                    ),
                  ),
                  const SizedBox(width: Space.small),
                  SizedBox(
                    width: 64,
                    child: LabelText(
                      controller.query.text.isEmpty
                          ? ''
                          : controller.matches.isEmpty
                              ? 'нет'
                              : '${(controller.current ?? 0) + 1} из ${controller.matches.length}',
                      textAlign: TextAlign.center,
                      style: RotideFonts.system(11.5, color: palette.text3),
                    ),
                  ),
                  MButton(label: 'назад', compact: true, kind: ButtonKind.ghost, onPressed: controller.matches.isEmpty ? null : controller.previous),
                  const SizedBox(width: Space.micro),
                  MButton(label: 'далее', compact: true, kind: ButtonKind.ghost, onPressed: controller.matches.isEmpty ? null : () => controller.next()),
                  const SizedBox(width: Space.small),
                  MButton(label: 'готово', compact: true, onPressed: onClose),
                ],
              ),
              if (controller.replacing) ...[
                const SizedBox(height: Space.small),
                Row(
                  children: [
                    Expanded(
                      child: _Field(controller: controller.replacement, focusNode: controller.replacementFocus, hint: 'заменить на', onSubmitted: () => onReplace(controller.replacement.text, all: false)),
                    ),
                    const SizedBox(width: Space.small),
                    MButton(
                      label: 'заменить',
                      compact: true,
                      kind: ButtonKind.ghost,
                      onPressed: controller.currentRange == null ? null : () => onReplace(controller.replacement.text, all: false),
                    ),
                    const SizedBox(width: Space.micro),
                    MButton(
                      label: 'все',
                      compact: true,
                      kind: ButtonKind.ghost,
                      onPressed: controller.matches.isEmpty ? null : () => onReplace(controller.replacement.text, all: true),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      builder: (context, progress, child) => ClipRect(
        child: Align(alignment: Alignment.topCenter, heightFactor: progress.clamp(0.0, 1.0), child: Opacity(opacity: progress.clamp(0.0, 1.0), child: child)),
      ),
    );
  }
}

/// A text field of the shell: white fill with a hairline in light mode, a faint fill in dark mode.
final class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, required this.focusNode, this.onChanged, required this.onSubmitted});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final style = RotideFonts.system(13, color: palette.ink);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: continuousDecoration(radius: 7, color: palette.field, border: palette.fieldBorder),
      alignment: Alignment.centerLeft,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty ? LabelText(hint, style: style.copyWith(color: palette.text3)) : const SizedBox.shrink(),
          ),
          EditableText(
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: palette.ink,
            backgroundCursorColor: palette.text3,
            selectionColor: palette.textSelection,
            maxLines: 1,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted(),
            inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
          ),
        ],
      ),
    );
  }
}
