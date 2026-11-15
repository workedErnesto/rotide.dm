import 'dart:ui' show Rect, lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../tokens/motion.dart';

/// Several numbers moving on springs together, retargetable mid-flight with their current velocity kept, as SwiftUI
/// springs are. A null spring jumps.
final class SpringVector extends ChangeNotifier {
  SpringVector({required TickerProvider vsync, required List<double> initial})
      : _values = List.of(initial),
        _velocities = List.filled(initial.length, 0),
        _targets = List.of(initial) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  final List<double> _values;
  final List<double> _velocities;
  final List<double> _targets;
  List<SpringSimulation>? _simulations;
  Duration _start = Duration.zero;
  Duration _now = Duration.zero;

  List<double> get values => _values;
  List<double> get targets => _targets;
  bool get isAnimating => _ticker.isActive;

  void animateTo(List<double> target, Spring? spring, {Duration delay = Duration.zero}) {
    for (var i = 0; i < target.length; i++) {
      _targets[i] = target[i];
    }
    if (spring == null) {
      _stop();
      for (var i = 0; i < target.length; i++) {
        _values[i] = target[i];
        _velocities[i] = 0;
      }
      notifyListeners();
      return;
    }
    final description = spring.description;
    _simulations = [
      for (var i = 0; i < target.length; i++)
        SpringSimulation(description, _values[i], target[i], _velocities[i], tolerance: const Tolerance(distance: 0.0005, velocity: 0.005)),
    ];
    _start = _now + delay;
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _start = delay;
      _ticker.start();
    }
  }

  void jumpTo(List<double> target) => animateTo(target, null);

  void _tick(Duration elapsed) {
    _now = elapsed;
    final simulations = _simulations;
    if (simulations == null) return _stop();
    if (elapsed < _start) return;
    final t = (elapsed - _start).inMicroseconds / Duration.microsecondsPerSecond;
    var done = true;
    for (var i = 0; i < simulations.length; i++) {
      final simulation = simulations[i];
      if (simulation.isDone(t)) {
        _values[i] = _targets[i];
        _velocities[i] = 0;
      } else {
        done = false;
        _values[i] = simulation.x(t);
        _velocities[i] = simulation.dx(t);
      }
    }
    notifyListeners();
    if (done) _stop();
  }

  void _stop() {
    _simulations = null;
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// A number that follows [value] on [spring]; Reduce Motion or a null spring makes it jump.
final class SpringValue extends StatefulWidget {
  const SpringValue({
    super.key,
    required this.value,
    required this.spring,
    required this.builder,
    this.delay = Duration.zero,
    this.motion = true,
    this.child,
  });

  final double value;
  final Spring? spring;
  final Duration delay;

  /// False for colour and opacity feedback that stays on with Reduce Motion.
  final bool motion;
  final Widget Function(BuildContext context, double value, Widget? child) builder;
  final Widget? child;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue> with SingleTickerProviderStateMixin {
  late final _vector = SpringVector(vsync: this, initial: [widget.value])..addListener(_changed);

  void _changed() => setState(() {});

  @override
  void didUpdateWidget(SpringValue old) {
    super.didUpdateWidget(old);
    if (widget.value != _vector.targets.first) {
      final reduced = widget.motion && RotideTheme.reduceMotionOf(context);
      _vector.animateTo([widget.value], reduced ? null : widget.spring, delay: widget.delay);
    }
  }

  @override
  void dispose() {
    _vector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _vector.values.first, widget.child);
}

/// Shows its child while [visible] and for as long as it takes to leave: [progress] runs 0 to 1 on the way in and
/// back on the way out, with the spring (or curve) chosen by the caller. SwiftUI's insertion and removal transitions.
final class Presence extends StatefulWidget {
  const Presence({
    super.key,
    required this.visible,
    required this.builder,
    this.spring,
    this.curve,
    this.exitSpring,
    this.exitCurve,
    this.child,
  });

  final bool visible;
  final Spring? spring;

  /// Used when [spring] is null: a timed curve, as `easeOut(duration:)`.
  final (Curve, Duration)? curve;
  final Spring? exitSpring;
  final (Curve, Duration)? exitCurve;
  final Widget Function(BuildContext context, double progress, Widget child) builder;
  final Widget? child;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence> with TickerProviderStateMixin {
  late final _spring = SpringVector(vsync: this, initial: [widget.visible ? 1 : 0])..addListener(_changed);
  late final _timed = AnimationController(vsync: this, value: widget.visible ? 1 : 0)..addListener(_timedChanged);
  double _progress = 0;
  bool _usesTimed = false;
  Widget? _lastChild;

  @override
  void initState() {
    super.initState();
    _progress = widget.visible ? 1 : 0;
  }

  void _changed() => setState(() => _progress = _spring.values.first);
  void _timedChanged() => setState(() => _progress = _timed.value);

  @override
  void didUpdateWidget(Presence old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    final target = widget.visible ? 1.0 : 0.0;
    final spring = widget.visible ? widget.spring : (widget.exitSpring ?? widget.spring);
    final curve = widget.visible ? widget.curve : (widget.exitCurve ?? widget.curve);
    if (spring != null) {
      if (_usesTimed) {
        _timed.stop();
        _spring.jumpTo([_progress]);
      }
      _usesTimed = false;
      _spring.animateTo([target], spring);
    } else if (curve != null) {
      _usesTimed = true;
      _timed.value = _progress;
      _timed.animateTo(target, duration: curve.$2, curve: curve.$1);
    } else {
      _spring.jumpTo([target]);
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    _timed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) _lastChild = widget.child;
    if (_progress <= 0.0005 && !widget.visible) return const SizedBox.shrink();
    return widget.builder(context, _progress, _lastChild ?? const SizedBox.shrink());
  }
}

/// A rectangle that glides to each new target on a spring: the plate under the current row, the thumb of a
/// segmented control. SwiftUI's matchedGeometryEffect for one moving shape.
final class SpringRect extends StatefulWidget {
  const SpringRect({super.key, required this.rect, required this.spring, required this.builder});
  final Rect? rect;
  final Spring? spring;
  final Widget Function(BuildContext context, Rect? rect) builder;

  @override
  State<SpringRect> createState() => _SpringRectState();
}

class _SpringRectState extends State<SpringRect> with SingleTickerProviderStateMixin {
  SpringVector? _vector;

  List<double> _parts(Rect rect) => [rect.left, rect.top, rect.width, rect.height];

  @override
  void didUpdateWidget(SpringRect old) {
    super.didUpdateWidget(old);
    final rect = widget.rect;
    if (rect == null) return;
    final vector = _vector;
    if (vector == null) {
      _vector = SpringVector(vsync: this, initial: _parts(rect))..addListener(() => setState(() {}));
    } else if (old.rect != rect) {
      final reduced = RotideTheme.reduceMotionOf(context);
      vector.animateTo(_parts(rect), reduced ? null : widget.spring);
    }
  }

  @override
  void dispose() {
    _vector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.rect;
    if (rect == null) return widget.builder(context, null);
    _vector ??= SpringVector(vsync: this, initial: _parts(rect))..addListener(() => setState(() {}));
    final v = _vector!.values;
    return widget.builder(context, Rect.fromLTWH(v[0], v[1], v[2], v[3]));
  }
}

/// Linear interpolation helper for transitions driven by a 0...1 progress.
double mix(double from, double to, double t) => lerpDouble(from, to, t)!;
