import 'package:flutter/widgets.dart';
import 'package:rotide_core/rotide_core.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/english.dart';
import '../shell/text_utils.dart';
import 'document_controller.dart';

/// Headings of the document on the shell, like mica's tab list. The current heading carries a raised plate that
/// travels between rows as the page scrolls; a click moves the page and the source to that heading.
final class OutlineSidebar extends StatefulWidget {
  const OutlineSidebar({super.key, required this.controller});
  final DocumentController controller;

  @override
  State<OutlineSidebar> createState() => _OutlineSidebarState();
}

class _OutlineSidebarState extends State<OutlineSidebar> {
  static const _rowHeight = 28.0;
  static const _rowGap = 1.0;
  final _scroll = ScrollController();
  String? _shownAnchor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current row in view, scrolling no further than needed.
  void _follow(int index) {
    if (!_scroll.hasClients) return;
    final top = index * (_rowHeight + _rowGap);
    final bottom = top + _rowHeight + Space.small;
    final position = _scroll.position;
    double? target;
    if (top < position.pixels) target = top;
    if (bottom > position.pixels + position.viewportDimension) target = bottom - position.viewportDimension;
    if (target == null) return;
    target = target.clamp(0, position.maxScrollExtent);
    if (RotideTheme.reduceMotionOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final controller = widget.controller;
    final headings = controller.rendered.headings;
    final top = headings.isEmpty ? 1 : headings.map((h) => h.level).reduce((a, b) => a < b ? a : b);
    final active = headings.indexWhere((heading) => heading.anchor == controller.activeAnchor);
    if (controller.activeAnchor != _shownAnchor) {
      _shownAnchor = controller.activeAnchor;
      if (active >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _follow(active));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          child: LabelText('содержание', style: RotideFonts.system(11, weight: FontWeight.w500, color: palette.text3)),
        ),
        Expanded(
          child: headings.isEmpty
              ? const EmptyState(symbol: 'list.bullet.indent', text: 'здесь появятся\nзаголовки документа')
              : ScrollConfiguration(
                  behavior: const _NoScrollbars(),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(left: Radii.gutter, right: Radii.gutter, bottom: Space.small),
                    child: SizedBox(
                      height: headings.length * (_rowHeight + _rowGap) - _rowGap,
                      child: Stack(
                        children: [
                          SpringValue(
                            value: active < 0 ? -1 : active.toDouble(),
                            spring: MotionTokens.snappy,
                            builder: (context, position, _) => active < 0
                                ? const SizedBox.shrink()
                                : Positioned(
                                    left: 0,
                                    right: 0,
                                    top: position * (_rowHeight + _rowGap),
                                    height: _rowHeight,
                                    child: DecoratedBox(
                                      decoration: continuousDecoration(
                                        radius: Radii.row,
                                        color: palette.selected,
                                        shadows: [swiftShadow(palette.shadow, 2, y: 1)],
                                      ),
                                    ),
                                  ),
                          ),
                          for (var index = 0; index < headings.length; index++)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: index * (_rowHeight + _rowGap),
                              height: _rowHeight,
                              child: _OutlineRow(
                                heading: headings[index],
                                depth: (headings[index].level - top).clamp(0, 4),
                                active: index == active,
                                onTap: () => controller.revealHeading(headings[index]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: MotionTokens.hover,
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
            child: LabelText(
              _statsLine(controller.stats, RotideTheme.languageOf(context)),
              key: ValueKey(controller.stats.words),
              maxLines: 1,
              style: RotideFonts.system(11.5, color: palette.text3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ],
    );
  }

  static String _statsLine(TextStats stats, RotideLanguage language) {
    final words = stats.words;
    if (language == RotideLanguage.en) {
      if (words == 0) return English.translate('пустой документ');
      return '${Russian.grouped(words, ',')} ${words == 1 ? 'word' : 'words'}, ${stats.readingMinutes} min read';
    }
    if (words == 0) return 'пустой документ';
    return '${Russian.grouped(words)} ${Russian.plural(words, 'слово', 'слова', 'слов')}, ${stats.readingMinutes} мин чтения';
  }
}

final class _OutlineRow extends StatelessWidget {
  const _OutlineRow({required this.heading, required this.depth, required this.active, required this.onTap});
  final Heading heading;
  final int depth;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final title = heading.title.isEmpty ? RotideTheme.textOf(context, 'без названия') : heading.title;
    return Hint(
      message: heading.title,
      verbatim: true,
      child: Interactive(
        onTap: onTap,
        selected: active,
        semanticLabel: title,
        translateLabel: false,
        builder: (context, hover, pressed) => PressScale(
          pressed: pressed,
          scale: 0.98,
          child: HoverColor(
            color: !active && hover ? palette.hover : const Color(0x00000000),
            builder: (context, fill) => Container(
              decoration: continuousDecoration(radius: Radii.row, color: fill),
              padding: EdgeInsets.only(left: 10 + depth * 12.0, right: 10),
              alignment: Alignment.centerLeft,
              child: HoverColor(
                color: active || hover || depth == 0 ? palette.ink : palette.text2,
                builder: (context, ink) => Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RotideFonts.system(12.5, weight: depth == 0 ? FontWeight.w500 : FontWeight.w400, color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _NoScrollbars extends ScrollBehavior {
  const _NoScrollbars();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}
