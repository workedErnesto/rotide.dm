import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/geometry.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';
import 'interactive.dart';
import 'label_text.dart';
import 'surfaces.dart';
import 'symbol.dart';

/// Segmented control from mica: a tonal track with a raised thumb that slides to the chosen segment on the snappy
/// spring. Segments share the width equally and grow past [width] rather than cut a word.
final class Segmented<T> extends StatefulWidget {
  const Segmented({
    super.key,
    required this.selection,
    required this.options,
    required this.onChanged,
    this.symbols = const [],
    this.compact = false,
    this.width = 0,
    this.fillsWidth = false,
    this.label = '',
    this.enabled = true,
    this.literal = false,
  });

  final T selection;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final List<String> symbols;
  final bool compact;
  final double width;
  final bool fillsWidth;
  final String label;
  final bool enabled;

  /// The options keep the case they are written in: each names a style of text in that style.
  final bool literal;

  @override
  State<Segmented<T>> createState() => _SegmentedState<T>();
}

class _SegmentedState<T> extends State<Segmented<T>> {
  T? _hovered;
  static const _gap = 2.0;

  double get _fontSize => widget.compact ? 11.5 : 12.5;
  double get _symbolSize => widget.compact ? 10 : 11;
  double get _padding => widget.compact ? 8 : 10;

  double _intrinsic(int index, String title) {
    // Measured with the chosen weight so the widest state fits.
    final painter = TextPainter(
      text: TextSpan(text: title, style: RotideFonts.system(_fontSize, weight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final symbol = index < widget.symbols.length ? _symbolSize * 1.25 + 6 : 0;
    return painter.width + symbol + 2 * _padding;
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final count = widget.options.length;
    final height = widget.compact ? 22.0 : 26.0;
    var widest = 0.0;
    for (var i = 0; i < count; i++) {
      widest = math.max(widest, _intrinsic(i, RotideTheme.textOf(context, widget.options[i].$2)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final intrinsic = widest * count + _gap * (count - 1);
      final proposed = widget.fillsWidth && constraints.maxWidth.isFinite ? constraints.maxWidth - 4 : 0.0;
      final inner = math.max(math.max(widget.width - 4, intrinsic), proposed);
      final each = ((inner - _gap * (count - 1)) / count).ceilToDouble();
      final selected = widget.options.indexWhere((option) => option.$1 == widget.selection);
      // A new language or letter case changes the width of the longest word: the track follows it on the spring.
      return SpringValue(
        value: each,
        spring: MotionTokens.snappy,
        builder: (context, each, _) => _track(context, palette, each, count, height, selected),
      );
    });
  }

  Widget _track(BuildContext context, RotidePalette palette, double each, int count, double height, int selected) {
      return Semantics(
        container: true,
        label: RotideTheme.textOf(context, widget.label),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.45,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: continuousDecoration(radius: Radii.track, color: palette.track),
            child: SizedBox(
              width: each * count + _gap * (count - 1),
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (selected >= 0)
                    SpringValue(
                      value: selected.toDouble(),
                      spring: MotionTokens.snappy,
                      builder: (context, position, _) => Positioned(
                        left: position * (each + _gap),
                        top: 0,
                        width: each,
                        height: height,
                        child: DecoratedBox(
                          decoration: continuousDecoration(radius: Radii.thumb, color: palette.thumb, shadows: [swiftShadow(palette.shadow, 2, y: 1)]),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        SizedBox(width: each, height: height, child: _segment(context, i, i == selected)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _segment(BuildContext context, int index, bool chosen) {
    final palette = RotideTheme.paletteOf(context);
    final (value, title) = widget.options[index];
    final hovered = _hovered == value;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = value),
      onExit: (_) {
        if (_hovered == value) setState(() => _hovered = null);
      },
      child: Interactive(
        onTap: widget.enabled ? () => widget.onChanged(value) : null,
        selected: chosen,
        semanticLabel: title,
        builder: (context, hover, pressed) => PressScale(
          pressed: pressed,
          scale: 0.96,
          child: HoverColor(
            color: !chosen && hovered ? palette.hover : const Color(0x00000000),
            builder: (context, fill) => DecoratedBox(
              decoration: continuousDecoration(radius: Radii.thumb, color: fill),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _padding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (index < widget.symbols.length) ...[
                      Symbol(widget.symbols[index], size: _symbolSize, color: chosen || hovered ? palette.ink : palette.text2),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: LabelText(
                        title,
                        literal: widget.literal,
                        opticalCenter: true,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: RotideFonts.system(_fontSize,
                            weight: chosen ? FontWeight.w500 : FontWeight.w400, color: chosen || hovered ? palette.ink : palette.text2),
                      ),
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
