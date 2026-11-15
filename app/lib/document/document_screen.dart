import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/scope.dart';
import '../editor/markdown_editor.dart';
import '../preview/preview_pane.dart';
import '../settings/settings_overlay.dart';
import '../shell/caption_buttons.dart';
import '../shell/shell.dart';
import '../shell/text_utils.dart';
import 'document_controller.dart';
import 'export_menu.dart';
import 'outline.dart';

/// The document window: top bar across the window, the outline on the shell at the left, and one card (source or
/// page) inset 8 pt from the window edges.
final class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.controller});
  final DocumentController controller;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  final _editor = GlobalKey<MarkdownEditorState>();
  late final StreamSubscription<MenuCommand> _menu;

  DocumentController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _menu = NativeBridge.instance.menu.listen(_command);
  }

  @override
  void dispose() {
    _menu.cancel();
    super.dispose();
  }

  void _command(MenuCommand command) {
    final controller = _controller;
    if (command.name == 'settings') return _showSettings();
    if (controller.dialog != null) return;
    switch (command.name) {
      case 'save':
        controller.save();
      case 'saveAs':
        controller.saveAs();
      case 'revert':
        controller.revert();
      case 'export':
        controller.export(ExportFormat.values[command.tag]);
      case 'exportMenu':
        controller.setExportMenu(!controller.exportMenu);
      case 'print':
        controller.print();
      case 'mode':
        _setMode(ViewMode.values[command.tag]);
      case 'sidebar':
        controller.toggleSidebar();
      case 'zoomIn':
        controller.zoomIn();
      case 'zoomOut':
        controller.zoomOut();
      case 'zoomReset':
        controller.setZoom(1);
      case 'find' || 'replace' || 'findNext' || 'findPrevious' || 'findSelection':
        if (controller.mode == ViewMode.edit) _editor.currentState?.find(command.name);
      case 'new':
        NativeBridge.instance.newDocument();
      case 'open':
        NativeBridge.instance.openPanel();
      case 'close':
        NativeBridge.instance.performClose();
    }
  }

  void _setMode(ViewMode mode) {
    if (mode == ViewMode.read) FocusManager.instance.primaryFocus?.unfocus();
    _controller.setMode(mode);
    if (mode == ViewMode.edit) WidgetsBinding.instance.addPostFrameCallback((_) => _editor.currentState?.focus());
  }

  void _showSettings() {
    if (_controller.dialog != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.setSettingsShown(true);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts(),
      child: Actions(
        actions: {_CommandIntent: CallbackAction<_CommandIntent>(onInvoke: (intent) => _command(intent.command))},
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final controller = _controller;
              final blocked = controller.exportMenu || controller.dialog != null || controller.settingsShown;
              return LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < Chrome.narrowWindow;
                if (narrow != controller.narrow) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => controller.setNarrow(narrow));
                }
                return Stack(
                  children: [
                    const Positioned.fill(child: ShellBackground()),
                    Positioned.fill(
                      child: Column(
                        children: [
                          _TopBar(controller: controller, onSettings: _showSettings, onMode: _setMode),
                          Expanded(child: _Body(controller: controller, editorKey: _editor, blocked: blocked)),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: ExportMenuLayer(controller: controller, visible: controller.exportMenu && controller.dialog == null && !controller.settingsShown),
                    ),
                    Positioned.fill(
                      child: FadePresence(
                        visible: controller.settingsShown && controller.dialog == null,
                        child: SettingsOverlay(onDismiss: () => controller.setSettingsShown(false)),
                      ),
                    ),
                    Positioned.fill(
                      child: FadePresence(
                        visible: controller.dialog != null,
                        child: controller.dialog == null ? null : DialogLayer(key: ValueKey(controller.dialog!.id), request: controller.dialog!),
                      ),
                    ),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }

  /// On Windows there is no menu bar: the same commands come from the keyboard.
  Map<ShortcutActivator, Intent> _shortcuts() {
    if (NativeBridge.instance.isMac) return const {};
    _CommandIntent c(String name, [int tag = 0]) => _CommandIntent(MenuCommand(name, tag));
    return {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): c('save'),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): c('saveAs'),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): c('export'),
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): c('print'),
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): c('mode', 0),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): c('mode', 1),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true): c('sidebar'),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): c('zoomIn'),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): c('zoomOut'),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): c('zoomReset'),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): c('find'),
      const SingleActivator(LogicalKeyboardKey.keyH, control: true): c('replace'),
      const SingleActivator(LogicalKeyboardKey.f3): c('findNext'),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): c('findPrevious'),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): c('settings'),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): c('new'),
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): c('open'),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): c('close'),
    };
  }
}

