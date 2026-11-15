// Ported from the Swift MotionTokens.swift (mica's shared/tokens.json). Keep in step with preview.css.
import 'dart:math' as math;

import 'package:flutter/physics.dart';

/// A spring given the SwiftUI way: response (seconds) and damping fraction. [description] converts it to the
/// mass-stiffness-damping form Flutter simulates, so both stacks move along the same curve.
final class Spring {
  const Spring(this.response, this.damping);
  final double response;
  final double damping;

  SpringDescription get description {
    final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
    return SpringDescription(mass: 1, stiffness: stiffness, damping: 4 * math.pi * damping / response);
  }

  /// Time until the spring rests within a hair of its target: SwiftUI's settlingDuration, used to time waves.
  double get settlingDuration {
    final omega = 2 * math.pi / response;
    // Envelope e^(-zeta*omega*t) below 0.001.
    return math.log(1000) / (damping * omega);
  }

  /// Value at [time] of a spring moving from 0 to 1 at rest.
  double value(double time) {
    final simulation = SpringSimulation(description, 0, 1, 0);
    return simulation.x(time);
  }
}

abstract final class MotionTokens {
  /// Colour and opacity feedback. Not movement, so it stays on with Reduce Motion.
  static const hover = Duration(milliseconds: 120);
  static const press = Spring(0.22, 0.72);
  static const snappy = Spring(0.3, 0.86);
  static const panel = Spring(0.36, 0.9);

  /// A livelier spring with a small overshoot.
  static const bouncy = Spring(0.38, 0.6);
  static const popScale = 0.96;

  /// Window and card entrance: parts appear one after another with the panel spring, each step later by
  /// [entranceStagger] and rising by [entranceRise] points. With Reduce Motion only a fade of [reducedFade].
  static const entranceStagger = 0.04;
  static const entranceRise = 10.0;
  static const entranceCardScale = 0.985;
  static const windowFade = Duration(milliseconds: 180);
  static const reducedFade = Duration(milliseconds: 150);

  /// The rotide.dm wordmark assembles glyph by glyph: each glyph rises, sharpens and moves together from spread points
  /// apart. A long text keeps the whole wave under [wordmarkStaggerCap].
  static const wordmarkLetterStagger = 0.045;
  static const wordmarkLetterDuration = 0.34;
  static const wordmarkStaggerCap = 0.3;
  static const wordmarkRise = 10.0;
  static const wordmarkSpread = 5.0;
  static const wordmarkBlur = 4.0;
}
