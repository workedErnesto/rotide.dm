import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../tokens/geometry.dart';
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
