import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/preferences.dart';
import '../app/scope.dart';
import '../shell/shell.dart';

/// The document is either read as a page or edited in one card.
enum ViewMode {
  read('чтение', 'book'),
  edit('правка', 'pencil');

  const ViewMode(this.title, this.symbol);
  final String title;
  final String symbol;
}

enum ExportFormat {
  html('веб-страница HTML', 'chevron.left.forwardslash.chevron.right', 'html'),
  pdf('документ PDF', 'doc.richtext', 'pdf'),
  word('документ Word', 'doc.text', 'docx'),
  rtf('текст RTF', 'textformat', 'rtf'),
  text('простой текст', 'text.alignleft', 'txt');

  const ExportFormat(this.title, this.symbol, this.extension);
  final String title;
  final String symbol;
  final String extension;
}

/// A Markdown file and the state of its window: the text, saving, the unsaved-changes question, reverting, reloading
/// after another app changed the file, export, and what the chrome shows. NSDocument's job in the Swift version.
final class DocumentController extends ChangeNotifier {
  DocumentController({String? path, required this.preferences, required this.bridge, required this.assets})
      : mode = path == null ? ViewMode.edit : ViewMode.read {
    bridge.onShouldClose = shouldClose;
    preferences.addListener(_preferencesChanged);
    _zoom = preferences.zoom;
    if (path != null) {
      _open(path);
    } else {
      _untitledNumber = ++_untitledCount;
      _publishDocument();
    }
    _publishState();
  }

  final Preferences preferences;
  final NativeBridge bridge;
  final PageAssets assets;

  static int _untitledCount = 0;
  int _untitledNumber = 0;

  String? path;
  String _text = '';
  String _saved = '';
  DateTime? _modified;
  StreamSubscription<FileSystemEvent>? _watch;

  ViewMode mode;
  bool narrow = false;
  bool narrowSidebar = false;
  bool settingsShown = false;
  bool exportMenu = false;
  DialogRequest? dialog;
  ExportFormat? exporting;
  String? activeAnchor;
  RenderedMarkdown rendered = RenderedMarkdown.empty;
  TextStats stats = TextStats('');
  double _zoom = 1;

  /// Bumped when the text changes from outside the editor (opening, reverting), so the editor reloads it.
  int revision = 0;
  final _pendingErrors = <(String, String)>[];
  final _reveal = StreamController<Heading>.broadcast();
  Timer? _renderTimer;
  bool _closeAsked = false;
  final _closeReplies = <Completer<bool>>[];

  String get text => _text;
  bool get edited => _text != _saved;
  bool get sidebarVisible => narrow ? narrowSidebar : preferences.sidebar;
  double get zoom => _zoom;
  Stream<Heading> get reveal => _reveal.stream;
  String? get baseDirectory => path == null ? null : File(path!).parent.path;

  String get displayName {
    final current = path;
    if (current != null) return current.split(Platform.pathSeparator).last;
    return _untitledNumber <= 1 ? 'Без названия' : 'Без названия $_untitledNumber';
  }

  /// Base of exported file names: the document name without its extension.
  String get exportBaseName {
    final name = displayName;
    final dot = name.lastIndexOf('.');
    final base = path != null && dot > 0 ? name.substring(0, dot) : name;
    return base.isEmpty ? 'документ' : base;
  }

  // Loading

  void _open(String path) {
    try {
      final file = File(path);
      _modified = file.lastModifiedSync();
      final text = decode(file.readAsBytesSync());
      this.path = path;
      _replaceText(text, saved: true);
      preferences.history.record(path);
      _watchFile();
      _publishDocument();
    } on Object catch (error) {
      this.path = path;
      _publishDocument();
      showError('не удалось открыть файл', _describe(error), onDismiss: bridge.close);
    }
  }

  /// UTF-8 first (a byte order mark is dropped), then UTF-16 with a mark, then Windows-1251 for old Russian files and
  /// Latin-1 for the rest.
  static String decode(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Not UTF-8.
    }
    if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      final little = bytes[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    final cyrillic = bytes.where((b) => b >= 0xC0).length;
    final high = bytes.where((b) => b >= 0x80).length;
    // Russian text in Windows-1251 is mostly letters from 0xC0 up; one accented letter is Latin-1.
    if (cyrillic >= 2 && cyrillic * 10 >= high * 6) return String.fromCharCodes(bytes.map(_cp1251));
    return latin1.decode(bytes);
  }

  static const _cp1251High = 'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї';
  static int _cp1251(int byte) {
    if (byte < 0x80) return byte;
    if (byte >= 0xC0) return 0x410 + byte - 0xC0;
    return _cp1251High.codeUnitAt(byte - 0x80);
  }

  void _replaceText(String text, {required bool saved}) {
    _text = text;
    if (saved) _saved = text;
    revision++;
    _renderNow();
    notifyListeners();
  }

  void _watchFile() {
    _watch?.cancel();
    final current = path;
    if (current == null) return;
    try {
      _watch = File(current).parent.watch(events: FileSystemEvent.modify | FileSystemEvent.create | FileSystemEvent.move).listen((event) {
        if (event.path == current || (event is FileSystemMoveEvent && event.destination == current)) _externalChange();
      });
    } on Object {
      _watch = null;
    }
  }

