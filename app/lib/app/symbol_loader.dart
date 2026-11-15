import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// Every SF Symbol the interface draws, with the size and weight it is drawn at.
const symbolRequests = <(String, double, FontWeight)>[
  ('sidebar.left', 28 * 0.48, FontWeight.w500),
  ('gearshape', 28 * 0.48, FontWeight.w500),
  ('square.and.arrow.up', 28 * 0.48, FontWeight.w500),
  ('xmark', 36 * 0.48, FontWeight.w500),
  ('book', 10, FontWeight.w500),
  ('pencil', 10, FontWeight.w500),
  ('paintbrush', 12, FontWeight.w500),
  ('textformat.size', 12, FontWeight.w500),
  ('info.circle', 12, FontWeight.w500),
  ('chevron.left.forwardslash.chevron.right', 13, FontWeight.w500),
  ('doc.richtext', 13, FontWeight.w500),
  ('doc.text', 13, FontWeight.w500),
  ('textformat', 13, FontWeight.w500),
  ('text.alignleft', 13, FontWeight.w500),
  ('square.and.arrow.down', 13, FontWeight.w500),
  ('printer', 13, FontWeight.w500),
  ('list.bullet.indent', 16, FontWeight.w500),
  ('doc.text', 15, FontWeight.w500),
];

/// Draws the symbols natively once, before the first frame, so icons never pop in. macOS only: Windows uses its
/// icon font.
Future<void> loadSymbols(NativeBridge bridge) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  final images = await bridge.symbols([for (final (name, size, weight) in symbolRequests) (name, size, weight.value)]);
  for (var index = 0; index < images.length && index < symbolRequests.length; index++) {
    final bytes = images[index];
    if (bytes == null) continue;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final (name, size, weight) = symbolRequests[index];
    SymbolImages.put(name, size, weight, frame.image);
  }
}

/// Calibrates letter spacing against AppKit so text lines are as wide as in the Swift version.
Future<void> calibrateTracking(NativeBridge bridge) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  const sample = 'Обычный абзац с жирным текстом и ссылкой: Hello, World 0123456789 rotide.dm';
  const sizes = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 17.0, 20.0, 24.0, 30.0, 40.0];
  final native = await bridge.textWidths(sample, sizes);
  if (native.length != sizes.length) return;
  final count = sample.length;
  for (var i = 0; i < sizes.length; i++) {
    final style = TextStyle(fontFamily: RotideFonts.sans, fontSize: sizes[i], fontVariations: RotideFonts.opticalSize(sizes[i]));
    final painter = TextPainter(text: TextSpan(text: sample, style: style), textDirection: TextDirection.ltr)..layout();
    RotideFonts.trackingTable[sizes[i]] = (native[i] - painter.width) / count;
  }
}
