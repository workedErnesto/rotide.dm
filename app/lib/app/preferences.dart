import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

/// Preferences of the whole app: kept by the host (user defaults on macOS), cached here, and changed in every window
/// at once. The keys are the ones the Swift version used.
final class Preferences extends ChangeNotifier implements PreferenceStore {
  Preferences(Map<String, Object?> initial, this._bridge) : _values = Map.of(initial) {
    _subscription = _bridge.preferenceChanges.listen((change) {
      final (key, value) = change;
      if (_values[key] == value) return;
      _values[key] = value;
      notifyListeners();
    });
  }

  final NativeBridge _bridge;
  final Map<String, Object?> _values;
  late final StreamSubscription<(String, Object?)> _subscription;

  @override
  Object? read(String key) => _values[key];

  @override
  void write(String key, Object? value) {
    _values[key] = value;
    notifyListeners();
    _bridge.setPreference(key, value);
  }

  String get appearance => _values['appearance'] as String? ?? 'system';
  set appearance(String value) => write('appearance', value);

  bool get frosted => _values['frosted'] as bool? ?? true;
  set frosted(bool value) => write('frosted', value);

  double get transparency => (_values['transparency'] as num?)?.toDouble() ?? 0.55;
  set transparency(double value) => write('transparency', value);

  double get zoom => (_values['zoom'] as num?)?.toDouble() ?? 1;
  set zoom(double value) => write('zoom', value);

  String get appIcon => _values['appIcon'] as String? ?? 'default';
  set appIcon(String value) {
    write('appIcon', value);
    _bridge.setIcon(value);
  }

  /// The interface language: the user's choice, otherwise Russian when the system prefers it and English elsewhere
  /// (the rule mica uses; the host's menus follow the same rule).
  RotideLanguage get language => switch (_values['language']) {
        'ru' => RotideLanguage.ru,
        'en' => RotideLanguage.en,
        _ => systemLanguage(),
      };
  set language(RotideLanguage value) => write('language', value.name);

  static RotideLanguage systemLanguage([List<Locale>? locales]) {
    for (final locale in locales ?? PlatformDispatcher.instance.locales) {
      if (locale.languageCode == 'ru') return RotideLanguage.ru;
      if (locale.languageCode == 'en') return RotideLanguage.en;
    }
    return RotideLanguage.en;
  }

  bool get capitalized => _values['capitalizedLabels'] as bool? ?? false;
  set capitalized(bool value) => write('capitalizedLabels', value);

  bool get sidebar => _values['sidebar'] as bool? ?? true;
  set sidebar(bool value) => write('sidebar', value);

  double get sidebarWidth => ((_values['sidebarWidth'] as num?)?.toDouble() ?? Chrome.sidebar).clamp(Chrome.sidebarMin, Chrome.sidebarMax);
  set sidebarWidth(double value) => write('sidebarWidth', value);

  late final history = RecentDocumentHistory(this);

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// System accessibility settings as the host reports them, updated live.
final class AccessibilitySettings extends ValueNotifier<RotideAccessibility> {
  AccessibilitySettings(Map<String, bool> initial, NativeBridge bridge) : super(_from(initial)) {
    _subscription = bridge.accessibilityChanges.listen((map) => value = _from(map));
  }

  late final StreamSubscription<Map<String, bool>> _subscription;

  static RotideAccessibility _from(Map<String, bool> map) => RotideAccessibility(
        reduceMotion: map['reduceMotion'] ?? false,
        reduceTransparency: map['reduceTransparency'] ?? false,
        increaseContrast: map['increaseContrast'] ?? false,
      );

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
