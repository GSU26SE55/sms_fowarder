import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/sms_log_entry.dart';

class SmsLogItem extends StatelessWidget {
  final SmsLogEntry entry;
  const SmsLogItem({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(entry.level);
    final icon = _iconFor(entry.level);
    final ts = DateFormat('HH:mm:ss').format(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s8,
        vertical: AppTheme.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: AppTheme.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      ts,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                    if (entry.smsId != null) ...[
                      const SizedBox(width: 6),
                      Text('·',
                          style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4))),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          entry.smsId!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(SmsLogLevel level) {
    switch (level) {
      case SmsLogLevel.success:
        return AppTheme.logSuccess;
      case SmsLogLevel.warning:
        return AppTheme.logWarning;
      case SmsLogLevel.error:
        return AppTheme.logError;
      case SmsLogLevel.info:
        return AppTheme.logInfo;
    }
  }

  static IconData _iconFor(SmsLogLevel level) {
    switch (level) {
      case SmsLogLevel.success:
        return Icons.check_rounded;
      case SmsLogLevel.warning:
        return Icons.warning_amber_rounded;
      case SmsLogLevel.error:
        return Icons.error_outline_rounded;
      case SmsLogLevel.info:
        return Icons.info_outline_rounded;
    }
  }
}
