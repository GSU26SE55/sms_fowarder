import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.s8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.rSm),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: AppTheme.s12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1,
              ),
            ),
            const SizedBox(height: AppTheme.s4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
