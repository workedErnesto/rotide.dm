// Ported from the Swift Palette.swift (itself from mica's shared/tokens.json). Keep in step with
// app/assets/preview/preview.css.
import 'dart:ui';

Color _rgb(int value, [double alpha = 1]) => Color.fromARGB((alpha * 255).round(), (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);

/// One colour per appearance; Increase Contrast falls back to the normal value where no contrast variant exists.
final class _Dynamic {
  const _Dynamic(this.light, this.dark, {this.contrastLight, this.contrastDark});
  final Color light, dark;
  final Color? contrastLight, contrastDark;

  Color resolve({required bool dark, required bool contrast}) {
    if (dark) return contrast ? (contrastDark ?? this.dark) : this.dark;
    return contrast ? (contrastLight ?? light) : light;
  }
}

/// Light: bright paper shell around a pure white page and panels, near-black neutral ink, light hairlines and soft
/// shadows doing the separation. Dark: warm stone. Both resolve per appearance, Increase Contrast included.
final class RotidePalette {
  RotidePalette._(this.dark, this.contrast);

  factory RotidePalette({required bool dark, required bool contrast}) =>
      _cache.putIfAbsent((dark, contrast), () => RotidePalette._(dark, contrast));
  static final _cache = <(bool, bool), RotidePalette>{};

  final bool dark;
  final bool contrast;

  Color _c(_Dynamic value) => value.resolve(dark: dark, contrast: contrast);

  late final shell = _c(_Dynamic(_rgb(0xF5F5F3), _rgb(0x272422)));
  late final raised = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0x302C2A)));
  late final surface = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0x2A2725)));
  late final canvas = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0x181615)));
  late final ink = _c(_Dynamic(_rgb(0x111113), _rgb(0xF5F5F4)));
  late final text2 = _c(_Dynamic(_rgb(0x4D4D53), _rgb(0xA8A29E), contrastLight: _rgb(0x222226), contrastDark: _rgb(0xD6D3D1)));
  late final text3 = _c(_Dynamic(_rgb(0x88888E), _rgb(0x7C756F), contrastLight: _rgb(0x3F3F45), contrastDark: _rgb(0xA8A29E)));
  late final hairline = _c(_Dynamic(_rgb(0x111113, 0.07), _rgb(0xFFFFFF, 0.06),
      contrastLight: _rgb(0x111113, 0.45), contrastDark: _rgb(0xFFFFFF, 0.45)));
  late final hairlineStrong = _c(_Dynamic(_rgb(0x111113, 0.12), _rgb(0xFFFFFF, 0.14),
      contrastLight: _rgb(0x111113, 0.6), contrastDark: _rgb(0xFFFFFF, 0.6)));
  late final hover = _c(_Dynamic(_rgb(0x111113, 0.045), _rgb(0xFFFFFF, 0.06),
      contrastLight: _rgb(0x111113, 0.1), contrastDark: _rgb(0xFFFFFF, 0.12)));
  late final pressed = _c(_Dynamic(_rgb(0x111113, 0.08), _rgb(0xFFFFFF, 0.1)));
  late final selected = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0xFFFFFF, 0.1), contrastLight: _rgb(0xFFFFFF), contrastDark: _rgb(0xFFFFFF, 0.2)));
  late final track = _c(_Dynamic(_rgb(0x111113, 0.05), _rgb(0xFFFFFF, 0.06),
      contrastLight: _rgb(0x111113, 0.12), contrastDark: _rgb(0xFFFFFF, 0.14)));
  late final thumb = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0xFFFFFF, 0.14), contrastDark: _rgb(0xFFFFFF, 0.26)));
  late final switchOff = _c(_Dynamic(_rgb(0x111113, 0.12), _rgb(0xFFFFFF, 0.16),
      contrastLight: _rgb(0x111113, 0.35), contrastDark: _rgb(0xFFFFFF, 0.35)));
  late final knobOff = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0xD6D3D1)));
  late final primary = _c(_Dynamic(_rgb(0x18181B), _rgb(0xF5F5F4)));
  late final primaryPressed = _c(_Dynamic(_rgb(0x000000), _rgb(0xD6D3D1)));
  late final onPrimary = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0x0C0A09)));
  late final danger = _c(_Dynamic(_rgb(0xC81E1E), _rgb(0xF87171)));
  late final live = _c(_Dynamic(_rgb(0xDC2626), _rgb(0xF87171)));
  late final shadow = _c(_Dynamic(_rgb(0x111113, 0.07), _rgb(0x000000, 0.45)));
  late final shadowStrong = _c(_Dynamic(_rgb(0x111113, 0.14), _rgb(0x000000, 0.6)));

  /// Shadow of shell menus: soft enough that its blur fades out well inside the menu window, so no edge of it shows.
  late final menuShadow = _c(_Dynamic(_rgb(0x111113, 0.1), _rgb(0x000000, 0.3)));

  /// Dims the window under a modal card. Lighter in light mode, so the white card does not sit in a grey haze.
  late final scrim = _c(_Dynamic(_rgb(0x111113, 0.18), _rgb(0x000000, 0.45)));
  late final field = _c(_Dynamic(_rgb(0xFFFFFF, 0.9), _rgb(0xFFFFFF, 0.06), contrastLight: _rgb(0xFFFFFF), contrastDark: _rgb(0xFFFFFF, 0.14)));
  late final fieldHover = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0xFFFFFF, 0.1), contrastLight: _rgb(0xFFFFFF), contrastDark: _rgb(0xFFFFFF, 0.2)));
  late final fieldBorder = _c(_Dynamic(_rgb(0x111113, 0.07), _rgb(0xFFFFFF, 0),
      contrastLight: _rgb(0x111113, 0.45), contrastDark: _rgb(0xFFFFFF, 0.45)));
  late final fieldShadow = _c(_Dynamic(_rgb(0x111113, 0.05), _rgb(0x000000, 0)));
  late final thumbSolid = _c(_Dynamic(_rgb(0xFFFFFF), _rgb(0xE7E5E4)));

  /// Secondary button fill: a quiet tonal surface instead of an outline.
  late final secondary = _c(_Dynamic(_rgb(0x111113, 0.05), _rgb(0xFFFFFF, 0.08),
      contrastLight: _rgb(0x111113, 0.14), contrastDark: _rgb(0xFFFFFF, 0.18)));
  late final secondaryHover = _c(_Dynamic(_rgb(0x111113, 0.08), _rgb(0xFFFFFF, 0.12),
      contrastLight: _rgb(0x111113, 0.2), contrastDark: _rgb(0xFFFFFF, 0.24)));
  late final secondaryPressed = _c(_Dynamic(_rgb(0x111113, 0.12), _rgb(0xFFFFFF, 0.16)));
  late final focusRing = _c(_Dynamic(_rgb(0x111113, 0.5), _rgb(0xFFFFFF, 0.5), contrastLight: _rgb(0x111113), contrastDark: _rgb(0xFFFFFF)));

  // Editor colours (EditorStyle in the Swift version).
  late final link = _c(_Dynamic(_rgb(0x0A5BD3), _rgb(0x6EA8FE)));
  late final codeFill = _c(_Dynamic(_rgb(0x111113, 0.05), _rgb(0xFFFFFF, 0.06)));
  late final textSelection = _c(_Dynamic(_rgb(0x0A5BD3, 0.16), _rgb(0x6EA8FE, 0.28)));
}
