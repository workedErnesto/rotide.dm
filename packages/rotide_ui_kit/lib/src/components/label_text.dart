import 'package:flutter/widgets.dart';

import '../motion/spring_motion.dart';
import '../theme.dart';
import '../tokens/motion.dart';

/// The same interface string in the style the user chose. rotide.dm writes its text from a lowercase letter; the
/// capital style raises the first letter of every authored string, as mica's regular style does. The product name
/// keeps its own spelling. A string of several sentences is raised at the start of each, so no sentence is left
/// lowercase between capitalised ones.
String styledLabel(String text, {required bool capitalized}) {
  if (!capitalized || text.isEmpty || text.startsWith('rotide.dm')) return text;
  return text.replaceFirstMapped(RegExp(r'^\p{Ll}', unicode: true), (match) => match[0]!.toUpperCase()).replaceAllMapped(
        RegExp(r'([.!?…]\s+)(\p{Ll})', unicode: true),
        (match) => '${match[1]}${match[2]!.toUpperCase()}',
      );
}

/// Authored interface text (buttons, titles, hints), never a document's own text, a file name or a path.
///
/// Changing the letter case in settings does not swap the strings at once: the old text gives way to the new one
/// on the snappy spring, the way a SwiftUI text changes inside an animation. A [literal] text keeps its own case
/// whatever the style, for the option that names the style itself.
final class LabelText extends StatefulWidget {
  const LabelText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.softWrap,
    this.overflow,
    this.textAlign,
    this.literal = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool literal;

  @override
  State<LabelText> createState() => _LabelTextState();
}

class _LabelTextState extends State<LabelText> with SingleTickerProviderStateMixin {
  late final SpringVector _fade = SpringVector(vsync: this, initial: const [1]);
  bool? _capitalized;
  String? _previous;

  String _shown(bool capitalized) => widget.literal ? widget.text : styledLabel(widget.text, capitalized: capitalized);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final capitalized = RotideTheme.capitalizedOf(context);
    final before = _capitalized;
    _capitalized = capitalized;
    if (before == null || before == capitalized || widget.literal) return;
    final old = _shown(before);
    if (old == _shown(capitalized)) return;
    _previous = old;
    _fade.values[0] = 0;
    _fade.animateTo(const [1], MotionTokens.snappy);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Alignment get _alignment => switch (widget.textAlign) {
        TextAlign.center => Alignment.topCenter,
        TextAlign.right || TextAlign.end => Alignment.topRight,
        _ => Alignment.topLeft,
      };

  Text _text(String value) => Text(
        value,
        style: widget.style,
        maxLines: widget.maxLines,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );

  @override
  Widget build(BuildContext context) {
    final current = _shown(RotideTheme.capitalizedOf(context));
    final previous = _previous;
    if (previous == null) return _text(current);
    return ListenableBuilder(
      listenable: _fade,
      builder: (context, _) {
        final progress = _fade.values[0].clamp(0.0, 1.0);
        if (progress >= 1) return _text(current);
        return Stack(
          alignment: _alignment,
          children: [
            Opacity(opacity: 1 - progress, child: _text(previous)),
            Opacity(opacity: progress, child: _text(current)),
          ],
        );
      },
    );
  }
}
