import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tokens/palette.dart';

/// System settings the interface follows; read from the native layer, which knows them on both systems.
@immutable
final class RotideAccessibility {
  const RotideAccessibility({this.reduceMotion = false, this.reduceTransparency = false, this.increaseContrast = false});
  final bool reduceMotion;
  final bool reduceTransparency;
  final bool increaseContrast;

  @override
  bool operator ==(Object other) =>
      other is RotideAccessibility &&
      other.reduceMotion == reduceMotion &&
      other.reduceTransparency == reduceTransparency &&
      other.increaseContrast == increaseContrast;

  @override
  int get hashCode => Object.hash(reduceMotion, reduceTransparency, increaseContrast);
}

/// Palette, accessibility and fonts for everything below it.
final class RotideTheme extends InheritedWidget {
  const RotideTheme({super.key, required this.dark, required this.accessibility, this.capitalized = false, required super.child});

  final bool dark;
  final RotideAccessibility accessibility;

  /// The interface text starts with a capital letter (the user's choice); by default it starts with a lowercase one.
  final bool capitalized;

  RotidePalette get palette => RotidePalette(dark: dark, contrast: accessibility.increaseContrast);
  bool get reduceMotion => accessibility.reduceMotion;

  static RotideTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<RotideTheme>();
    assert(theme != null, 'RotideTheme is missing above this widget');
    return theme!;
  }

  static RotidePalette paletteOf(BuildContext context) => of(context).palette;
  static bool reduceMotionOf(BuildContext context) => of(context).reduceMotion;
  static bool capitalizedOf(BuildContext context) => of(context).capitalized;

  @override
  bool updateShouldNotify(RotideTheme oldWidget) =>
      dark != oldWidget.dark || accessibility != oldWidget.accessibility || capitalized != oldWidget.capitalized;
}

/// System fonts: SF Pro on macOS, Segoe UI Variable on Windows. Nothing is bundled.
abstract final class RotideFonts {
  static bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

  static String get sans => _mac ? '.AppleSystemUIFont' : 'Segoe UI Variable Text';
  static List<String> get sansFallback => _mac ? const [] : const ['Segoe UI', 'Segoe UI Emoji'];
  static String get mono => _mac ? 'SF Mono' : 'Cascadia Mono';
  static List<String> get monoFallback => _mac ? const ['Menlo'] : const ['Consolas'];

  /// SF Pro is one variable font with an optical size axis; AppKit picks the size's own optical size (Text below 20 pt,
  /// Display above), Flutter does not unless asked.
  static List<FontVariation>? opticalSize(double size) => _mac ? [FontVariation('opsz', size)] : null;

  /// Letter spacing per point size that makes Flutter's line as wide as AppKit's (AppKit tracks the system font by
  /// size; Skia does not). Measured at launch on macOS, empty elsewhere.
  static final trackingTable = <double, double>{};

  static double tracking(double size) {
    if (trackingTable.isEmpty) return 0;
    final sizes = trackingTable.keys.toList()..sort();
    if (size <= sizes.first) return trackingTable[sizes.first]! * size / sizes.first;
    if (size >= sizes.last) return trackingTable[sizes.last]! * size / sizes.last;
    for (var i = 1; i < sizes.length; i++) {
      if (size <= sizes[i]) {
        final a = sizes[i - 1], b = sizes[i];
        final t = (size - a) / (b - a);
        return trackingTable[a]! + (trackingTable[b]! - trackingTable[a]!) * t;
      }
    }
    return 0;
  }

  /// How far a line of lowercase interface text sits below the middle of its line box: the box keeps room above the
  /// x-height for capitals and below the baseline for descenders, and rotide.dm writes its labels from a lowercase
  /// letter. Measured in the running app on the macOS system font at 12.5 and 13 pt (1.5 to 1.75 pt). Segoe UI on
  /// Windows has not been measured, so nothing is raised there.
  static double lowercaseDrop(double size) => _mac ? 0.125 * size : 0;

  /// SwiftUI `.system(size:weight:)`.
  static TextStyle system(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height, double? tracking}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: sansFallback,
        fontSize: size,
        fontWeight: weight,
        fontVariations: opticalSize(size),
        color: color,
        height: height,
        letterSpacing: (tracking ?? 0) + RotideFonts.tracking(size),
        decoration: TextDecoration.none,
      );

  static TextStyle monospace(double size, {Color? color, double? height}) => TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        height: height,
        decoration: TextDecoration.none,
      );
}
