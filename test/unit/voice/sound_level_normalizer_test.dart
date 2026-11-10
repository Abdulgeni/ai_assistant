import 'package:ai_assistant/data/voice/sound_level_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> _run(List<double> levels) {
  final SoundLevelNormalizer normalizer = SoundLevelNormalizer();
  return <double>[for (final double level in levels) normalizer.add(level)];
}

void main() {
  final Map<String, List<double>> scales = <String, List<double>>{
    'an Android-like scale (-2..10)': <double>[
      ...List<double>.filled(20, -2),
      6, 8, 10, 9, 7, 8, 10, 9,
      ...List<double>.filled(40, -2),
    ],
    'an iOS-like scale (-50..0)': <double>[
      ...List<double>.filled(20, -50),
      -20, -10, -5, -8, -12, -6, -3, -9,
      ...List<double>.filled(40, -50),
    ],
  };

  for (final MapEntry<String, List<double>> scale in scales.entries) {
    group(scale.key, () {
      final List<double> out = _run(scale.value);

      test('stays within [0, 1]', () {
        expect(out.every((double v) => v >= 0 && v <= 1), isTrue);
      });

      test('speech is clearly louder than silence', () {
        final double speech = out.sublist(20, 28).reduce((double a, double b) => a > b ? a : b);
        final double silence = out.sublist(0, 19).reduce((double a, double b) => a > b ? a : b);
        expect(speech, greaterThan(0.5));
        expect(silence, lessThan(0.25));
      });

      test('decays back to near zero after speech', () {
        expect(out.last, lessThan(0.15));
      });
    });
  }

  test('constant input settles near zero', () {
    expect(_run(List<double>.filled(200, 5)).last, lessThan(0.05));
  });

  test('ignores NaN and infinity', () {
    final SoundLevelNormalizer n = SoundLevelNormalizer();
    final double before = n.add(3);
    expect(n.add(double.nan), before);
    expect(n.add(double.infinity), before);
  });

  test('reset forgets the learned range', () {
    final SoundLevelNormalizer n = SoundLevelNormalizer();
    for (var i = 0; i < 50; i++) {
      n.add(-50);
    }
    n.reset();
    expect(n.add(10), lessThanOrEqualTo(1));
  });
}
