import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// Minimize, maximize and close of a Windows window, drawn the way Windows 11 draws them (46 pt wide, Segoe Fluent
/// glyphs, red close on hover). The host is told where the maximize button is, so it can offer snap layouts.
/// Nothing on macOS: the system buttons sit in the top bar there.
final class CaptionButtons extends StatelessWidget {
  const CaptionButtons({super.key, this.resizable = true});
  final bool resizable;

  static const width = 46.0;
  static double reservedWidth({bool resizable = true}) => NativeBridge.instance.isMac ? 0 : width * (resizable ? 3 : 2);

  @override
  Widget build(BuildContext context) {
    final bridge = NativeBridge.instance;
    if (bridge.isMac) return const SizedBox.shrink();
    return _Reporter(
      resizable: resizable,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionButton(glyph: 0xE921, label: 'свернуть', onTap: bridge.minimize),
          if (resizable)
            ValueListenableBuilder(
              valueListenable: bridge.maximized,
              builder: (context, maximized, _) => ValueListenableBuilder(
                valueListenable: bridge.maximizeHover,
                builder: (context, hover, _) => _CaptionButton(
                  glyph: maximized ? 0xE923 : 0xE922,
                  label: maximized ? 'восстановить' : 'развернуть',
                  forcedHover: hover,
                  onTap: bridge.toggleMaximize,
                ),
              ),
            ),
          _CaptionButton(glyph: 0xE8BB, label: 'закрыть', close: true, onTap: bridge.performClose),
        ],
      ),
    );
  }
}

final class _CaptionButton extends StatelessWidget {
  const _CaptionButton({required this.glyph, required this.label, required this.onTap, this.close = false, this.forcedHover = false});
  final int glyph;
  final String label;
  final VoidCallback onTap;
  final bool close;
  final bool forcedHover;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hover, pressed) {
        final active = hover || forcedHover;
        final fill = close
            ? (pressed ? const Color(0xFFC42B1C).withValues(alpha: 0.9) : active ? const Color(0xFFC42B1C) : const Color(0x00000000))
            : (pressed ? palette.pressed : active ? palette.hover : const Color(0x00000000));
        final ink = close && (active || pressed) ? const Color(0xFFFFFFFF) : palette.ink;
        return HoverColor(
          color: fill,
          builder: (context, color) => Container(
            width: CaptionButtons.width,
            height: Chrome.bar,
            color: color,
            alignment: Alignment.center,
            child: Text(
              String.fromCharCode(glyph),
              style: TextStyle(fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: const ['Segoe MDL2 Assets'], fontSize: 10, color: ink),
            ),
          ),
        );
      },
    );
  }
}

/// Reports the maximize button's rectangle in window coordinates after each layout.
final class _Reporter extends SingleChildRenderObjectWidget {
  const _Reporter({required this.resizable, required super.child});
  final bool resizable;

  @override
  RenderObject createRenderObject(BuildContext context) => _ReporterBox(resizable);

  @override
  void updateRenderObject(BuildContext context, _ReporterBox renderObject) => renderObject.resizable = resizable;
}

final class _ReporterBox extends RenderProxyBox {
  _ReporterBox(this.resizable);
  bool resizable;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final origin = localToGlobal(Offset.zero);
    final rect = origin & size;
    if (rect == _last) return;
    _last = rect;
    final maximize = resizable ? Rect.fromLTWH(rect.left + CaptionButtons.width, rect.top, CaptionButtons.width, rect.height) : Rect.zero;
    NativeBridge.instance.setCaptionButtons({
      'maximize': [maximize.left, maximize.top, maximize.width, maximize.height],
      'all': [rect.left, rect.top, rect.width, rect.height],
    });
  }
}
