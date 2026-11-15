import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/geometry.dart';
import '../tokens/motion.dart';
import 'interactive.dart';
import 'surfaces.dart';

/// Switch from mica: a capsule whose knob slides on the snappy spring and stretches while pressed.
final class MSwitch extends StatelessWidget {
  const MSwitch({super.key, required this.value, required this.onChanged, this.enabled = true, this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final motion = motionAllowed(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        toggled: value,
        label: label == null ? null : RotideTheme.textOf(context, label!),
        child: Interactive(
          onTap: enabled ? () => onChanged(!value) : null,
          button: false,
          builder: (context, hover, pressed) => SpringValue(
            value: value ? 1 : 0,
            spring: MotionTokens.snappy,
            builder: (context, position, _) => SpringValue(
              value: pressed && motion ? 21 : 16,
              spring: MotionTokens.press,
              builder: (context, knobWidth, _) => HoverColor(
                color: value ? palette.primary : palette.switchOff,
                builder: (context, trackColor) => SizedBox(
                  width: 36,
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned.fill(child: DecoratedBox(decoration: ShapeDecoration(shape: const StadiumBorder(), color: trackColor))),
                      Positioned.fill(
                        child: HoverColor(
                          color: const Color(0xFFFFFFFF).withValues(alpha: hover && !value ? 0.06 : 0),
                          builder: (context, overlay) => DecoratedBox(decoration: ShapeDecoration(shape: const StadiumBorder(), color: overlay)),
                        ),
                      ),
                      Positioned(
                        left: 2 + position * (32 - knobWidth),
                        top: 2,
                        width: knobWidth,
                        height: 16,
                        child: HoverColor(
                          color: value ? palette.onPrimary : palette.knobOff,
                          builder: (context, knob) => DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: knob,
                              shadows: [swiftShadow(palette.shadowStrong, 1.5, y: 1)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled row with a switch at the end (MToggleStyle).
final class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged});
  final Widget label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: label),
          const SizedBox(width: Space.normal),
          MSwitch(value: value, onChanged: onChanged),
        ],
      );
}

/// Slider from mica: thin track, filled part in the primary colour, a knob that grows on hover and while dragging.
final class MSlider extends StatefulWidget {
  const MSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String label;
  final bool enabled;

  @override
  State<MSlider> createState() => _MSliderState();
}

class _MSliderState extends State<MSlider> {
  bool _dragging = false;
  bool _hover = false;
  static const _knob = 16.0;

  void _update(Offset local, double width) {
    if (!widget.enabled) return;
    final travel = (width - _knob).clamp(1, double.infinity);
    final position = ((local.dx - _knob / 2) / travel).clamp(0.0, 1.0);
    widget.onChanged(widget.min + position * (widget.max - widget.min));
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final motion = motionAllowed(context);
    final span = widget.max - widget.min;
    final fraction = ((widget.value.clamp(widget.min, widget.max) - widget.min) / span);
    final step = span / 20;
    return Semantics(
      label: RotideTheme.textOf(context, widget.label),
      value: '${(fraction * 100).round()}%',
      onIncrease: () => widget.onChanged((widget.value + step).clamp(widget.min, widget.max)),
      onDecrease: () => widget.onChanged((widget.value - step).clamp(widget.min, widget.max)),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.45,
        child: SizedBox(
          height: 22,
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final travel = (width - _knob).clamp(1.0, double.infinity);
            return MouseRegion(
              onEnter: (_) => setState(() => _hover = widget.enabled),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) {
                  setState(() => _dragging = true);
                  _update(details.localPosition, width);
                },
                onPanUpdate: (details) => _update(details.localPosition, width),
                onPanEnd: (_) => setState(() => _dragging = false),
                onPanCancel: () => setState(() => _dragging = false),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(height: 4, decoration: ShapeDecoration(shape: const StadiumBorder(), color: palette.track)),
                    Container(
                      width: _knob / 2 + fraction * travel,
                      height: 4,
                      decoration: ShapeDecoration(shape: const StadiumBorder(), color: palette.primary),
                    ),
                    Positioned(
                      left: fraction * travel,
                      child: SpringValue(
                        value: !motion ? 1 : _dragging ? 1.18 : 1,
                        spring: MotionTokens.press,
                        builder: (context, dragScale, _) => TweenAnimationBuilder<double>(
                          tween: Tween(end: motion && _hover && !_dragging ? 1.08 : 1),
                          duration: MotionTokens.hover,
                          curve: Curves.easeOut,
                          builder: (context, hoverScale, _) => Transform.scale(
                            scale: dragScale * hoverScale,
                            child: Container(
                              width: _knob,
                              height: _knob,
                              decoration: ShapeDecoration(
                                shape: CircleBorder(side: BorderSide(color: palette.hairlineStrong, width: 0.5, strokeAlign: BorderSide.strokeAlignInside)),
                                color: palette.thumbSolid,
                                shadows: [swiftShadow(palette.shadowStrong, 2, y: 1)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
