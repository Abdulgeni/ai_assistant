import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/app_background.dart';
import 'package:ai_assistant/core/theme/widgets/glass_surface.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/core/theme/widgets/skeleton.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(
  Widget child, {
  bool reduceMotion = false,
  bool highContrast = false,
  TextDirection direction = TextDirection.ltr,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (BuildContext context, Widget? app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        highContrast: highContrast,
      ),
      child: Directionality(textDirection: direction, child: app!),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('GlassSurface', () {
    testWidgets('blurs the backdrop by default', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const GlassSurface(child: SizedBox(width: 100, height: 40))),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('is solid (no blur) in high-contrast mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const GlassSurface(child: SizedBox(width: 100, height: 40)),
          highContrast: true,
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('opaque: true overrides the platform setting',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const GlassSurface(
            opaque: true,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('lays out under RTL without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const GlassSurface(child: SizedBox(width: 100, height: 40)),
          direction: TextDirection.rtl,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Pressable', () {
    testWidgets('expands small content to a 48dp touch target',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          Pressable(
            onPressed: () {},
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final Size size = tester.getSize(find.byType(Pressable));
      expect(size.width, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    });

    testWidgets('invokes onPressed on tap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _harness(
          Pressable(
            onPressed: () => taps++,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      await tester.tap(find.byType(Pressable));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('does nothing when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const Pressable(
            onPressed: null,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      await tester.tap(find.byType(Pressable), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('activates through the accessibility tap action',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      int taps = 0;
      await tester.pumpWidget(
        _harness(
          Pressable(
            semanticLabel: 'Send',
            onPressed: () => taps++,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('Send'));
      await tester.pump();
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('scales down while pressed', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          Pressable(
            onPressed: () {},
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(Pressable)));
      await tester.pump(kPressTimeout);
      final Finder scale = find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(AnimatedScale),
      );
      expect(
        tester.widget<AnimatedScale>(scale).scale,
        AppInteraction.pressedScale,
      );
      await gesture.up();
      await tester.pump();
    });

    testWidgets('under reduce-motion it dims instead of scaling',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          Pressable(
            onPressed: () {},
            child: const SizedBox(width: 10, height: 10),
          ),
          reduceMotion: true,
        ),
      );
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.byType(Pressable)));
      await tester.pump(kPressTimeout);
      final Finder scale = find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(AnimatedScale),
      );
      final Finder opacity = find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedScale>(scale).scale, 1.0);
      expect(
        tester.widget<AnimatedOpacity>(opacity).opacity,
        AppInteraction.reducedMotionPressedOpacity,
      );
      await gesture.up();
      await tester.pump();
    });
  });

  group('AppBackground', () {
    testWidgets('draws the glow and the child', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const AppBackground(child: Text('content'))),
      );
      expect(find.byKey(AppBackground.glowKey), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('omits the glow in high-contrast mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const AppBackground(child: Text('content')),
          highContrast: true,
        ),
      );
      expect(find.byKey(AppBackground.glowKey), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('lays out under RTL without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const AppBackground(child: Text('content')),
          direction: TextDirection.rtl,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Skeleton', () {
    testWidgets('animates when motion is allowed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const SkeletonScope(child: SkeletonBox(width: 120, height: 16)),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is static under reduce-motion', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const SkeletonScope(child: SkeletonBox(width: 120, height: 16)),
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('SkeletonText renders the requested number of lines',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const SizedBox(
            width: 200,
            child: SkeletonScope(child: SkeletonText(lines: 4)),
          ),
          reduceMotion: true,
        ),
      );
      expect(find.byType(SkeletonBox), findsNWidgets(4));
    });

    testWidgets('announces a single label when provided',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _harness(
          const SkeletonScope(
            semanticLabel: 'Loading',
            child: SkeletonText(),
          ),
          reduceMotion: true,
        ),
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the short last line hugs the start edge in LTR',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const SizedBox(
            width: 200,
            child: SkeletonScope(child: SkeletonText()),
          ),
          reduceMotion: true,
        ),
      );
      final Finder boxes = find.byType(SkeletonBox);
      expect(
        tester.getTopLeft(boxes.last).dx,
        tester.getTopLeft(boxes.first).dx,
      );
    });

    testWidgets('the short last line hugs the start edge in RTL',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const SizedBox(
            width: 200,
            child: SkeletonScope(child: SkeletonText()),
          ),
          reduceMotion: true,
          direction: TextDirection.rtl,
        ),
      );
      final Finder boxes = find.byType(SkeletonBox);
      expect(
        tester.getTopRight(boxes.last).dx,
        tester.getTopRight(boxes.first).dx,
      );
    });
  });
}
