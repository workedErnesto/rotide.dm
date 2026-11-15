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
  static const _header = 24.0, _rowHeight = 30.0, _separator = 2 * Space.micro + 1;
  final _focus = FocusNode(debugLabel: 'export menu');
  double? _highlight;

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

  /// Follows the pointer over the rows; leaving a row clears the highlight unless another row already took it.
  ValueChanged<bool> _hover(double top) => (inside) {
        if (inside) {
          setState(() => _highlight = top);
        } else if (_highlight == top) {
          setState(() => _highlight = null);
        }
      };

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
        label: RotideTheme.textOf(context, 'экспорт'),
        child: SizedBox(
          width: 300,
          child: RaisedSurface(
            child: Padding(
              padding: const EdgeInsets.all(Radii.panelPadding),
              child: MenuHighlight(
                top: _highlight,
                height: _rowHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: _header,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      child: LabelText('экспорт', style: RotideFonts.system(11, weight: FontWeight.w500, color: palette.text3)),
                    ),
                    for (final format in ExportFormat.values)
                      MenuRow(
                        symbol: format.symbol,
                        title: format.title,
                        hint: '.${format.extension}',
                        onHover: _hover(_header + _rowHeight * format.index),
                        onTap: () => controller.export(format),
                      ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: Space.micro, horizontal: 10), child: Hairline()),
                    MenuRow(
                      symbol: 'square.and.arrow.down',
                      title: 'сохранить как Markdown…',
                      hint: shortcutHint('⇧⌘S'),
                      onHover: _hover(_header + _rowHeight * ExportFormat.values.length + _separator),
                      onTap: () {
                        _close();
                        controller.saveAs();
                      },
                    ),
                    MenuRow(
                      symbol: 'printer',
                      title: 'напечатать…',
                      hint: shortcutHint('⌘P'),
                      onHover: _hover(_header + _rowHeight * (ExportFormat.values.length + 1) + _separator),
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
      ),
    );
  }
}

/// A row of a shell menu: symbol, title and a quiet hint at the end. The menu draws the hover plate behind its rows
/// ([MenuHighlight]); the row reports the pointer through [onHover] and brightens its symbol.
final class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.symbol, required this.title, required this.hint, required this.onHover, required this.onTap});
  final String symbol;
  final String title;
  final String hint;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Interactive(
        onTap: onTap,
        semanticLabel: title,
        builder: (context, hover, pressed) => PressScale(
          pressed: pressed,
          scale: 0.98,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
