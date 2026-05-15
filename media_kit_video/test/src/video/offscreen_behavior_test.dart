/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:media_kit_video/src/video/offscreen_behavior.dart';

void main() {
  group('OffscreenBehavior', () {
    group('presets', () {
      test('none preset disables all features', () {
        const behavior = OffscreenBehavior.none;

        expect(behavior.pauseWhenOffscreen, isFalse);
        expect(behavior.resumeWhenOnscreen, isFalse);
        expect(behavior.cullWhenOffscreen, isFalse);
        expect(behavior.suspensionMode, OffscreenSuspensionMode.none);
        expect(behavior.isEnabled, isFalse);
      });

      test('pauseAndResume preset only enables pause/resume', () {
        const behavior = OffscreenBehavior.pauseAndResume;

        expect(behavior.pauseWhenOffscreen, isTrue);
        expect(behavior.resumeWhenOnscreen, isTrue);
        expect(behavior.cullWhenOffscreen, isFalse);
        expect(behavior.suspensionMode, OffscreenSuspensionMode.none);
        expect(behavior.isEnabled, isTrue);
      });

      test('powerSaving preset enables pause, resume, cull, and disableOutput',
          () {
        const behavior = OffscreenBehavior.powerSaving;

        expect(behavior.pauseWhenOffscreen, isTrue);
        expect(behavior.resumeWhenOnscreen, isTrue);
        expect(behavior.cullWhenOffscreen, isTrue);
        expect(behavior.suspensionMode, OffscreenSuspensionMode.disableOutput);
        expect(behavior.isEnabled, isTrue);
      });

      test('maxPowerSaving preset uses disableDecoding mode', () {
        const behavior = OffscreenBehavior.maxPowerSaving;

        expect(behavior.pauseWhenOffscreen, isTrue);
        expect(behavior.resumeWhenOnscreen, isTrue);
        expect(behavior.cullWhenOffscreen, isTrue);
        expect(
            behavior.suspensionMode, OffscreenSuspensionMode.disableDecoding);
        expect(behavior.isEnabled, isTrue);
      });
    });

    group('isEnabled', () {
      test('returns false when all features disabled', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.none,
        );
        expect(behavior.isEnabled, isFalse);
      });

      test('returns true when only pauseWhenOffscreen is enabled', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: true,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.none,
        );
        expect(behavior.isEnabled, isTrue);
      });

      test('returns true when only cullWhenOffscreen is enabled', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          cullWhenOffscreen: true,
          suspensionMode: OffscreenSuspensionMode.none,
        );
        expect(behavior.isEnabled, isTrue);
      });

      test('returns true when only suspensionMode is not none', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.disableOutput,
        );
        expect(behavior.isEnabled, isTrue);
      });

      // This test ensures resumeWhenOnscreen alone doesn't enable the feature
      // (it only makes sense when pauseWhenOffscreen is also true)
      test('returns false when only resumeWhenOnscreen is true', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          resumeWhenOnscreen: true,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.none,
        );
        expect(behavior.isEnabled, isFalse);
      });
    });

    group('constructor validation', () {
      test('accepts visibilityThreshold at lower bound (0.0)', () {
        expect(
          () => const OffscreenBehavior(visibilityThreshold: 0.0),
          returnsNormally,
        );
      });

      test('accepts visibilityThreshold at upper bound (1.0)', () {
        expect(
          () => const OffscreenBehavior(visibilityThreshold: 1.0),
          returnsNormally,
        );
      });

      test('accepts visibilityThreshold in valid range', () {
        expect(
          () => const OffscreenBehavior(visibilityThreshold: 0.5),
          returnsNormally,
        );
      });

      // Note: These assertion tests only work in debug mode
      // In release mode, assertions are stripped
      test('rejects visibilityThreshold below 0.0', () {
        expect(
          () => OffscreenBehavior(visibilityThreshold: -0.1),
          throwsA(isA<AssertionError>()),
        );
      });

      test('rejects visibilityThreshold above 1.0', () {
        expect(
          () => OffscreenBehavior(visibilityThreshold: 1.1),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('copyWith', () {
      test('preserves all values when called without arguments', () {
        const original = OffscreenBehavior(
          pauseWhenOffscreen: true,
          resumeWhenOnscreen: true,
          cullWhenOffscreen: true,
          suspensionMode: OffscreenSuspensionMode.disableDecoding,
          visibilityThreshold: 0.5,
          debounceDuration: Duration(milliseconds: 200),
        );

        final copy = original.copyWith();

        expect(copy.pauseWhenOffscreen, original.pauseWhenOffscreen);
        expect(copy.resumeWhenOnscreen, original.resumeWhenOnscreen);
        expect(copy.cullWhenOffscreen, original.cullWhenOffscreen);
        expect(copy.suspensionMode, original.suspensionMode);
        expect(copy.visibilityThreshold, original.visibilityThreshold);
        expect(copy.debounceDuration, original.debounceDuration);
      });

      test('overrides only specified values', () {
        const original = OffscreenBehavior(
          pauseWhenOffscreen: true,
          resumeWhenOnscreen: true,
          cullWhenOffscreen: true,
          suspensionMode: OffscreenSuspensionMode.disableDecoding,
        );

        final copy = original.copyWith(
          pauseWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.disableOutput,
        );

        expect(copy.pauseWhenOffscreen, isFalse);
        expect(copy.suspensionMode, OffscreenSuspensionMode.disableOutput);
        // These should remain unchanged
        expect(copy.resumeWhenOnscreen, isTrue);
        expect(copy.cullWhenOffscreen, isTrue);
      });
    });

    group('equality', () {
      test('equal instances have same hashCode', () {
        const a = OffscreenBehavior(
          pauseWhenOffscreen: true,
          resumeWhenOnscreen: true,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.disableOutput,
          visibilityThreshold: 0.3,
          debounceDuration: Duration(milliseconds: 100),
        );
        const b = OffscreenBehavior(
          pauseWhenOffscreen: true,
          resumeWhenOnscreen: true,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.disableOutput,
          visibilityThreshold: 0.3,
          debounceDuration: Duration(milliseconds: 100),
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different instances are not equal', () {
        const a = OffscreenBehavior(pauseWhenOffscreen: true);
        const b = OffscreenBehavior(pauseWhenOffscreen: false);

        expect(a, isNot(equals(b)));
      });

      test('works correctly in Sets and as Map keys', () {
        const behavior1 = OffscreenBehavior(pauseWhenOffscreen: true);
        const behavior2 = OffscreenBehavior(pauseWhenOffscreen: true);
        const behavior3 = OffscreenBehavior(pauseWhenOffscreen: false);

        final set = <OffscreenBehavior>{}
          ..addAll([behavior1, behavior2, behavior3]);
        // behavior1 and behavior2 are equal, so set should have 2 items
        expect(set.length, 2);

        final map = <OffscreenBehavior, String>{};
        map[behavior1] = 'first';
        map[behavior2] = 'second'; // Should overwrite 'first'
        expect(map[behavior1], 'second');
      });
    });

    group('defaults', () {
      test('default constructor has backward-compatible defaults', () {
        const behavior = OffscreenBehavior();

        expect(behavior.pauseWhenOffscreen, isFalse);
        expect(behavior.resumeWhenOnscreen, isFalse);
        expect(behavior.cullWhenOffscreen, isFalse);
        expect(behavior.suspensionMode, OffscreenSuspensionMode.none);
        expect(behavior.visibilityThreshold, 0.0);
        expect(behavior.debounceDuration, const Duration(milliseconds: 150));
        expect(behavior.onOffscreen, isNull);
        expect(behavior.onOnscreen, isNull);
        expect(behavior.isEnabled, isFalse);
      });
    });

    group('callbacks', () {
      test('onOffscreen callback can be set', () {
        var callCount = 0;
        double? lastFraction;

        final behavior = OffscreenBehavior(
          onOffscreen: (fraction) {
            callCount++;
            lastFraction = fraction;
          },
        );

        expect(behavior.onOffscreen, isNotNull);

        // Simulate calling the callback
        behavior.onOffscreen!(0.5);
        expect(callCount, 1);
        expect(lastFraction, 0.5);
      });

      test('onOnscreen callback can be set', () {
        var callCount = 0;
        double? lastFraction;

        final behavior = OffscreenBehavior(
          onOnscreen: (fraction) {
            callCount++;
            lastFraction = fraction;
          },
        );

        expect(behavior.onOnscreen, isNotNull);

        // Simulate calling the callback
        behavior.onOnscreen!(0.8);
        expect(callCount, 1);
        expect(lastFraction, 0.8);
      });

      test('isEnabled returns true when only onOffscreen is set', () {
        final behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.none,
          onOffscreen: (_) {},
        );
        expect(behavior.isEnabled, isTrue);
      });

      test('isEnabled returns true when only onOnscreen is set', () {
        final behavior = OffscreenBehavior(
          pauseWhenOffscreen: false,
          cullWhenOffscreen: false,
          suspensionMode: OffscreenSuspensionMode.none,
          onOnscreen: (_) {},
        );
        expect(behavior.isEnabled, isTrue);
      });

      test('copyWith preserves callbacks when not overridden', () {
        void offscreenCallback(double f) {}
        void onscreenCallback(double f) {}

        final original = OffscreenBehavior(
          pauseWhenOffscreen: true,
          onOffscreen: offscreenCallback,
          onOnscreen: onscreenCallback,
        );

        final copy = original.copyWith(pauseWhenOffscreen: false);

        expect(copy.pauseWhenOffscreen, isFalse);
        expect(copy.onOffscreen, same(offscreenCallback));
        expect(copy.onOnscreen, same(onscreenCallback));
      });

      test('copyWith can override callbacks', () {
        void originalCallback(double f) {}
        void newCallback(double f) {}

        final original = OffscreenBehavior(
          onOffscreen: originalCallback,
        );

        final copy = original.copyWith(onOffscreen: newCallback);

        expect(copy.onOffscreen, same(newCallback));
      });

      test('equality considers callbacks', () {
        void callback(double f) {}

        final a = OffscreenBehavior(onOffscreen: callback);
        final b = OffscreenBehavior(onOffscreen: callback);
        final c = OffscreenBehavior(onOffscreen: (_) {});

        // Same callback reference = equal
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));

        // Different callback reference = not equal
        expect(a, isNot(equals(c)));
      });

      test('presets have null callbacks', () {
        expect(OffscreenBehavior.none.onOffscreen, isNull);
        expect(OffscreenBehavior.none.onOnscreen, isNull);
        expect(OffscreenBehavior.pauseAndResume.onOffscreen, isNull);
        expect(OffscreenBehavior.pauseAndResume.onOnscreen, isNull);
        expect(OffscreenBehavior.powerSaving.onOffscreen, isNull);
        expect(OffscreenBehavior.powerSaving.onOnscreen, isNull);
        expect(OffscreenBehavior.maxPowerSaving.onOffscreen, isNull);
        expect(OffscreenBehavior.maxPowerSaving.onOnscreen, isNull);
      });
    });

    group('toString', () {
      test('includes all property values', () {
        const behavior = OffscreenBehavior(
          pauseWhenOffscreen: true,
          suspensionMode: OffscreenSuspensionMode.disableOutput,
        );

        final str = behavior.toString();

        expect(str, contains('pauseWhenOffscreen: true'));
        expect(str,
            contains('suspensionMode: OffscreenSuspensionMode.disableOutput'));
        expect(str, contains('onOffscreen: null'));
        expect(str, contains('onOnscreen: null'));
      });

      test('toString shows Function for non-null callbacks', () {
        final behavior = OffscreenBehavior(
          onOffscreen: (_) {},
          onOnscreen: (_) {},
        );

        final str = behavior.toString();

        expect(str, contains('onOffscreen: Function'));
        expect(str, contains('onOnscreen: Function'));
      });
    });
  });

  group('OffscreenSuspensionMode', () {
    test('has expected values', () {
      expect(OffscreenSuspensionMode.values, hasLength(3));
      expect(OffscreenSuspensionMode.values,
          contains(OffscreenSuspensionMode.none));
      expect(OffscreenSuspensionMode.values,
          contains(OffscreenSuspensionMode.disableOutput));
      expect(OffscreenSuspensionMode.values,
          contains(OffscreenSuspensionMode.disableDecoding));
    });
  });
}
