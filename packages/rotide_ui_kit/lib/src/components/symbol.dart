import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Rendered symbol images. On macOS the native layer draws real SF Symbols (the app's existing icons) into
/// template bitmaps once at launch; on Windows the system icon font stands in, since SF Symbols may not ship there.
abstract final class SymbolImages {
  static final _images = <String, ui.Image>{};

  /// Pixel density the native layer renders at.
  static const scale = 2.0;

  static String key(String name, double size, FontWeight weight) => '$name@$size/${weight.value}';

  static void put(String name, double size, FontWeight weight, ui.Image image) => _images[key(name, size, weight)] = image;

  static ui.Image? get(String name, double size, FontWeight weight) => _images[key(name, size, weight)];

  /// Every symbol, size and weight the interface draws, so the images exist before the first frame.
  static final requests = <(String, double, FontWeight)>{};

  /// Segoe Fluent Icons (Windows 11) and Segoe MDL2 Assets (Windows 10) code points for the SF Symbols in use.
  static const windowsGlyphs = <String, int>{
    'gearshape': 0xE713,
    'sidebar.left': 0xE90C,
    'square.and.arrow.up': 0xE72D,
    'square.and.arrow.down': 0xE74E,
    'printer': 0xE749,
    'xmark': 0xE711,
    'list.bullet.indent': 0xE8FD,
    'doc.text': 0xE8A5,
    'doc.richtext': 0xEA90,
    'chevron.left.forwardslash.chevron.right': 0xE943,
    'text.alignleft': 0xE8E4,
    'textformat': 0xE8D2,
    'textformat.size': 0xE8E9,
    'info.circle': 0xE946,
    'paintbrush': 0xE790,
    'book': 0xE736,
    'pencil': 0xE70F,
  };
}

/// `Image(systemName:)` with `.font(.system(size:weight:))` and a foreground colour.
final class Symbol extends StatelessWidget {
  const Symbol(this.name, {super.key, required this.size, this.weight = FontWeight.w500, required this.color});

  final String name;
  final double size;
  final FontWeight weight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final image = SymbolImages.get(name, size, weight);
    if (image != null) {
      return RawImage(
        image: image,
        width: image.width / SymbolImages.scale,
        height: image.height / SymbolImages.scale,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      );
    }
    final glyph = SymbolImages.windowsGlyphs[name];
    if (glyph != null && defaultTargetPlatform == TargetPlatform.windows) {
      return Text(
        String.fromCharCode(glyph),
        style: TextStyle(
          fontFamily: 'Segoe Fluent Icons',
          fontFamilyFallback: const ['Segoe MDL2 Assets'],
          fontSize: size,
          color: color,
          height: 1,
          decoration: TextDecoration.none,
        ),
      );
    }
    return SizedBox.square(dimension: size);
  }
}
