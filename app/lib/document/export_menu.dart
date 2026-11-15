import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../shell/text_utils.dart';
import 'document_controller.dart';

/// Export and save menu under the export button, drawn like mica's shell menus: raised, radius 16 with a 6 pt inset,
/// rows of radius 10, grows from the button on the snappy spring (opacity only with Reduce Motion). Esc and a click
/// outside close it.
final class ExportMenuLayer extends StatelessWidget {
  const ExportMenuLayer({super.key, required this.controller, required this.visible});
  final DocumentController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final reduced = RotideTheme.reduceMotionOf(context);
    return Presence(
      visible: visible,
      spring: MotionTokens.snappy,
      child: _ExportMenu(controller: controller),
      builder: (context, progress, menu) => IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => controller.setExportMenu(false)),
            ),
            Positioned(
              top: Chrome.bar - 2,
              right: Radii.gutter,
              child: Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: Transform.scale(scale: reduced ? 1 : 0.95 + 0.05 * progress, alignment: Alignment.topRight, child: menu),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ExportMenu extends StatefulWidget {
  const _ExportMenu({required this.controller});
  final DocumentController controller;

  @override
  State<_ExportMenu> createState() => _ExportMenuState();
}

class _ExportMenuState extends State<_ExportMenu> {
  final _focus = FocusNode(debugLabel: 'export menu');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _close() => widget.controller.setExportMenu(false);

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final controller = widget.controller;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        label: 'экспорт',
        child: SizedBox(
          width: 300,
          child: RaisedSurface(
            child: Padding(
              padding: const EdgeInsets.all(Radii.panelPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: LabelText('экспорт', style: RotideFonts.system(11, weight: FontWeight.w500, color: palette.text3)),
                  ),
                  for (final format in ExportFormat.values)
                    MenuRow(symbol: format.symbol, title: format.title, hint: '.${format.extension}', onTap: () => controller.export(format)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: Space.micro, horizontal: 10), child: Hairline()),
                  MenuRow(
                    symbol: 'square.and.arrow.down',
                    title: 'сохранить как Markdown…',
                    hint: shortcutHint('⇧⌘S'),
                    onTap: () {
                      _close();
                      controller.saveAs();
                    },
                  ),
                  MenuRow(
                    symbol: 'printer',
                    title: 'напечатать…',
                    hint: shortcutHint('⌘P'),
                    onTap: () {
                      _close();
                      controller.print();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of a shell menu: symbol, title and a quiet hint at the end.
final class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.symbol, required this.title, required this.hint, required this.onTap});
  final String symbol;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: title,
      builder: (context, hover, pressed) => PressScale(
        pressed: pressed,
        scale: 0.98,
        child: HoverColor(
          color: hover ? palette.hover : const Color(0x00000000),
          builder: (context, fill) => Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: continuousDecoration(radius: Radii.row, color: fill),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Center(
                    child: HoverColor(color: hover ? palette.ink : palette.text2, builder: (context, ink) => Symbol(symbol, size: 13, color: ink)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: LabelText(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: RotideFonts.system(13, color: palette.ink))),
                const SizedBox(width: Space.small),
                Text(hint, style: RotideFonts.system(11.5, color: palette.text3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
