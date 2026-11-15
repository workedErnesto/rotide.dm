import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/scope.dart';

/// Shell fill: the paper or stone tint over the blurred desktop (mica's default 55 % transparency), opaque when the
/// system asks for less transparency or more contrast. The blur itself is the native material under Flutter.
final class ShellBackground extends StatelessWidget {
  const ShellBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = RotideTheme.paletteOf(context);
    final opaque = !scope.frostActive;
    final alpha = opaque ? 1.0 : 0.92 - 0.72 * scope.preferences.transparency.clamp(0, 1);
    return ColoredBox(color: palette.shell.withValues(alpha: alpha));
  }
}

/// Empty chrome moves the window like a title bar; a double click zooms it, as the system setting says.
final class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => NativeBridge.instance.drag(),
        onDoubleTap: () => NativeBridge.instance.doubleClick(),
        child: child ?? const SizedBox.expand(),
      );
}

/// One action of a modal card.
final class DialogAction {
  const DialogAction({required this.title, required this.kind, required this.run, this.isDefault = false, this.isCancel = false});
  final String title;
  final ButtonKind kind;
  final VoidCallback run;
  final bool isDefault;
  final bool isCancel;
}

final class DialogRequest {
  DialogRequest({required this.title, required this.detail, required this.actions, required this.cancel}) : id = _next++;
  static int _next = 0;
  final int id;
  final String title;
  final String detail;
  final List<DialogAction> actions;
  final VoidCallback cancel;
}

/// An in-window modal card without the app icon: the scrim, the system confirm and cancel keys (Return, Esc).
final class DialogLayer extends StatefulWidget {
  const DialogLayer({super.key, required this.request});
  final DialogRequest request;

  @override
  State<DialogLayer> createState() => _DialogLayerState();
}

class _DialogLayerState extends State<DialogLayer> {
  final _focus = FocusNode(debugLabel: 'dialog');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final request = widget.request;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final cancel = request.actions.where((action) => action.isCancel).firstOrNull;
      (cancel?.run ?? request.cancel)();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      request.actions.where((action) => action.isDefault).firstOrNull?.run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final request = widget.request;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Stack(
        children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, child: ColoredBox(color: palette.scrim))),
          Center(
            child: Appear(
              builder: (context, shown) => SpringValue(
                value: shown ? 1 : 0,
                spring: MotionTokens.snappy,
                motion: false,
                builder: (context, progress, child) => Opacity(
                  opacity: progress.clamp(0.0, 1.0),
                  child: Transform.scale(scale: RotideTheme.reduceMotionOf(context) ? 1 : 0.97 + 0.03 * progress, child: child),
                ),
                child: LayoutBuilder(builder: (context, constraints) {
                  final width = (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 320.0);
                  return SizedBox(
                    width: width,
                    child: ModalSurface(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LabelText(request.title, textAlign: TextAlign.center, style: RotideFonts.system(14, weight: FontWeight.w600, color: palette.ink)),
                            if (request.detail.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 150),
                                  child: SingleChildScrollView(
                                    child: LabelText(
                                      request.detail,
                                      textAlign: TextAlign.center,
                                      style: RotideFonts.system(12, color: palette.text2, height: 1.35),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            for (var index = 0; index < request.actions.length; index++) ...[
                              if (index > 0) const SizedBox(height: Space.small),
                              MButton(label: request.actions[index].title, kind: request.actions[index].kind, fill: true, onPressed: request.actions[index].run),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades an overlay (settings, dialogs) in and out with the given animation, like SwiftUI's `.transition(.opacity)`.
final class FadePresence extends StatelessWidget {
  const FadePresence({super.key, required this.visible, required this.child, this.spring});
  final bool visible;
  final Widget? child;
  final Spring? spring;

  @override
  Widget build(BuildContext context) => Presence(
        visible: visible,
        spring: spring,
        curve: spring == null ? (Curves.easeOut, MotionTokens.hover) : null,
        exitSpring: spring ?? MotionTokens.snappy,
        child: child,
        builder: (context, progress, child) => IgnorePointer(ignoring: !visible, child: Opacity(opacity: progress.clamp(0.0, 1.0), child: child)),
      );
}
