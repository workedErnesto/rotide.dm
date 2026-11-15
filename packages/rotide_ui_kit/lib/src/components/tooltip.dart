import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'surfaces.dart';
import 'label_text.dart';

/// A help tag that appears after the pointer rests on a control, like the system tooltip SwiftUI's `.help()` shows:
/// small, below the pointer, gone on the first click or when the pointer leaves.
final class Hint extends StatefulWidget {
  const Hint({super.key, required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  State<Hint> createState() => _HintState();
}

class _HintState extends State<Hint> {
  final _portal = OverlayPortalController();
  Timer? _timer;
  Offset _pointer = Offset.zero;

  void _enter(PointerEnterEvent event) {
    _pointer = event.position;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted && widget.message.isNotEmpty) _portal.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) return widget.child;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final palette = RotideTheme.paletteOf(context);
        final size = MediaQuery.sizeOf(context);
        return Positioned(
          left: (_pointer.dx - 8).clamp(4, size.width - 240),
          top: _pointer.dy + 22 > size.height - 30 ? _pointer.dy - 30 : _pointer.dy + 22,
          child: IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 236),
              child: DecoratedBox(
                decoration: continuousDecoration(
                  radius: 5,
                  color: palette.raised,
                  border: palette.hairlineStrong,
                  borderWidth: 0.5,
                  shadows: [swiftShadow(palette.menuShadow, 4, y: 2)],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(styledLabel(widget.message, capitalized: RotideTheme.capitalizedOf(context)), style: RotideFonts.system(11, color: palette.ink)),
                ),
              ),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: _enter,
        onHover: (event) {
          if (!_portal.isShowing) _pointer = event.position;
        },
        onExit: (_) => _hide(),
        child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
      ),
    );
  }
}
