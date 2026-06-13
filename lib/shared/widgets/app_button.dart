import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppButtonVariant { primary, danger, neutral, success }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (variant) {
      AppButtonVariant.primary => theme.colorScheme.primary,
      AppButtonVariant.danger => AppTheme.logError,
      AppButtonVariant.success => AppTheme.logSuccess,
      AppButtonVariant.neutral => theme.colorScheme.surface,
    };
    final foreground = variant == AppButtonVariant.neutral
        ? theme.colorScheme.onSurface
        : Colors.white;

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground,
        disabledBackgroundColor: color.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
      ),
      onPressed: loading ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (loading || icon != null) const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}
