import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/motion.dart';

/// Hover and press state for a custom control, the way SwiftUI's ButtonStyle reports them: pressed while the pointer
/// is down and still inside. The arrow cursor stays, as on macOS.
final class Interactive extends StatefulWidget {
  const Interactive({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.semanticLabel,
    this.selected = false,
    this.button = true,
    this.focusable = false,
  });

  final VoidCallback? onTap;
  final bool enabled;
  final String? semanticLabel;
  final bool selected;
  final bool button;
  final bool focusable;
  final Widget Function(BuildContext context, bool hover, bool pressed) builder;

  @override
  State<Interactive> createState() => _InteractiveState();
}

class _InteractiveState extends State<Interactive> {
  bool _hover = false;
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  void didUpdateWidget(Interactive old) {
    super.didUpdateWidget(old);
    if (!_active && (_hover || _pressed)) {
      _hover = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _hover && _active, _pressed && _active);
    return Semantics(
      button: widget.button,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: _active ? widget.onTap : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: _active ? () => setState(() => _pressed = false) : null,
          onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
          onTap: _active ? widget.onTap : null,
          child: content,
        ),
      ),
    );
  }
}

/// Press feedback for rows and tiles that draw their own resting and hover states (PressStyle).
final class PressScale extends StatelessWidget {
  const PressScale({super.key, required this.pressed, required this.child, this.scale = 0.97});
  final bool pressed;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => SpringValue(
        value: pressed && motionAllowed(context) ? scale : 1,
        spring: MotionTokens.press,
        child: child,
        builder: (context, value, child) => Transform.scale(scale: value, child: child),
      );
}

/// A colour that eases to each new value over the hover duration (`Motion.hover`), on with Reduce Motion too.
final class HoverColor extends StatelessWidget {
  const HoverColor({super.key, required this.color, required this.builder, this.duration = MotionTokens.hover});
  final Color color;
  final Duration duration;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: duration,
        curve: Curves.easeOut,
        builder: (context, value, _) => builder(context, value ?? color),
      );
}

/// Reports `true` from the first frame after it is built: SwiftUI's `onAppear { shown = true }`.
final class Appear extends StatefulWidget {
  const Appear({super.key, required this.builder});
  final Widget Function(BuildContext context, bool shown) builder;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}

/// Whether spatial motion is allowed here.
bool motionAllowed(BuildContext context) => !RotideTheme.reduceMotionOf(context);
