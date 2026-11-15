import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/geometry.dart';
import '../tokens/motion.dart';
import 'symbol.dart';
import 'label_text.dart';

/// SwiftUI `.shadow(color:radius:y:)`: its radius is the Gaussian standard deviation, Flutter's blur radius is not.
BoxShadow swiftShadow(Color color, double radius, {double y = 0}) =>
    BoxShadow(color: color, blurRadius: radius <= 0.5 ? 0 : (radius - 0.5) / 0.57735, offset: Offset(0, y));

/// A rounded rectangle with Apple's continuous corners (`RoundedRectangle(style: .continuous)`).
ShapeBorder continuous(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius), side: side);

/// Fill, optional hairline border inside the shape, and shadows; what SwiftUI builds from background, overlay with
/// strokeBorder and shadow.
ShapeDecoration continuousDecoration({
  required double radius,
  Color? color,
  Color? border,
  double borderWidth = 1,
  List<BoxShadow>? shadows,
}) =>
    ShapeDecoration(
      color: color,
      // SwiftUI casts a shadow from what the view draws, so a translucent fill casts a fainter one.
      shadows: color == null || color.a >= 1
          ? shadows
          : shadows
              ?.map((shadow) => BoxShadow(
                    color: shadow.color.withValues(alpha: shadow.color.a * color.a),
                    blurRadius: shadow.blurRadius,
                    spreadRadius: shadow.spreadRadius,
                    offset: shadow.offset,
                  ))
              .toList(),
      shape: continuous(radius, side: border == null ? BorderSide.none : BorderSide(color: border, width: borderWidth, strokeAlign: BorderSide.strokeAlignInside)),
    );

final class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = RotideTheme.paletteOf(context).hairline;
    return vertical ? SizedBox(width: 1, child: ColoredBox(color: color)) : SizedBox(height: 1, child: ColoredBox(color: color));
  }
}

/// Raised floating surface: menus and panels drawn by rotide.dm.
final class RaisedSurface extends StatelessWidget {
  const RaisedSurface({super.key, required this.child, this.radius = Radii.panel});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return DecoratedBox(
      decoration: continuousDecoration(radius: radius, color: palette.raised, shadows: [swiftShadow(palette.menuShadow, 8, y: 3)]),
      position: DecorationPosition.background,
      child: DecoratedBox(
        decoration: continuousDecoration(radius: radius, border: palette.hairline),
        position: DecorationPosition.foreground,
        child: child,
      ),
    );
  }
}

/// Document card: canvas fill, hairline and the soft 6 pt shadow of mica's page card.
///
/// The hairline is painted under the content, which sits inside it. On macOS the page is a native web view, and
/// Flutter takes every rectangle it paints above a native view out of that view's hit testing: a border drawn in
/// front would cover the whole card and the page would get no scrolling, clicks or selection.
final class CardSurface extends StatelessWidget {
  const CardSurface({super.key, required this.child});
  final Widget child;

  /// Width of the hairline around the content.
  static const double inset = 1;

  /// Corner radius of the content inside the hairline, concentric with the card.
  static const double contentRadius = Radii.card - inset;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return DecoratedBox(
      decoration: continuousDecoration(radius: Radii.card, color: palette.canvas, shadows: [swiftShadow(palette.shadow, 6, y: 2)]),
      child: DecoratedBox(
        decoration: continuousDecoration(radius: Radii.card, border: palette.hairline, borderWidth: inset),
        child: Padding(
          padding: const EdgeInsets.all(inset),
          child: ClipRSuperellipse(borderRadius: BorderRadius.circular(contentRadius), child: child),
        ),
      ),
    );
  }
}

/// A window-level card: settings and dialogs.
final class ModalSurface extends StatelessWidget {
  const ModalSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return DecoratedBox(
      decoration: continuousDecoration(radius: Radii.modal, color: palette.canvas, shadows: [swiftShadow(palette.shadowStrong, 30, y: 14)]),
      child: DecoratedBox(
        decoration: continuousDecoration(radius: Radii.modal, border: palette.hairline),
        position: DecorationPosition.foreground,
        child: ClipRSuperellipse(borderRadius: BorderRadius.circular(Radii.modal), child: child),
      ),
    );
  }
}

final class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.symbol, required this.text});
  final String symbol;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: continuousDecoration(radius: 11, color: palette.track),
            child: Symbol(symbol, size: 16, weight: FontWeight.w500, color: palette.text3),
          ),
          const SizedBox(height: Space.normal),
          LabelText(text, textAlign: TextAlign.center, style: RotideFonts.system(12.5, color: palette.text3)),
        ],
      ),
    );
  }
}

/// The highlight of a menu: one plate behind the rows that slides to the row under the pointer (or the keyboard
/// choice) on the snappy spring, the way the settings navigation moves its selection, and fades in and out over the
/// hover duration. [top] is the row's offset inside [child], null when no row is highlighted; a plate that has faded
/// out appears in place instead of sliding from the last row. With Reduce Motion it moves at once and only fades.
final class MenuHighlight extends StatefulWidget {
  const MenuHighlight({super.key, required this.top, required this.height, required this.child, this.radius = Radii.row});
  final double? top;
  final double height;
  final double radius;
  final Widget child;

  @override
  State<MenuHighlight> createState() => _MenuHighlightState();
}

class _MenuHighlightState extends State<MenuHighlight> with TickerProviderStateMixin {
  late final _position = SpringVector(vsync: this, initial: [widget.top ?? 0]);
  late final _opacity = AnimationController(vsync: this, duration: MotionTokens.hover, value: widget.top == null ? 0 : 1);
  late final _changes = Listenable.merge([_position, _opacity]);
  late bool _shown = widget.top != null;

  @override
  void didUpdateWidget(MenuHighlight old) {
    super.didUpdateWidget(old);
    final top = widget.top;
    if (top == null) {
      if (_shown) _opacity.animateTo(0, curve: Curves.easeOut);
      _shown = false;
      return;
    }
    if (top != _position.targets.first) {
      final hidden = _opacity.value < 0.05;
      _position.animateTo([top], hidden || RotideTheme.reduceMotionOf(context) ? null : MotionTokens.snappy);
    }
    if (!_shown) _opacity.animateTo(1, curve: Curves.easeOut);
    _shown = true;
  }

  @override
  void dispose() {
    _position.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = RotideTheme.paletteOf(context).hover;
    return Stack(
      children: [
        ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => Positioned(
            left: 0,
            right: 0,
            top: _position.values.first,
            height: widget.height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: continuousDecoration(radius: widget.radius, color: color.withValues(alpha: color.a * _opacity.value)),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
