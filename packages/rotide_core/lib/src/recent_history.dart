import 'dart:io';

/// Where preferences live: UserDefaults on macOS (so the Dock tile plug-in reads the same values), a JSON file in the
/// application data folder on Windows. Implemented by the app; tests use a map.
abstract interface class PreferenceStore {
  Object? read(String key);
  void write(String key, Object? value);
}

/// Recent file paths live in preferences, independently of the system's own recent items. The key and the limit are
/// the ones the Swift version used, so history carries over to this build.
final class RecentDocumentHistory {
  RecentDocumentHistory(this.store);

  final PreferenceStore store;
  static const key = 'recentDocumentPaths';
  static const limit = 20;

  List<String> get paths => [for (final value in (store.read(key) as List?) ?? const []) if (value is String) value];

  /// Fills an empty history once from the system's list of recent files.
  void migrateIfNeeded(List<String> systemPaths) {
    if (store.read(key) != null) return;
    store.write(key, _unique(systemPaths.map(standardize)).take(limit).toList());
  }

  void record(String path) {
    final standard = standardize(path);
    store.write(key, [standard, ...paths.where((existing) => existing != standard)].take(limit).toList());
  }

  void remove(String path) {
    final standard = standardize(path);
    store.write(key, paths.where((existing) => existing != standard).toList());
  }

  void clear() => store.write(key, const <String>[]);

  static String standardize(String path) {
    final windows = Platform.isWindows;
    return Uri.file(File(path).absolute.path, windows: windows).normalizePath().toFilePath(windows: windows);
  }

  static Iterable<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return values.where(seen.add);
  }
}
