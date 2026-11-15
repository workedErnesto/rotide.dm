import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/scope.dart';
import '../settings/settings_overlay.dart';
import '../shell/caption_buttons.dart';
import '../shell/shell.dart';
import '../shell/text_utils.dart';

/// Shown when rotide.dm runs without a document: the wordmark, new and open, recent files, and a drop target.
final class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _settings = false;
  DialogRequest? _dialog;
  late final StreamSubscription<MenuCommand> _menu;
  static const _wordmark = 'rotide.dm';

  @override
  void initState() {
    super.initState();
    _menu = NativeBridge.instance.menu.listen((command) {
      if (command.name == 'settings' && _dialog == null) setState(() => _settings = true);
    });
  }

  @override
  void dispose() {
    _menu.cancel();
    super.dispose();
  }

  void _open(String path) {
    if (!File(path).existsSync()) {
      void dismiss() => setState(() => _dialog = null);
      setState(() => _dialog = DialogRequest(
            title: 'не удалось открыть файл',
            detail: 'файл «${path.split(Platform.pathSeparator).last}» не найден',
            actions: [DialogAction(title: 'понятно', kind: ButtonKind.primary, isDefault: true, run: dismiss)],
            cancel: dismiss,
          ));
      return;
    }
    NativeBridge.instance.openDocument(path);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = RotideTheme.paletteOf(context);
    final recents = scope.preferences.history.paths;
    return Stack(
      children: [
        const Positioned.fill(child: ShellBackground()),
        const Positioned.fill(child: WindowDragArea()),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Appear(
              builder: (context, shown) => Column(
                children: [
                  const SizedBox(height: 56),
                  const Spacer(),
                  AssemblingText(text: _wordmark, style: RotideFonts.system(40, weight: FontWeight.w300, color: palette.ink), shown: shown),
                  const SizedBox(height: Space.micro),
                  Entrance(
                    shown: shown,
                    delay: 0.18,
                    child: LabelText('читалка и редактор Markdown', style: RotideFonts.system(13, color: palette.text2)),
                  ),
                  const SizedBox(height: Space.section),
                  Entrance(
                    shown: shown,
                    delay: 0.18 + Entrance.step(1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MButton(label: 'новый файл', kind: ButtonKind.primary, onPressed: NativeBridge.instance.newDocument),
                        const SizedBox(width: Space.small),
                        MButton(label: 'открыть…', onPressed: NativeBridge.instance.openPanel),
                      ],
                    ),
                  ),
                  if (recents.isNotEmpty) ...[
                    const SizedBox(height: Space.large),
                    Entrance(shown: shown, delay: 0.18 + Entrance.step(2), child: _RecentList(paths: recents.take(3).toList(), onOpen: _open)),
                  ],
                  const Spacer(),
                  const SizedBox(height: Space.section),
                  Entrance(
                    shown: shown,
                    delay: 0.18 + Entrance.step(3),
                    child: LabelText('или перетащите сюда файл .md', style: RotideFonts.system(11.5, color: palette.text3)),
                  ),
                  const SizedBox(height: Space.section),
                ],
              ),
            ),
          ),
        ),
        const Positioned(top: 0, right: 0, child: CaptionButtons(resizable: false)),
        Positioned(
          top: Space.small,
          right: Space.small + CaptionButtons.reservedWidth(resizable: false),
          child: IconButton(symbol: 'gearshape', label: 'настройки', onPressed: () => setState(() => _settings = true)),
        ),
        Positioned.fill(child: IgnorePointer(child: _DropTarget(active: NativeBridge.instance.dropping))),
        Positioned.fill(
          child: FadePresence(
            visible: _settings && _dialog == null,
            child: SettingsOverlay(onDismiss: () => setState(() => _settings = false)),
          ),
        ),
        Positioned.fill(
          child: FadePresence(
            visible: _dialog != null,
            child: _dialog == null ? null : DialogLayer(key: ValueKey(_dialog!.id), request: _dialog!),
          ),
        ),
      ],
    );
  }
}

/// The dashed outline that fades in while a file is dragged over the window.
final class _DropTarget extends StatelessWidget {
  const _DropTarget({required this.active});
  final ValueNotifier<bool> active;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final reduced = RotideTheme.reduceMotionOf(context);
    return ValueListenableBuilder(
      valueListenable: active,
      builder: (context, dropping, _) => AnimatedOpacity(
        opacity: dropping ? 1 : 0,
        duration: Duration(milliseconds: reduced ? 120 : 280),
        curve: Curves.easeInOut,
        child: Padding(
          padding: const EdgeInsets.all(Radii.gutter),
          child: CustomPaint(painter: _DashedRect(stroke: palette.focusRing, fill: palette.hover)),
        ),
      ),
    );
  }
}

final class _DashedRect extends CustomPainter {
  _DashedRect({required this.stroke, required this.fill});
  final Color stroke;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = (Offset.zero & size).deflate(0.75);
    final shape = RSuperellipse.fromRectAndRadius(inset, const Radius.circular(Radii.modal - 0.75));
    canvas.drawRSuperellipse(shape, Paint()..color = fill);
    final path = Path()..addRSuperellipse(shape);
    final paint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) => old.stroke != stroke || old.fill != fill;
}

final class _RecentList extends StatelessWidget {
  const _RecentList({required this.paths, required this.onOpen});
  final List<String> paths;
  final ValueChanged<String> onOpen;
  static const _tile = (520 - 2 * Space.small) / 3;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return SizedBox(
      width: paths.length * _tile + (paths.length - 1) * Space.small,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.micro),
            child: LabelText('недавние', style: RotideFonts.system(11, weight: FontWeight.w500, color: palette.text3)),
          ),
          const SizedBox(height: Space.small),
          Row(
            children: [
              for (var index = 0; index < paths.length; index++) ...[
                if (index > 0) const SizedBox(width: Space.small),
                SizedBox(width: _tile, child: _RecentTile(path: paths[index], onOpen: onOpen)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

final class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.path, required this.onOpen});
  final String path;
  final ValueChanged<String> onOpen;

  String get _folder {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    final folder = index <= 0 ? separator : path.substring(0, index);
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home != null && folder.startsWith(home) ? '~${folder.substring(home.length)}' : folder;
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final name = path.split(Platform.pathSeparator).last;
    return Hint(
      message: path,
      child: Interactive(
        onTap: () => onOpen(path),
        semanticLabel: name,
        builder: (context, hover, pressed) => PressScale(
          pressed: pressed,
          scale: 0.98,
          child: HoverColor(
            color: hover ? palette.secondaryHover : palette.track,
            builder: (context, fill) => Container(
              height: 82,
              padding: const EdgeInsets.all(Space.small),
              decoration: continuousDecoration(radius: Radii.row, color: fill),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Symbol('doc.text', size: 15, color: palette.text2),
                  const SizedBox(height: Space.small),
                  MiddleEllipsisText(name, style: RotideFonts.system(12.5, weight: FontWeight.w500, color: palette.ink)),
                  const SizedBox(height: 2),
                  HeadEllipsisText(_folder, style: RotideFonts.system(11, color: palette.text2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