final class _CommandIntent extends Intent {
  const _CommandIntent(this.command);
  final MenuCommand command;
}

/// The outline and the card below the top bar.
final class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.editorKey, required this.blocked});
  final DocumentController controller;
  final GlobalKey<MarkdownEditorState> editorKey;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final width = scope.preferences.sidebarWidth;
    return SpringValue(
      value: controller.sidebarVisible ? 1 : 0,
      spring: MotionTokens.panel,
      builder: (context, shown, _) {
        final progress = shown.clamp(0.0, 1.2);
        final visible = shown > 0.001;
        return Stack(
          children: [
            if (visible)
              Positioned(
                left: -(1 - shown) * width,
                top: 0,
                bottom: 0,
                width: width,
                child: Opacity(opacity: shown.clamp(0.0, 1.0), child: OutlineSidebar(controller: controller)),
              ),
            Positioned(
              left: width * progress + Radii.gutter * (1 - shown).clamp(0.0, 1.0),
              top: 0,
              right: Radii.gutter,
              bottom: Radii.gutter,
              child: Appear(
                builder: (context, appeared) => Entrance(
                  shown: appeared,
                  scale: MotionTokens.entranceCardScale,
                  child: CardSurface(child: _Cards(controller: controller, editorKey: editorKey, blocked: blocked)),
                ),
              ),
            ),
            if (visible && shown > 0.5)
              Positioned(left: width * progress - 4, top: 0, bottom: Radii.gutter, width: 8, child: _SidebarResizer(controller: controller)),
          ],
        );
      },
    );
  }
}

/// Reading and editing share one card; the other one fades out on the panel spring.
final class _Cards extends StatelessWidget {
  const _Cards({required this.controller, required this.editorKey, required this.blocked});
  final DocumentController controller;
  final GlobalKey<MarkdownEditorState> editorKey;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final editing = controller.mode == ViewMode.edit;
    return Stack(
      fit: StackFit.expand,
      children: [
        SpringValue(
          value: editing ? 1 : 0,
          spring: MotionTokens.panel,
          builder: (context, opacity, child) => Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
          child: IgnorePointer(
            ignoring: !editing,
            child: ExcludeSemantics(
              excluding: !editing,
              child: MarkdownEditor(key: editorKey, controller: controller, blocked: blocked || !editing),
            ),
          ),
        ),
        SpringValue(
          value: editing ? 0 : 1,
          spring: MotionTokens.panel,
          builder: (context, opacity, child) => Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
          child: IgnorePointer(
            ignoring: editing,
            child: ExcludeSemantics(excluding: editing, child: PreviewPane(controller: controller, blocked: blocked || editing)),
          ),
        ),
      ],
    );
  }
}

/// The card edge next to the outline: dragging it changes the outline width, which is remembered.
final class _SidebarResizer extends StatefulWidget {
  const _SidebarResizer({required this.controller});
  final DocumentController controller;

  @override
  State<_SidebarResizer> createState() => _SidebarResizerState();
}

class _SidebarResizerState extends State<_SidebarResizer> {
  double? _start;

  @override
  Widget build(BuildContext context) {
    final preferences = AppScope.of(context).preferences;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _start = preferences.sidebarWidth,
        onHorizontalDragUpdate: (details) {
          final start = _start ?? preferences.sidebarWidth;
          _start = start + details.delta.dx;
          preferences.sidebarWidth = (_start!).clamp(Chrome.sidebarMin, Chrome.sidebarMax);
        },
        onHorizontalDragEnd: (_) => _start = null,
      ),
    );
  }
}

