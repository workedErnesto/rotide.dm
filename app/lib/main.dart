import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import 'app/english.dart';
import 'app/preferences.dart';
import 'app/scope.dart';
import 'app/symbol_loader.dart';
import 'document/document_controller.dart';
import 'document/document_screen.dart';
import 'start/start_screen.dart';

/// Every window runs its own engine; the host passes the window kind and the document path as arguments.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = NativeBridge.instance;
  final launch = await bridge.launch(args);
  final preferences = Preferences(launch.preferences, bridge);
  final accessibility = AccessibilitySettings(launch.accessibility, bridge);
  final assets = PageAssets(
    css: await rootBundle.loadString('assets/preview/preview.css'),
    script: await rootBundle.loadString('assets/preview/preview.js'),
  );
  await loadSymbols(bridge);
  await calibrateTracking(bridge);
  DocumentController? document;
  if (launch.kind == WindowKind.document) {
    document = DocumentController(path: launch.path, preferences: preferences, bridge: bridge, assets: assets);
  }
  runApp(RotideApp(preferences: preferences, accessibility: accessibility, bridge: bridge, assets: assets, document: document));
}

final class RotideApp extends StatefulWidget {
  const RotideApp({
    super.key,
    required this.preferences,
    required this.accessibility,
    required this.bridge,
    required this.assets,
    this.document,
  });

  final Preferences preferences;
  final AccessibilitySettings accessibility;
  final NativeBridge bridge;
  final PageAssets assets;
  final DocumentController? document;

  @override
  State<RotideApp> createState() => _RotideAppState();
}

class _RotideAppState extends State<RotideApp> with WidgetsBindingObserver {
  int _revision = 0;
  bool? _frost;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.preferences.addListener(_changed);
    widget.accessibility.addListener(_changed);
    _syncFrost();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.bridge.ready());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.preferences.removeListener(_changed);
    widget.accessibility.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  void _changed() {
    setState(() => _revision++);
    _syncFrost();
  }

  void _syncFrost() {
    final accessibility = widget.accessibility.value;
    final frost = widget.preferences.frosted && !accessibility.reduceTransparency && !accessibility.increaseContrast;
    if (frost == _frost) return;
    _frost = frost;
    widget.bridge.setFrost(frost);
  }

  bool get _dark => switch (widget.preferences.appearance) {
        'light' => false,
        'dark' => true,
        _ => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      };

  bool? _publishedDark;

  @override
  Widget build(BuildContext context) {
    final dark = _dark;
    if (dark != _publishedDark) {
      _publishedDark = dark;
      widget.bridge.setDark(dark);
    }
    final palette = RotidePalette(dark: dark, contrast: widget.accessibility.value.increaseContrast);
    return AppScope(
      preferences: widget.preferences,
      accessibility: widget.accessibility,
      bridge: widget.bridge,
      assets: widget.assets,
      revision: _revision,
      child: RotideTheme(
        dark: dark,
        accessibility: widget.accessibility.value,
        capitalized: widget.preferences.capitalized,
        language: widget.preferences.language,
        translate: English.translate,
        child: WidgetsApp(
          title: 'rotide.dm',
          color: palette.ink,
          debugShowCheckedModeBanner: false,
          textStyle: RotideFonts.system(13, color: palette.ink),
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            transitionDuration: Duration.zero,
            pageBuilder: (context, _, _) => builder(context),
          ),
          home: DefaultSelectionStyle(
            selectionColor: palette.textSelection,
            cursorColor: palette.ink,
            child: widget.document == null ? const StartScreen() : DocumentScreen(controller: widget.document!),
          ),
        ),
      ),
    );
  }
}
