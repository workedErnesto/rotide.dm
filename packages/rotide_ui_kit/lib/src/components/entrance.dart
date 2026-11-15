import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/motion.dart';

/// Window and card entrance: a part fades in and settles into place on the panel spring [delay] after the entrance
/// begins. It only moves pixels, so the part takes input from the first frame. With Reduce Motion it is a short fade.
final class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.shown,
    required this.child,
    this.delay = 0,
    this.rise = MotionTokens.entranceRise,
    this.dx = 0,
    this.scale = 1,
  });

  final bool shown;
  final double delay;
  final double rise;
  final double dx;
  final double scale;
  final Widget child;

  /// Delay of the step-th part of a cascade.
  static double step(int index) => index * MotionTokens.entranceStagger;

  @override
  Widget build(BuildContext context) {
    if (RotideTheme.reduceMotionOf(context)) {
      return AnimatedOpacity(opacity: shown ? 1 : 0, duration: MotionTokens.reducedFade, curve: Curves.easeOut, child: child);
    }
    return SpringValue(
      value: shown ? 1 : 0,
      spring: MotionTokens.panel,
      motion: false,
      delay: Duration(microseconds: (delay * 1e6).round()),
      child: child,
      builder: (context, progress, child) {
        final rest = 1 - progress;
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx * rest, rise * rest),
            child: Transform.scale(scale: scale + (1 - scale) * progress, child: child),
          ),
        );
      },
    );
  }
}

/// The start window wordmark: drawn glyph by glyph, each rising, coming into focus and closing in from a wider
/// spacing, one after another from the first. With Reduce Motion it uses the plain entrance.
final class AssemblingText extends StatefulWidget {
  const AssemblingText({super.key, required this.text, required this.style, required this.shown, this.delay = 0});
  final String text;
  final TextStyle style;
  final bool shown;
  final double delay;

  static const spring = Spring(MotionTokens.wordmarkLetterDuration, 0.78);

  static double stepFor(int glyphs) =>
      glyphs > 1 ? math.min(MotionTokens.wordmarkLetterStagger, MotionTokens.wordmarkStaggerCap / (glyphs - 1)) : 0;

  /// Time when the last glyph is at rest.
  static double totalFor(int glyphs) => math.max(glyphs - 1, 0) * stepFor(glyphs) + spring.settlingDuration;

  @override
  State<AssemblingText> createState() => _AssemblingTextState();
}

class _AssemblingTextState extends State<AssemblingText> with SingleTickerProviderStateMixin {
  late final int _glyphs = widget.text.runes.length;
  late final double _total = AssemblingText.totalFor(_glyphs);
  late final _controller = AnimationController(vsync: this, duration: Duration(microseconds: (_total * 1e6).round()));

  @override
  void initState() {
    super.initState();
    if (widget.shown) _start();
  }

  @override
  void didUpdateWidget(AssemblingText old) {
    super.didUpdateWidget(old);
    if (widget.shown && !old.shown) _start();
  }

  void _start() {
    Future<void>.delayed(Duration(microseconds: (widget.delay * 1e6).round()), () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (RotideTheme.reduceMotionOf(context)) {
      return Entrance(shown: widget.shown, delay: widget.delay, child: Text(widget.text, style: widget.style));
    }
    final painter = TextPainter(text: TextSpan(text: widget.text, style: widget.style), textDirection: TextDirection.ltr)..layout();
    return Semantics(
      label: widget.text,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: painter.size,
          painter: _AssemblePainter(painter, widget.text, _controller.value * _total),
        ),
      ),
    );
  }
}

class _AssemblePainter extends CustomPainter {
  _AssemblePainter(this.painter, this.text, this.time);
  final TextPainter painter;
  final String text;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final units = <(int, int)>[];
    var offset = 0;
    for (final rune in text.runes) {
      final length = rune > 0xFFFF ? 2 : 1;
      units.add((offset, offset + length));
      offset += length;
    }
    final count = units.length;
    final step = AssemblingText.stepFor(count);
    final middle = (count - 1) / 2;
    final fade = MotionTokens.wordmarkLetterDuration * 0.6;
    for (var index = 0; index < count; index++) {
      final local = time - index * step;
      if (local <= 0) continue;
      final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: units[index].$1, extentOffset: units[index].$2));
      if (boxes.isEmpty) continue;
      final box = boxes.first.toRect();
      final travel = AssemblingText.spring.value(local);
      final rest = 1 - travel;
      final opacity = math.min(1.0, local / fade);
      final blur = MotionTokens.wordmarkBlur * math.max(0, 1 - local / fade);
      canvas.save();
      canvas.translate((index - middle) * MotionTokens.wordmarkSpread * rest, MotionTokens.wordmarkRise * rest);
      final layerPaint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity);
      if (blur > 0.05) layerPaint.imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      final bounds = Rect.fromLTRB(box.left, -size.height, box.right, size.height * 2).inflate(blur * 3);
      canvas.saveLayer(bounds, layerPaint);
      canvas.clipRect(Rect.fromLTRB(box.left, -size.height, box.right, size.height * 2));
      painter.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssemblePainter old) => old.time != time || old.painter != painter;
}