final class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.onSettings, required this.onMode});
  final DocumentController controller;
  final VoidCallback onSettings;
  final ValueChanged<ViewMode> onMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Chrome.bar,
      child: Stack(
        children: [
          const Positioned.fill(child: WindowDragArea()),
          const Positioned(top: 0, right: 0, child: CaptionButtons()),
          Padding(
            padding: EdgeInsets.only(left: Radii.gutter, right: Radii.gutter + CaptionButtons.reservedWidth()),
            child: ValueListenableBuilder(
              valueListenable: NativeBridge.instance.fullScreen,
              builder: (context, fullScreen, _) => CustomMultiChildLayout(
                delegate: _TopBarLayout(),
                children: [
                  LayoutId(
                    id: _Slot.leading,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: fullScreen || !NativeBridge.instance.isMac ? 0 : Chrome.lightsInset - Space.small),
                        const SizedBox(width: Space.micro),
                        IconButton(symbol: 'sidebar.left', label: 'содержание (${shortcutHint('⌃⌘S')})', onPressed: controller.toggleSidebar),
                      ],
                    ),
                  ),
                  LayoutId(
                    id: _Slot.trailing,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Segmented<ViewMode>(
                          selection: controller.mode,
                          options: [for (final mode in ViewMode.values) (mode, mode.title)],
                          symbols: [for (final mode in ViewMode.values) mode.symbol],
                          compact: true,
                          label: 'режим',
                          onChanged: onMode,
                        ),
                        const SizedBox(width: Space.small),
                        _ExportButton(controller: controller),
                        const SizedBox(width: Space.small),
                        IconButton(symbol: 'gearshape', label: 'настройки', onPressed: onSettings),
                      ],
                    ),
                  ),
                  LayoutId(id: _Slot.title, child: _DocumentTitle(controller: controller)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Slot { leading, trailing, title }

/// Title centred in the window; when there is not enough room it takes the space between the two button groups.
final class _TopBarLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final leading = layoutChild(_Slot.leading, loose);
    final trailing = layoutChild(_Slot.trailing, loose);
    positionChild(_Slot.leading, Offset(0, (size.height - leading.height) / 2));
    positionChild(_Slot.trailing, Offset(size.width - trailing.width, (size.height - trailing.height) / 2));
    // The bar is inset by the gutter on both sides; the window is that much wider.
    final window = size.width + 2 * Radii.gutter;
    final side = (leading.width > trailing.width ? leading.width : trailing.width) + Space.normal;
    final centered = window - 2 * side >= 160;
    final maxWidth = centered ? window - 2 * side : size.width - leading.width - trailing.width - 2 * Space.normal;
    final title = layoutChild(_Slot.title, BoxConstraints(maxWidth: maxWidth < 0 ? 0 : maxWidth, maxHeight: size.height));
    final x = centered ? (size.width - title.width) / 2 : leading.width + Space.normal + ((maxWidth < 0 ? 0 : maxWidth) - title.width) / 2;
    positionChild(_Slot.title, Offset(x, (size.height - title.height) / 2));
  }

  @override
  bool shouldRelayout(_TopBarLayout oldDelegate) => false;
}

final class _DocumentTitle extends StatelessWidget {
  const _DocumentTitle({required this.controller});
  final DocumentController controller;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Hint(
      message: controller.path ?? 'файл ещё не сохранён',
      child: IgnorePointer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: MiddleEllipsisText(controller.displayName, style: RotideFonts.system(13, weight: FontWeight.w500, color: palette.ink))),
            Presence(
              visible: controller.edited,
              curve: (Curves.easeOut, MotionTokens.hover),
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: LabelText('изменён', style: RotideFonts.system(12, color: palette.text3)),
              ),
              builder: (context, progress, child) => Opacity(opacity: progress, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.controller});
  final DocumentController controller;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return AnimatedSwitcher(
      duration: MotionTokens.hover,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: controller.exporting != null
          ? Semantics(
              key: const ValueKey('progress'),
              label: RotideTheme.textOf(context, 'идёт экспорт'),
              child: SizedBox.square(dimension: 28, child: CupertinoActivityIndicator(radius: 7, color: palette.text2)),
            )
          : IconButton(
              key: const ValueKey('button'),
              symbol: 'square.and.arrow.up',
              label: 'экспорт и сохранение',
              selected: controller.exportMenu,
              symbolOffsetY: -0.5,
              onPressed: () => controller.setExportMenu(!controller.exportMenu),
            ),
    );
  }
}
