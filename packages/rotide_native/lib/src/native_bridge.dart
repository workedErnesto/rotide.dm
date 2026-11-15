import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What this engine's window is.
enum WindowKind { start, document }

/// Launch information of this window's engine.
final class LaunchInfo {
  const LaunchInfo({
    required this.kind,
    required this.path,
    required this.preferences,
    required this.accessibility,
    required this.fullScreen,
  });

  final WindowKind kind;
  final String? path;
  final Map<String, Object?> preferences;
  final Map<String, bool> accessibility;
  final bool fullScreen;
}

/// A menu bar or keyboard command routed to this window: save, export, mode, find and so on.
final class MenuCommand {
  const MenuCommand(this.name, [this.tag = 0]);
  final String name;
  final int tag;
}

/// The bridge of one window's engine to the host: window chrome, documents, panels, preferences shared by all
/// windows, the application icon, symbols, printing. The same channel is implemented on macOS and Windows.
final class NativeBridge {
  NativeBridge._() {
    _channel.setMethodCallHandler(_handle);
  }

  static final instance = NativeBridge._();
  static const _channel = MethodChannel('rotide/native');

  final _menu = StreamController<MenuCommand>.broadcast();
  final _preference = StreamController<(String, Object?)>.broadcast();
  final _accessibility = StreamController<Map<String, bool>>.broadcast();
  final fullScreen = ValueNotifier(false);

  /// The application version shown in settings.
  String version = '';
  final isKey = ValueNotifier(true);

  /// The window is maximized (Windows caption buttons show restore instead of maximize).
  final maximized = ValueNotifier(false);

  /// The pointer is over the maximize button, as the host reports it while the system shows snap layouts.
  final maximizeHover = ValueNotifier(false);

  /// A file is being dragged over the start window.
  final dropping = ValueNotifier(false);

  /// Answers "may this window close?"; the document shows its save question here.
  Future<bool> Function()? onShouldClose;

  Stream<MenuCommand> get menu => _menu.stream;
  Stream<(String, Object?)> get preferenceChanges => _preference.stream;
  Stream<Map<String, bool>> get accessibilityChanges => _accessibility.stream;

  bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'menu':
        final map = (args as Map).cast<String, Object?>();
        _menu.add(MenuCommand(map['command']! as String, (map['tag'] as int?) ?? 0));
      case 'preference':
        final map = (args as Map).cast<String, Object?>();
        _preference.add((map['key']! as String, map['value']));
      case 'accessibility':
        _accessibility.add((args as Map).cast<String, bool>());
      case 'fullScreen':
        fullScreen.value = args as bool;
      case 'key':
        isKey.value = args as bool;
      case 'dropping':
        dropping.value = args as bool;
      case 'maximized':
        maximized.value = args as bool;
      case 'maximizeHover':
        maximizeHover.value = args as bool;
      case 'shouldClose':
        return await (onShouldClose?.call() ?? Future.value(true));
    }
    return null;
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) => _channel.invokeMethod<T>(method, arguments);

  Future<LaunchInfo> launch(List<String> args) async {
    final info = (await _call<Map<Object?, Object?>>('launch'))?.cast<String, Object?>() ?? const {};
    final kindName = info['kind'] as String? ?? (args.isNotEmpty ? args.first : 'start');
    final path = info['path'] as String? ?? (args.length > 1 && args[1].isNotEmpty ? args[1] : null);
    fullScreen.value = info['fullScreen'] as bool? ?? false;
    version = info['version'] as String? ?? '';
    return LaunchInfo(
      kind: kindName == 'document' ? WindowKind.document : WindowKind.start,
      path: path,
      preferences: (info['preferences'] as Map?)?.cast<String, Object?>() ?? const {},
      accessibility: (info['accessibility'] as Map?)?.cast<String, bool>() ?? const {},
      fullScreen: fullScreen.value,
    );
  }

  // Window

  Future<void> ready() => _call('ready');
  Future<void> setFrost(bool enabled) => _call('setFrost', {'enabled': enabled});

  /// Dark or light window frame and backdrop on Windows; macOS follows the app appearance by itself.
  Future<void> setDark(bool dark) => isMac ? Future.value() : _call('setDark', {'dark': dark});

  /// Where the Windows caption buttons are, so the maximize button can offer snap layouts.
  Future<void> setCaptionButtons(Map<String, List<double>> rects) => isMac ? Future.value() : _call('captionButtons', rects);

  Future<void> minimize() => _call('minimize');
  Future<void> toggleMaximize() => _call('doubleClick');
  Future<void> setDocument({String? path, required String title, required bool edited}) =>
      _call('setDocument', {'path': path, 'title': title, 'edited': edited});
  Future<void> setState(Map<String, Object?> state) => _call('setState', state);
  Future<void> drag() => _call('drag');
  Future<void> doubleClick() => _call('doubleClick');
  Future<void> close() => _call('close');
  Future<void> performClose() => _call('performClose');

  // Documents and panels

  Future<void> openDocument(String path) => _call('openDocument', {'path': path});
  Future<void> newDocument() => _call('newDocument');
  Future<void> showStart() => _call('showStart');
  Future<void> openPanel() => _call('openPanel');
  Future<String?> savePanel({required String title, String? prompt, required String name, String? directory, required String extension}) =>
      _call<String>('savePanel', {'title': title, 'prompt': prompt, 'name': name, 'directory': directory, 'extension': extension});

  // Preferences

  Future<void> setPreference(String key, Object? value) => _call('setPreference', {'key': key, 'value': value});

  // Application icon

  Future<void> setIcon(String name) => _call('setIcon', {'name': name});

  // System

  Future<List<Uint8List?>> symbols(List<(String, double, int)> requests) async {
    final result = await _call<List<Object?>>('symbols', {
      'requests': [for (final (name, size, weight) in requests) {'name': name, 'size': size, 'weight': weight}],
    });
    return [for (final item in result ?? const []) item as Uint8List?];
  }

  Future<List<double>> textWidths(String sample, List<double> sizes) async {
    final result = await _call<List<Object?>>('textWidths', {'sample': sample, 'sizes': sizes});
    return [for (final value in result ?? const []) (value as num).toDouble()];
  }

  Future<void> openUrl(String url) => _call('openURL', {'url': url});
  Future<void> reveal(String path) => _call('reveal', {'path': path});
  Future<void> beep() => _call('beep');

  /// Prints the page (with the system print panel) or saves it as PDF; returns an error message or null.
  Future<String?> print({required String html, String? base, required String title}) =>
      _call<String>('print', {'html': html, 'base': base, 'title': title});
  Future<String?> pdf({required String html, String? base, required String title, required String path}) =>
      _call<String>('pdf', {'html': html, 'base': base, 'title': title, 'path': path});
}
