import 'dart:math' as math;

import 'package:ai_assistant/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// (label, foreground, background, minimum ratio)
List<(String, Color, Color, double)> _pairs(AppPalette p) =>
    <(String, Color, Color, double)>[
      ('textPrimary/background', p.textPrimary, p.background, 7.0),
      ('textPrimary/surface', p.textPrimary, p.surface, 7.0),
      ('textPrimary/surfaceRaised', p.textPrimary, p.surfaceRaised, 7.0),
      ('textSecondary/background', p.textSecondary, p.background, 4.5),
      ('textSecondary/surface', p.textSecondary, p.surface, 4.5),
      ('textSecondary/surfaceRaised', p.textSecondary, p.surfaceRaised, 4.5),
      ('textTertiary/background', p.textTertiary, p.background, 4.5),
      ('textTertiary/surface', p.textTertiary, p.surface, 4.5),
      ('textTertiary/surfaceRaised', p.textTertiary, p.surfaceRaised, 4.5),
      ('onAccent/accent', p.onAccent, p.accent, 4.5),
      ('accent/background', p.accent, p.background, 4.5),
      ('accent/surface', p.accent, p.surface, 4.5),
      (
        'onAccentContainer/accentContainer',
        p.onAccentContainer,
        p.accentContainer,
        4.5,
      ),
      ('onUserBubble/userBubbleStart', p.onUserBubble, p.userBubbleStart, 4.5),
      ('onUserBubble/userBubbleEnd', p.onUserBubble, p.userBubbleEnd, 4.5),
      (
        'onAssistantBubble/assistantBubble',
        p.onAssistantBubble,
        p.assistantBubble,
        7.0,
      ),
      ('onCode/codeBackground', p.onCode, p.codeBackground, 4.5),
      ('success/background', p.success, p.background, 4.5),
      ('warning/background', p.warning, p.background, 4.5),
      ('danger/background', p.danger, p.background, 4.5),
      ('success/surface', p.success, p.surface, 4.5),
      ('warning/surface', p.warning, p.surface, 4.5),
      ('danger/surface', p.danger, p.surface, 4.5),
      ('outlineStrong/background', p.outlineStrong, p.background, 3.0),
      ('outlineStrong/surface', p.outlineStrong, p.surface, 3.0),
      ('outlineStrong/surfaceRaised', p.outlineStrong, p.surfaceRaised, 3.0),
    ];

void main() {
  final List<(String, AppPalette, AppPalette)> palettes =
      <(String, AppPalette, AppPalette)>[
    ('light', AppPalette.light, AppPalette.dark),
    ('dark', AppPalette.dark, AppPalette.light),
  ];

  for (final (String name, AppPalette palette, AppPalette other) in palettes) {
    group('AppPalette.$name', () {
      for (final (String label, Color fg, Color bg, double min)
          in _pairs(palette)) {
        test('$label >= $min:1', () {
          expect(fg.a, 1.0, reason: 'contrast pairs must be opaque');
          expect(bg.a, 1.0, reason: 'contrast pairs must be opaque');
          expect(_contrast(fg, bg), greaterThanOrEqualTo(min));
        });
      }

      test('copyWith() with no arguments preserves every color', () {
        expect(palette.copyWith().colors, palette.colors);
      });

      test('lerp covers every field (t=0 and t=1 return the endpoints)', () {
        expect(palette.lerp(other, 0).colors, palette.colors);
        expect(palette.lerp(other, 1).colors, other.colors);
      });
    });
  }
}