  /// A file changed by another app reloads by itself while there are no unsaved edits here.
  void _externalChange() {
    final current = path;
    if (current == null || edited) return;
    try {
      final file = File(current);
      final modified = file.lastModifiedSync();
      final known = _modified;
      if (known != null && !modified.isAfter(known)) return;
      _modified = modified;
      _replaceText(decode(file.readAsBytesSync()), saved: true);
      _publishDocument();
    } on Object {
      // The file is being written or went away; the next event or a save decides.
    }
  }

  // Editing and rendering

  void editorChanged(String text) {
    if (text == _text) return;
    final wasEdited = edited;
    _text = text;
    if (wasEdited != edited) {
      _publishDocument();
      notifyListeners();
    }
    _scheduleRender();
  }

  void _renderNow() {
    _renderTimer?.cancel();
    rendered = MarkdownRenderer.render(_text);
    stats = TextStats(MarkdownRenderer.plainText(_text));
  }

  /// Re-renders shortly after typing pauses; a newer edit wins over an older one.
  void _scheduleRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(const Duration(milliseconds: 90), () {
      _renderNow();
      notifyListeners();
    });
  }

  void setMode(ViewMode value) {
    if (value == mode) return;
    mode = value;
    _publishState();
    notifyListeners();
  }

  void toggleSidebar() {
    if (narrow) {
      narrowSidebar = !narrowSidebar;
      notifyListeners();
    } else {
      preferences.sidebar = !preferences.sidebar;
    }
    _publishState();
  }

  void setNarrow(bool value) {
    if (value == narrow) return;
    narrow = value;
    if (!value) narrowSidebar = false;
    _publishState();
    notifyListeners();
  }

  void setActiveAnchor(String? anchor) {
    if (anchor == activeAnchor) return;
    activeAnchor = anchor;
    notifyListeners();
  }

  void revealHeading(Heading heading) {
    setActiveAnchor(heading.anchor);
    _reveal.add(heading);
  }

  void setSettingsShown(bool value) {
    if (value && dialog != null) return;
    settingsShown = value;
    if (value) exportMenu = false;
    _publishState();
    notifyListeners();
  }

  void setExportMenu(bool value) {
    if (exportMenu == value) return;
    exportMenu = value;
    notifyListeners();
  }

  void setZoom(double value) => preferences.zoom = value.clamp(0.6, 2.5);
  void zoomIn() => setZoom(((_zoom * 10 + 1).round()) / 10);
  void zoomOut() => setZoom(((_zoom * 10 - 1).round()) / 10);

  void _preferencesChanged() {
    _zoom = preferences.zoom;
    _publishState();
    notifyListeners();
  }

  // Dialogs

  void showError(String title, String detail, {VoidCallback? onDismiss}) {
    if (dialog != null) {
      _pendingErrors.add((title, detail));
      return;
    }
    exportMenu = false;
    void dismiss() {
      dismissDialog();
      onDismiss?.call();
    }

    _setDialog(DialogRequest(
      title: title,
      detail: detail,
      actions: [DialogAction(title: 'понятно', kind: ButtonKind.primary, isDefault: true, run: dismiss)],
      cancel: dismiss,
    ));
  }

  void dismissDialog() {
    _setDialog(null);
    if (_pendingErrors.isNotEmpty) {
      final (title, detail) = _pendingErrors.removeAt(0);
      showError(title, detail);
    }
  }

  void _setDialog(DialogRequest? request) {
    dialog = request;
    _publishState();
    notifyListeners();
  }

  static String _describe(Object error) => switch (error) {
        FileSystemException(:final message, :final osError) => osError?.message.isNotEmpty == true ? osError!.message : message,
        FormatException(:final message) => message,
        _ => '$error',
      };

  // Saving

  Future<bool> save() async {
    final current = path;
    if (current == null) return saveAs();
    try {
      await _writeAtomically(current, utf8.encode(_text));
      _saved = _text;
      _modified = File(current).lastModifiedSync();
      preferences.history.record(current);
      _publishDocument();
      notifyListeners();
      return true;
    } on Object catch (error) {
      showError('не удалось сохранить документ', _describe(error));
      return false;
    }
  }

  Future<bool> saveAs() async {
    final name = path == null ? '$displayName.md' : displayName;
    final chosen = await bridge.savePanel(title: '', name: name, directory: baseDirectory, extension: 'md');
    if (chosen == null) return false;
    try {
      await _writeAtomically(chosen, utf8.encode(_text));
      path = chosen;
      _saved = _text;
      _modified = File(chosen).lastModifiedSync();
      preferences.history.record(chosen);
      _watchFile();
      _publishDocument();
      _publishState();
      notifyListeners();
      return true;
    } on Object catch (error) {
      showError('не удалось сохранить документ', _describe(error));
      return false;
    }
  }

  static Future<void> _writeAtomically(String target, List<int> bytes) async {
    final file = File(target);
    final temporary = File('${file.parent.path}${Platform.pathSeparator}.${file.uri.pathSegments.last}.rotide-${DateTime.now().microsecondsSinceEpoch}');
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(target);
    } on FileSystemException {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  void revert() {
    final current = path;
    if (current == null || dialog != null) return;
    void cancel() => dismissDialog();
    _setDialog(DialogRequest(
      title: 'вернуть сохранённую версию?',
      detail: 'несохранённые изменения в документе «$displayName» будут потеряны',
      actions: [
        DialogAction(
          title: 'вернуть версию',
          kind: ButtonKind.destructive,
          run: () {
            dismissDialog();
            try {
              final file = File(current);
              _modified = file.lastModifiedSync();
              _replaceText(decode(file.readAsBytesSync()), saved: true);
              _publishDocument();
            } on Object catch (error) {
              showError('не удалось вернуть сохранённую версию', _describe(error));
            }
          },
        ),
        DialogAction(title: 'отмена', kind: ButtonKind.ghost, isDefault: true, isCancel: true, run: cancel),
      ],
      cancel: cancel,
    ));
  }

  /// The question before closing an edited document: save, don't save, cancel.
  Future<bool> shouldClose() {
    if (!edited && !_closeAsked) return Future.value(true);
    final reply = Completer<bool>();
    if (dialog != null && _closeReplies.isEmpty) return Future.value(false);
    _closeReplies.add(reply);
    if (dialog != null || _closeAsked) return reply.future;
    _closeAsked = true;
    exportMenu = false;
    void cancel() => _finishClose(false);
    _setDialog(DialogRequest(
      title: 'сохранить изменения?',
      detail: 'изменения в документе «$displayName» будут потеряны, если их не сохранить',
      actions: [
        DialogAction(
          title: 'сохранить',
          kind: ButtonKind.primary,
          isDefault: true,
          run: () async {
            _setDialog(null);
            final saved = await save();
            _finishClose(saved && !edited);
          },
        ),
        DialogAction(title: 'не сохранять', kind: ButtonKind.destructive, run: () => _finishClose(true)),
        DialogAction(title: 'отмена', kind: ButtonKind.ghost, isCancel: true, run: cancel),
      ],
      cancel: cancel,
    ));
    return reply.future;
  }

  void _finishClose(bool answer) {
    _closeAsked = false;
    if (dialog != null) dismissDialog();
    final replies = List.of(_closeReplies);
    _closeReplies.clear();
    for (final reply in replies) {
      reply.complete(answer);
    }
  }

  // Export and printing

  Future<void> export(ExportFormat format) async {
    exportMenu = false;
    notifyListeners();
    final chosen = await bridge.savePanel(
      title: 'экспорт: ${format.title}',
      prompt: 'экспортировать',
      name: '$exportBaseName.${format.extension}',
      directory: baseDirectory,
      extension: format.extension,
    );
    if (chosen == null) return;
    exporting = format;
    _publishState();
    notifyListeners();
    String? error;
    try {
      error = await _write(format, chosen);
    } on Object catch (caught) {
      error = _describe(caught);
    }
    exporting = null;
    _publishState();
    notifyListeners();
    if (error != null) showError('не удалось экспортировать: ${format.title}', error);
  }

  Future<String?> _write(ExportFormat format, String target) async {
    switch (format) {
      case ExportFormat.html:
        final body = PageBuilder.inlineLocalMedia(MarkdownRenderer.render(_text).html, baseDirectory);
        await _writeAtomically(target, utf8.encode(PageBuilder.page(title: exportBaseName, body: body, css: assets.css)));
      case ExportFormat.text:
        await _writeAtomically(target, utf8.encode(MarkdownRenderer.plainText(_text)));
      case ExportFormat.word:
        await _writeAtomically(target, DocxWriter.document(markdown: _text, title: exportBaseName, baseDirectory: baseDirectory));
      case ExportFormat.rtf:
        await _writeAtomically(target, latin1.encode(RtfWriter.document(markdown: _text, title: exportBaseName)));
      case ExportFormat.pdf:
        return bridge.pdf(html: printablePage(), base: baseDirectory, title: exportBaseName, path: target);
    }
    return null;
  }

  /// The page in the light theme, so paper stays white.
  String printablePage() => PageBuilder.page(title: exportBaseName, body: pageBody(MarkdownRenderer.render(_text).html), css: assets.css, theme: PageTheme.light);

  static String pageBody(String html) => html.isEmpty ? '<p class="empty-document">пусто: оформленный текст появится здесь</p>' : html;

  Future<void> print() async {
    final error = await bridge.print(html: printablePage(), base: baseDirectory, title: exportBaseName);
    if (error != null) showError('не удалось напечатать', error);
  }

  // Host state

  void _publishDocument() => bridge.setDocument(path: path, title: displayName, edited: edited);

  void _publishState() => bridge.setState({
        'mode': mode.index,
        'sidebar': sidebarVisible,
        'exporting': exporting != null,
        'dialog': dialog != null,
        'canRevert': path != null,
      });

  @override
  void dispose() {
    _watch?.cancel();
    _renderTimer?.cancel();
    _reveal.close();
    preferences.removeListener(_preferencesChanged);
    super.dispose();
  }
}
