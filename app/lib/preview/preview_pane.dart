import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/scope.dart';
import '../document/document_controller.dart';

/// The rendered page. Loaded once per folder; later edits replace the article body from the isolated script world,
/// so the scroll position survives typing.
final class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key, required this.controller, required this.blocked});
  final DocumentController controller;
  final bool blocked;

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  final _page = PreviewController();
  late final StreamSubscription<Map<String, Object?>> _messages;
  late final StreamSubscription<PreviewNavigation> _navigations;
  late final StreamSubscription<Heading> _reveal;
  bool _ready = false;
  String? _shownBody;
  RotideLanguage? _shownLanguage;
  (String?,)? _base;
  double? _zoom;
  bool? _blocked;
  Color? _background;
  String? _pendingAnchor;

  DocumentController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _messages = _page.messages.listen(_message);
    _navigations = _page.navigations.listen(_follow);
    _reveal = _controller.reveal.listen((heading) => _scroll(heading.anchor, animated: true));
  }

  @override
  void dispose() {
    _messages.cancel();
    _navigations.cancel();
    _reveal.cancel();
    _page.dispose();
    super.dispose();
  }

  void _sync(PageAssets assets, Color canvas) {
    if (_zoom != _controller.zoom) {
      _zoom = _controller.zoom;
      _page.zoom(_controller.zoom);
    }
    if (_blocked != widget.blocked) {
      _blocked = widget.blocked;
      _page.blocked(widget.blocked);
    }
    if (_background != canvas) {
      _background = canvas;
      _page.background(canvas);
    }
    final directory = _controller.baseDirectory;
    final body = _controller.pageBody(_controller.rendered.html);
    if (_base == null || _base!.$1 != directory) {
      _base = (directory,);
      _ready = false;
      _shownBody = body;
      _page.load(PageBuilder.page(title: _controller.displayName, body: body, css: assets.css), directory);
    } else if (_ready && _shownBody != body) {
      _shownBody = body;
      _page.eval('rotide.update(${jsonEncode(body)})');
    }
    _syncLanguage();
  }

  /// The page script owns the labels it adds (the copy button of a code block): it learns the language when the page
  /// is ready and whenever the setting changes.
  void _syncLanguage() {
    final language = _controller.preferences.language;
    if (!_ready || _shownLanguage == language) return;
    _shownLanguage = language;
    _page.eval('rotide.language(${jsonEncode(language.name)})');
  }

  void _scroll(String anchor, {required bool animated}) {
    if (_controller.mode != ViewMode.read) return;
    if (!_ready) {
      _pendingAnchor = anchor;
      return;
    }
    _page.eval('rotide.scrollTo(${jsonEncode(anchor)}, $animated)');
  }

  void _message(Map<String, Object?> body) {
    switch (body['type']) {
      case 'ready':
        _ready = true;
        _shownLanguage = null;
        if (_shownBody != _controller.pageBody(_controller.rendered.html)) setState(() {});
        _syncLanguage();
        final anchor = _pendingAnchor;
        if (anchor != null) {
          _pendingAnchor = null;
          _scroll(anchor, animated: false);
        }
      case 'heading':
        _controller.setActiveAnchor(body['id'] as String?);
      case 'copy':
        Clipboard.setData(ClipboardData(text: body['text'] as String? ?? ''));
    }
  }

  static const _markdownExtensions = {'md', 'markdown', 'mdown', 'mkd', 'mkdn', 'mdwn', 'mdtxt', 'mdtext'};

  /// The page itself is the only navigation. Links inside it scroll, open another Markdown file in rotide.dm, or go
  /// to the default browser or the file manager.
  void _follow(PreviewNavigation navigation) {
    final uri = Uri.tryParse(navigation.url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    final bridge = NativeBridge.instance;
    if (scheme == 'rotide-local' || scheme == 'file') {
      final path = Uri.decodeFull(navigation.path);
      final fragment = navigation.fragment;
      final directory = _controller.baseDirectory;
      final samePage = path.isEmpty || path == '/' || (directory != null && _same(path, directory));
      if (fragment != null && fragment.isNotEmpty && samePage) {
        _scroll(Uri.decodeComponent(fragment), animated: true);
        return;
      }
      final extension = path.contains('.') ? path.split('.').last.toLowerCase() : '';
      if (_markdownExtensions.contains(extension)) {
        if (File(path).existsSync()) {
          bridge.openDocument(path);
        } else {
          _controller.showError('не удалось открыть файл', 'файл «${path.split('/').last}» не найден');
        }
      } else if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        bridge.reveal(path);
      }
      return;
    }
    if (scheme == 'about' && navigation.fragment != null) {
      _scroll(navigation.fragment!, animated: true);
      return;
    }
    if (const {'http', 'https', 'mailto', 'tel'}.contains(scheme)) bridge.openUrl(navigation.url);
  }

  static bool _same(String a, String b) {
    String clean(String path) => path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    return clean(a) == clean(b);
  }

  @override
  Widget build(BuildContext context) {
    final assets = AppScope.of(context).assets;
    final canvas = RotideTheme.paletteOf(context).canvas;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(assets, canvas);
    });
    return PreviewHost(controller: _page, script: assets.script, radius: CardSurface.contentRadius);
  }
}
