import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand + design tokens cho SMS Gateway.
class AppTheme {
  AppTheme._();

  // ------ Brand palette ------
  static const Color brandSeed = Color(0xFF4F46E5); // indigo-600

  // Semantic status colors (cùng tone Material 3 nhưng saturated hơn cho dot/badge)
  static const Color statusRunning   = Color(0xFF10B981); // emerald-500
  static const Color statusStarting  = Color(0xFFF59E0B); // amber-500
  static const Color statusStopped   = Color(0xFF94A3B8); // slate-400
  static const Color statusErrored   = Color(0xFFEF4444); // red-500

  // Log level colors
  static const Color logSuccess = Color(0xFF10B981);
  static const Color logWarning = Color(0xFFF59E0B);
  static const Color logError   = Color(0xFFEF4444);
  static const Color logInfo    = Color(0xFF64748B);

  // ------ Spacing scale ------
  static const double s4  = 4;
  static const double s8  = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;

  // ------ Radius ------
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 24;

  // ------ Hero gradient (cho header trên Home) ------
  static const Gradient runningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF10B981)],
  );
  static const Gradient stoppedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  );
  static const Gradient erroredGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
  );
  static const Gradient startingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
  );

  // ------ Themes ------
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: Brightness.light);
    return _build(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: Brightness.dark);
    return _build(scheme, Brightness.dark);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final baseText = isLight ? Colors.black : Colors.white;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF8FAFC)
          : const Color(0xFF0F172A),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: baseText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: baseText),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(
            color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
            width: 1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(
          color: baseText.withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
        ),
        helperStyle: TextStyle(
          color: baseText.withValues(alpha: 0.55),
          fontSize: 12,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isLight ? Colors.white : const Color(0xFF1E293B),
        side: BorderSide(
          color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        labelStyle: TextStyle(
          color: baseText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: scheme.primary,
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
        backgroundColor: isLight ? const Color(0xFF0F172A) : const Color(0xFF334155),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),

      textTheme: const TextTheme(
        displaySmall:    TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineMedium:  TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        headlineSmall:   TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge:      TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium:     TextStyle(fontWeight: FontWeight.w600),
        titleSmall:      TextStyle(fontWeight: FontWeight.w600),
        bodyLarge:       TextStyle(fontWeight: FontWeight.w400, height: 1.4),
        bodyMedium:      TextStyle(fontWeight: FontWeight.w400, height: 1.4),
        labelLarge:      TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ).apply(bodyColor: baseText, displayColor: baseText),
    );
  }
}
