import 'dart:math' as math;

/// Maps raw microphone levels onto 0..1 for the voice orb.
///
/// The platform scales differ (roughly -2..10 on Android, large negative
/// decibel values on iOS) and are not documented as stable, so this adapts: it
/// tracks a slowly relaxing floor and ceiling, scales into that range, and
/// smooths with a fast attack and slower release. Steady background noise
/// settles near 0; speech rises clearly above it.
final class SoundLevelNormalizer {
  SoundLevelNormalizer({
    this.minSpan = 6,
    this.relax = 0.02,
    this.attack = 0.6,
    this.release = 0.2,
  });

  /// Smallest range ever used for scaling, so tiny fluctuations in a silent
  /// room are not amplified into movement.
  final double minSpan;

  /// How quickly the floor and ceiling drift toward the current level.
  final double relax;
  final double attack;
  final double release;

  double? _low;
  double? _high;
  double _output = 0;

  void reset() {
    _low = null;
    _high = null;
    _output = 0;
  }

  /// Feeds one raw level and returns the smoothed value in [0, 1]. Non-finite
  /// input is ignored.
  double add(double level) {
    if (level.isNaN || level.isInfinite) return _output;
    var low = _low ?? level - 1;
    var high = _high ?? level + 1;
    low = level < low ? level : low + (level - low) * relax;
    high = level > high ? level : high + (level - high) * relax;
    _low = low;
    _high = high;
    final double span = math.max(high - low, minSpan);
    final double scaled = ((level - low) / span).clamp(0.0, 1.0).toDouble();
    final double rate = scaled > _output ? attack : release;
    _output = _output + (scaled - _output) * rate;
    return _output;
  }
}
