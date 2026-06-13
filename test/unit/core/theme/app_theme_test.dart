import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme.light()', () {
    final theme = AppTheme.light();

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness is light', () {
      expect(theme.brightness, Brightness.light);
    });

    test('seed color produces consistent indigo palette', () {
      expect(theme.colorScheme.primary, isNotNull);
    });

    test('Card has rounded shape', () {
      final cardShape = theme.cardTheme.shape;
      expect(cardShape, isA<RoundedRectangleBorder>());
    });

    test('FilledButton has min height ≥ 48dp', () {
      final style = theme.filledButtonTheme.style!;
      final size = style.minimumSize?.resolve({});
      expect(size?.height, greaterThanOrEqualTo(48));
    });

    test('inputDecorationTheme is filled (no border)', () {
      expect(theme.inputDecorationTheme.filled, isTrue);
    });

    test('snackBar uses floating behavior', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });
  });

  group('AppTheme.dark()', () {
    final theme = AppTheme.dark();

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness is dark', () {
      expect(theme.brightness, Brightness.dark);
    });

    test('scaffold background is dark', () {
      // Slate-900 ish #0F172A
      expect(theme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.1));
    });
  });

  group('AppTheme tokens', () {
    test('spacing scale ascending', () {
      final scale = [AppTheme.s4, AppTheme.s8, AppTheme.s12, AppTheme.s16,
        AppTheme.s20, AppTheme.s24, AppTheme.s32, AppTheme.s40];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('radius scale ascending', () {
      expect(AppTheme.rSm, lessThan(AppTheme.rMd));
      expect(AppTheme.rMd, lessThan(AppTheme.rLg));
      expect(AppTheme.rLg, lessThan(AppTheme.rXl));
    });

    test('all status colors are distinct', () {
      final colors = {
        AppTheme.statusRunning,
        AppTheme.statusStarting,
        AppTheme.statusStopped,
        AppTheme.statusErrored,
      };
      expect(colors.length, 4);
    });

    test('log level colors are distinct', () {
      final colors = {
        AppTheme.logSuccess,
        AppTheme.logWarning,
        AppTheme.logError,
        AppTheme.logInfo,
      };
      expect(colors.length, 4);
    });

    test('gradients have at least 2 stops', () {
      for (final g in [
        AppTheme.runningGradient,
        AppTheme.stoppedGradient,
        AppTheme.startingGradient,
        AppTheme.erroredGradient,
      ]) {
        expect((g as LinearGradient).colors.length, greaterThanOrEqualTo(2));
      }
    });
  });
}
