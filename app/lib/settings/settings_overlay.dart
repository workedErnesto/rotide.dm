import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rotide_native/rotide_native.dart';
import 'package:rotide_ui_kit/rotide_ui_kit.dart';

import '../app/scope.dart';

enum _Section {
  appearance('оформление', 'paintbrush'),
  typography('типографика', 'textformat.size'),
  about('rotide.dm', 'info.circle');

  const _Section(this.title, this.symbol);
  final String title;
  final String symbol;
}

const appIcons = [
  ('default', 'угольная'),
  ('stone', 'каменная'),
  ('blue', 'синяя'),
  ('green', 'зелёная'),
  ('lavender', 'лавандовая'),
  ('terracotta', 'терракотовая'),
];

/// Settings: a card over the window with a scrim and mica's two-column navigation. Done, Esc and a click on the scrim
/// close it; changes apply at once and reach every window.
final class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({super.key, required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  final _focus = FocusNode(debugLabel: 'settings');

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

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    final reduced = RotideTheme.reduceMotionOf(context);
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 48).clamp(0.0, 860.0);
        final height = (constraints.maxHeight - 48).clamp(0.0, 660.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onDismiss, child: ColoredBox(color: palette.scrim)),
            ),
            Center(
              child: Appear(
                builder: (context, shown) => SpringValue(
                  value: shown ? 1 : 0,
                  spring: MotionTokens.snappy,
                  motion: false,
                  builder: (context, progress, child) => Opacity(
                    opacity: progress.clamp(0.0, 1.0),
                    child: Transform.scale(scale: reduced ? 1 : 0.97 + 0.03 * progress, child: child),
                  ),
                  child: SizedBox(width: width, height: height, child: ModalSurface(child: _SettingsContent(onDismiss: widget.onDismiss))),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

final class _SettingsContent extends StatefulWidget {
  const _SettingsContent({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  _Section _section = _Section.appearance;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: compact ? 60 : 228,
            color: palette.shell,
            padding: const EdgeInsets.all(Space.normal),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, right: 10, top: 6, bottom: Space.normal),
                    child: LabelText('настройки', style: RotideFonts.system(20, color: palette.ink, tracking: -0.4)),
                  ),
                // Compact rows are 2 pt wider than the 36 pt column, as in SwiftUI, and overhang it evenly.
                SizedBox(
                  height: _Navigation.height,
                  child: OverflowBox(
                    minWidth: compact ? 38 : null,
                    maxWidth: compact ? 38 : null,
                    child: _Navigation(
                      selected: _section,
                      compact: compact,
                      onSelect: (section) => setState(() => _section = section),
                    ),
                  ),
                ),
                const Spacer(),
                if (compact)
                  Align(alignment: Alignment.centerLeft, child: IconButton(symbol: 'xmark', label: 'готово', size: 36, onPressed: widget.onDismiss))
                else
                  MButton(label: 'готово', kind: ButtonKind.primary, fill: true, onPressed: widget.onDismiss),
              ],
            ),
          ),
          const Hairline(vertical: true),
          Expanded(
            child: ColoredBox(
              color: palette.canvas,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey(_section),
                      padding: EdgeInsets.all(compact ? 20 : 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LabelText(_section.title, style: RotideFonts.system(22, color: palette.ink, tracking: -0.5)),
                          const SizedBox(height: Space.section),
                          ..._content(context),
                        ],
                      ),
                    ),
                  ),
                  FadePresenceFooter(
                    visible: _section == _Section.about,
                    child: Padding(
                      padding: EdgeInsets.only(left: compact ? 20 : 28, right: compact ? 20 : 28, bottom: 22, top: Space.small),
                      child: Row(
                        children: [
                          LabelText('develop', style: RotideFonts.system(12, color: palette.text3)),
                          const SizedBox(width: 3),
                          _Link(text: 'whoa', url: 'https://github.com/workedErnesto'),
                          const SizedBox(width: 3),
                          LabelText('with ❤️', style: RotideFonts.system(12, color: palette.text3)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  List<Widget> _content(BuildContext context) {
    final scope = AppScope.of(context);
    final preferences = scope.preferences;
    final palette = RotideTheme.paletteOf(context);
    final gap = const SizedBox(height: Space.section);
    switch (_section) {
      case _Section.appearance:
        return [
          _Group(title: 'тема', children: [
            _Row(
              title: 'тема',
              trailing: Segmented<String>(
                selection: preferences.appearance,
                options: [('system', 'система'), ('light', 'светлая'), ('dark', 'тёмная')],
                label: 'тема',
                onChanged: (value) => preferences.appearance = value,
              ),
            ),
          ]),
          gap,
          _Group(
            title: 'материал оболочки',
            footnote: 'прозрачность действует только на оболочку окна',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: SwitchRow(
                  label: LabelText('матовое стекло', style: RotideFonts.system(13, color: palette.ink)),
                  value: preferences.frosted,
                  onChanged: (value) => preferences.frosted = value,
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 14), child: Hairline()),
              _Row(
                title: 'прозрачность',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 160,
                      child: MSlider(
                        value: preferences.transparency,
                        min: 0,
                        max: 1,
                        label: 'прозрачность',
                        enabled: preferences.frosted,
                        onChanged: (value) => preferences.transparency = value,
                      ),
                    ),
                    const SizedBox(width: Space.small),
                    SizedBox(
                      width: 36,
                      child: Text('${(preferences.transparency * 100).round()}%',
                          textAlign: TextAlign.right, style: RotideFonts.system(11.5, color: palette.text3).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ],
                ),
              ),
            ],
          ),
          gap,
          _Group(
            title: 'иконка приложения',
            footnote: NativeBridge.instance.isMac
                ? 'иконка меняется в Dock, в Finder и в переключателе программ и сохраняется после выхода'
                : 'иконка меняется на панели задач, в меню «Пуск» и в ярлыках и сохраняется после выхода',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                // LazyVGrid with adaptive columns of at least 55 pt: the icons spread over the whole row.
                child: LayoutBuilder(builder: (context, constraints) {
                  final columns = ((constraints.maxWidth + Space.small) / (55 + Space.small)).floor().clamp(1, appIcons.length);
                  final width = (constraints.maxWidth - Space.small * (columns - 1)) / columns;
                  return Wrap(
                    spacing: Space.small,
                    runSpacing: Space.small,
                    children: [
                      for (final (name, title) in appIcons)
                        SizedBox(
                          width: width,
                          child: _IconChoice(name: name, title: title, selected: preferences.appIcon == name, onTap: () => preferences.appIcon = name),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ];
      case _Section.typography:
        return [
          _Group(title: 'текст интерфейса', children: [
            _Row(
              title: 'регистр текста',
              trailing: Segmented<bool>(
                selection: preferences.capitalized,
                // Each option is written in the style it selects.
                literal: true,
                options: const [(false, 'со строчной'), (true, 'С прописной')],
                label: 'регистр текста',
                onChanged: (value) => preferences.capitalized = value,
              ),
            ),
          ]),
          gap,
          _Group(
            title: 'документ',
            footnote: 'размер применяется к чтению и правке',
            children: [
              _Row(
                title: 'размер текста',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 150,
                      child: MSlider(value: preferences.zoom, min: 0.6, max: 2.5, label: 'размер текста', onChanged: (value) => preferences.zoom = value),
                    ),
                    const SizedBox(width: Space.small),
                    SizedBox(
                      width: 40,
                      child: Text('${(preferences.zoom * 100).round()}%',
                          textAlign: TextAlign.right, style: RotideFonts.system(11.5, color: palette.text3).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                    const SizedBox(width: Space.small),
                    MButton(label: 'сбросить', compact: true, onPressed: () => preferences.zoom = 1),
                  ],
                ),
              ),
            ],
          ),
        ];
      case _Section.about:
        return [
          LabelText(
            NativeBridge.instance.isMac
                ? 'читалка и редактор Markdown для macOS. открывайте документы, редактируйте их и экспортируйте в другие форматы.'
                : 'читалка и редактор Markdown для Windows. открывайте документы, редактируйте их и экспортируйте в другие форматы.',
            style: RotideFonts.system(13.5, color: palette.text2, height: 1.45),
          ),
          gap,
          _Group(children: [
            _Row(title: 'версия', trailing: const _Version()),
          ]),
        ];
    }
  }
}

/// The about footer fades in with the about section.
final class FadePresenceFooter extends StatelessWidget {
  const FadePresenceFooter({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => Presence(
        visible: visible,
        spring: MotionTokens.snappy,
        child: child,
        builder: (context, progress, child) => Opacity(opacity: progress.clamp(0.0, 1.0), child: child),
      );
}

final class _Navigation extends StatelessWidget {
  const _Navigation({required this.selected, required this.compact, required this.onSelect});
  static const height = 3 * 32.0 + 2 * 2.0;
  final _Section selected;
  final bool compact;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    const rowHeight = 32.0, gap = 2.0;
    return SizedBox(
      height: _Section.values.length * (rowHeight + gap) - gap,
      child: Stack(
        children: [
          SpringValue(
            value: selected.index.toDouble(),
            spring: MotionTokens.snappy,
            builder: (context, position, _) => Positioned(
              left: 0,
              right: 0,
              top: position * (rowHeight + gap),
              height: rowHeight,
              child: DecoratedBox(
                decoration: continuousDecoration(radius: Radii.row, color: palette.selected, shadows: [swiftShadow(palette.shadow, 2, y: 1)]),
              ),
            ),
          ),
          for (final section in _Section.values)
            Positioned(
              left: 0,
              right: 0,
              top: section.index * (rowHeight + gap),
              height: rowHeight,
              child: Hint(
                message: section.title,
                child: Interactive(
                  onTap: () => onSelect(section),
                  selected: section == selected,
                  semanticLabel: section.title,
                  builder: (context, hover, pressed) {
                    final active = section == selected;
                    return PressScale(
                      pressed: pressed,
                      scale: 0.98,
                      child: HoverColor(
                        color: !active && hover ? palette.hover : const Color(0x00000000),
                        builder: (context, fill) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: continuousDecoration(radius: Radii.row, color: fill),
                          child: HoverColor(
                            color: active || hover ? palette.ink : palette.text2,
                            builder: (context, ink) => Row(
                              children: [
                                SizedBox(width: 18, child: Center(child: Symbol(section.symbol, size: 12, color: ink))),
                                if (!compact) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LabelText(section.title,
                                        maxLines: 1, style: RotideFonts.system(13, weight: active ? FontWeight.w500 : FontWeight.w400, color: ink)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _Group extends StatelessWidget {
  const _Group({this.title, this.footnote, required this.children});
  final String? title;
  final String? footnote;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          LabelText(title!, style: RotideFonts.system(12, weight: FontWeight.w500, color: palette.text2)),
          const SizedBox(height: Space.small),
        ],
        DecoratedBox(
          decoration: continuousDecoration(radius: Radii.panel - 4, color: palette.surface, border: palette.hairline),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
        if (footnote != null) ...[
          const SizedBox(height: Space.small),
          LabelText(footnote!, style: RotideFonts.system(11.5, color: palette.text3, height: 1.3)),
        ],
      ],
    );
  }
}

/// A setting with its control at the end; on a narrow card the control goes under the title (ViewThatFits).
final class _Row extends StatelessWidget {
  const _Row({required this.title, required this.trailing});
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.normal,
          runSpacing: Space.small,
          children: [LabelText(title, style: RotideFonts.system(13, color: palette.ink)), trailing],
        ),
      ),
    );
  }
}

final class _IconChoice extends StatefulWidget {
  const _IconChoice({required this.name, required this.title, required this.selected, required this.onTap});
  final String name;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IconChoice> createState() => _IconChoiceState();
}

class _IconChoiceState extends State<_IconChoice> {
  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Hint(
      message: widget.title,
      child: Interactive(
        onTap: widget.onTap,
        selected: widget.selected,
        semanticLabel: widget.title,
        builder: (context, hover, pressed) => PressScale(
          pressed: pressed,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Image.asset('assets/icons/${widget.name}.png', width: 48, height: 48, cacheWidth: 96, filterQuality: FilterQuality.medium),
                const SizedBox(height: Space.micro),
                HoverColor(
                  color: widget.selected ? palette.ink : const Color(0x00000000),
                  builder: (context, color) => Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Link extends StatelessWidget {
  const _Link({required this.text, required this.url});
  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => NativeBridge.instance.openUrl(url),
        child: Text(text, style: RotideFonts.system(12, color: palette.text2).copyWith(decoration: TextDecoration.underline, decorationColor: palette.text2)),
      ),
    );
  }
}

final class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) {
    final palette = RotideTheme.paletteOf(context);
    return Text(
      NativeBridge.instance.version,
      style: RotideFonts.system(12, color: palette.text2).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

