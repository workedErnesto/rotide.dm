import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../tokens/geometry.dart';
import 'interactive.dart';
import 'surfaces.dart';
import 'symbol.dart';
import 'tooltip.dart';
import 'label_text.dart';

enum ButtonKind { primary, secondary, ghost, destructive }

/// Filled rounded rectangle with a tonal secondary and the press spring (MButtonStyle, from mica).
final class MButton extends StatelessWidget {
  const MButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.secondary,
    this.compact = false,
    this.fill = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final bool compact;
  final bool fill;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final active = enabled && onPressed != null;
    return Interactive(
      onTap: onPressed,
      enabled: active,
      semanticLabel: label,
      builder: (context, hover, pressed) {
        final foreground = switch (kind) {
          ButtonKind.primary => palette.onPrimary,
          ButtonKind.destructive => palette.danger,
          _ => palette.ink,
        };
        final background = switch (kind) {
          ButtonKind.primary => pressed ? palette.primaryPressed : palette.primary.withValues(alpha: palette.primary.a * (hover ? 0.86 : 1)),
          ButtonKind.secondary => pressed ? palette.secondaryPressed : hover ? palette.secondaryHover : palette.secondary,
          ButtonKind.ghost => pressed ? palette.pressed : hover ? palette.hover : const Color(0x00000000),
          ButtonKind.destructive => palette.danger.withValues(alpha: pressed ? 0.2 : hover ? 0.15 : 0.1),
        };
        return Opacity(
          opacity: active ? 1 : 0.42,
          child: PressScale(
            pressed: pressed,
            scale: 0.965,
            child: HoverColor(
              color: background,
              builder: (context, color) => Container(
                height: compact ? 26 : 32,
                width: fill ? double.infinity : null,
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                alignment: Alignment.center,
                decoration: continuousDecoration(radius: compact ? Radii.icon - 1 : Radii.icon, color: color),
                child: LabelText(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: RotideFonts.system(compact ? 12 : 13, weight: FontWeight.w500, color: foreground),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A square symbol button of the top bar and settings (IconButton).
final class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.symbol,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.size = 28,
    this.symbolOffsetY = 0,
    this.enabled = true,
  });

  final String symbol;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double symbolOffsetY;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Hint(
      message: label,
      child: Interactive(
        onTap: onPressed,
        enabled: enabled,
        semanticLabel: label,
        selected: selected,
        builder: (context, hover, pressed) {
          final foreground = enabled ? (selected || hover ? palette.ink : palette.text2) : palette.text3.withValues(alpha: palette.text3.a * 0.6);
          final background = selected ? palette.pressed : hover ? palette.hover : const Color(0x00000000);
          return PressScale(
            pressed: pressed,
            scale: 0.9,
            child: HoverColor(
              color: background,
              builder: (context, fill) => HoverColor(
                color: foreground,
                builder: (context, ink) => Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: continuousDecoration(radius: Radii.icon, color: fill),
                  child: Transform.translate(
                    offset: Offset(0, symbolOffsetY),
                    child: Symbol(symbol, size: size * 0.48, color: ink),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
