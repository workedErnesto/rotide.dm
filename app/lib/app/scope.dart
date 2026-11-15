import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';

import 'preferences.dart';

/// Page assets shared by the live preview, the HTML export and printing.
final class PageAssets {
  const PageAssets({required this.css, required this.script});
  final String css;
  final String script;
}

/// What every widget of a window may need: preferences, system accessibility settings, the native bridge and the page
/// assets. Rebuilds dependants when preferences or accessibility change.
final class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.preferences,
    required this.accessibility,
    required this.bridge,
    required this.assets,
    required this.revision,
    required super.child,
  });

  final Preferences preferences;
  final AccessibilitySettings accessibility;
  final NativeBridge bridge;
  final PageAssets assets;

  /// Bumped on every preference or accessibility change.
  final int revision;

  /// The blurred shell is on: the user wants it and the system does not ask for less transparency or more contrast.
  bool get frostActive => preferences.frosted && !accessibility.value.reduceTransparency && !accessibility.value.increaseContrast;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => revision != oldWidget.revision;
}
