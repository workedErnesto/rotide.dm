import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A link the page asked to follow.
final class PreviewNavigation {
  const PreviewNavigation({required this.url, required this.path, this.fragment});
  final String url;
  final String path;
  final String? fragment;
}

/// Talks to one native web view: WKWebView on macOS, WebView2 on Windows. Page logic stays in Dart.
final class PreviewController {
  MethodChannel? _channel;
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  final _navigations = StreamController<PreviewNavigation>.broadcast();
  final _pending = <(String, Map<String, Object?>)>[];

  /// Windows: a picture of the page shown while the web view window is hidden under a Flutter overlay.
  final snapshot = ValueNotifier<Uint8List?>(null);

  Stream<Map<String, Object?>> get messages => _messages.stream;
  Stream<PreviewNavigation> get navigations => _navigations.stream;
  bool get attached => _channel != null;

  void _attach(int id) {
    final channel = MethodChannel('rotide/preview/$id');
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'message':
          // WKWebView sends a dictionary, WebView2 the message as JSON text.
          final arguments = call.arguments;
          final body = arguments is String ? jsonDecode(arguments) : arguments;
          if (body is Map) _messages.add(body.cast<String, Object?>());
        case 'navigate':
          final map = (call.arguments as Map).cast<String, Object?>();
          _navigations.add(PreviewNavigation(url: map['url']! as String, path: map['path'] as String? ?? '', fragment: map['fragment'] as String?));
        case 'snapshot':
          snapshot.value = call.arguments as Uint8List?;
      }
      return null;
    });
    _channel = channel;
    for (final (method, args) in _pending) {
      channel.invokeMethod<void>(method, args);
    }
    _pending.clear();
  }

  void _detach() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  void _send(String method, Map<String, Object?> args) {
    final channel = _channel;
    if (channel == null) {
      _pending.add((method, args));
    } else {
      channel.invokeMethod<void>(method, args);
    }
  }

  void load(String html, String? base) => _send('load', {'html': html, 'base': base});
  void eval(String script) => _send('eval', {'script': script});
  void zoom(double value) => _send('zoom', {'value': value});
  void blocked(bool value) => _send('blocked', {'value': value});
  void background(Color color) => _send('background', {'color': color.toARGB32() & 0xFFFFFF});
  void focus() => _send('focus', const {});

  void dispose() {
    _detach();
    _messages.close();
    _navigations.close();
    snapshot.dispose();
  }
}

/// Places the native web view in the widget tree. On macOS it is a platform view clipped to the card's corners; on
/// Windows the host keeps a WebView2 window over the rectangle this widget reports, and a snapshot of the page stands
/// in for it while a Flutter overlay covers the card.
final class PreviewHost extends StatefulWidget {
  const PreviewHost({super.key, required this.controller, required this.script, this.radius = 10});
  final PreviewController controller;
  final String script;
  final double radius;

  @override
  State<PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<PreviewHost> {
  static const _native = MethodChannel('rotide/native');
  int? _windowsId;
  Rect? _pendingFrame;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) _createWindows();
  }

  Future<void> _createWindows() async {
    final id = await _native.invokeMethod<int>('previewCreate', {'script': widget.script, 'radius': widget.radius});
    if (!mounted || id == null) return;
    _windowsId = id;
    widget.controller._attach(id);
    final frame = _pendingFrame;
    if (frame != null) _report(frame);
  }

  void _report(Rect rect) {
    final id = _windowsId;
    if (id == null) {
      _pendingFrame = rect;
      return;
    }
    _native.invokeMethod<void>('previewFrame', {
      'id': id,
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'scale': _scale,
    });
  }

  @override
  void dispose() {
    final id = _windowsId;
    if (id != null) _native.invokeMethod<void>('previewDestroy', {'id': id});
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        viewType: 'rotide/preview',
        creationParams: {'script': widget.script, 'radius': widget.radius},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: widget.controller._attach,
      );
    }
    _scale = MediaQuery.devicePixelRatioOf(context);
    return _FrameReporter(
      onFrame: _report,
      child: ValueListenableBuilder(
        valueListenable: widget.controller.snapshot,
        builder: (context, bytes, _) => bytes == null
            ? const SizedBox.expand()
            : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Reports its rectangle in window coordinates whenever it is painted somewhere new.
final class _FrameReporter extends SingleChildRenderObjectWidget {
  const _FrameReporter({required this.onFrame, required super.child});
  final ValueChanged<Rect> onFrame;

  @override
  RenderObject createRenderObject(BuildContext context) => _FrameReporterBox(onFrame);

  @override
  void updateRenderObject(BuildContext context, _FrameReporterBox renderObject) => renderObject.onFrame = onFrame;
}

final class _FrameReporterBox extends RenderProxyBox {
  _FrameReporterBox(this.onFrame);
  ValueChanged<Rect> onFrame;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rect = localToGlobal(Offset.zero) & size;
    if (rect == _last) return;
    _last = rect;
    final callback = onFrame;
    scheduleMicrotask(() => callback(rect));
  }
}
