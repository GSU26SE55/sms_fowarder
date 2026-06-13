import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/sms_log_entry.dart';
import '../controllers/sms_gateway_controller.dart';
import '../widgets/sms_log_item.dart';

class GatewayLogsPage extends StatefulWidget {
  const GatewayLogsPage({super.key});

  @override
  State<GatewayLogsPage> createState() => _GatewayLogsPageState();
}

class _GatewayLogsPageState extends State<GatewayLogsPage> {
  SmsLogLevel? _filter;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SmsGatewayController>();
    final logs = _filter == null
        ? controller.logs
        : controller.logs.where((e) => e.level == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Activity logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear logs',
            onPressed: controller.logs.isEmpty
                ? null
                : () => _confirmClear(context, controller),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.s16, 0, AppTheme.s16, AppTheme.s8,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    icon: Icons.list_rounded,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                    count: controller.logs.length,
                  ),
                  const SizedBox(width: AppTheme.s8),
                  _FilterChip(
                    label: 'Sent',
                    icon: Icons.check_rounded,
                    color: AppTheme.logSuccess,
                    selected: _filter == SmsLogLevel.success,
                    onTap: () => setState(() => _filter = SmsLogLevel.success),
                    count: controller.logs
                        .where((e) => e.level == SmsLogLevel.success)
                        .length,
                  ),
                  const SizedBox(width: AppTheme.s8),
                  _FilterChip(
                    label: 'Failed',
                    icon: Icons.error_outline_rounded,
                    color: AppTheme.logError,
                    selected: _filter == SmsLogLevel.error,
                    onTap: () => setState(() => _filter = SmsLogLevel.error),
                    count: controller.logs
                        .where((e) => e.level == SmsLogLevel.error)
                        .length,
                  ),
                  const SizedBox(width: AppTheme.s8),
                  _FilterChip(
                    label: 'Warnings',
                    icon: Icons.warning_amber_rounded,
                    color: AppTheme.logWarning,
                    selected: _filter == SmsLogLevel.warning,
                    onTap: () => setState(() => _filter = SmsLogLevel.warning),
                    count: controller.logs
                        .where((e) => e.level == SmsLogLevel.warning)
                        .length,
                  ),
                  const SizedBox(width: AppTheme.s8),
                  _FilterChip(
                    label: 'Info',
                    icon: Icons.info_outline_rounded,
                    color: AppTheme.logInfo,
                    selected: _filter == SmsLogLevel.info,
                    onTap: () => setState(() => _filter = SmsLogLevel.info),
                    count: controller.logs
                        .where((e) => e.level == SmsLogLevel.info)
                        .length,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? EmptyState(
                    icon: _filter == null
                        ? Icons.history_toggle_off_rounded
                        : Icons.filter_alt_off_rounded,
                    title: _filter == null
                        ? 'No activity yet'
                        : 'No matching logs',
                    message: _filter == null
                        ? 'Logs from polling and SMS sends will appear here.'
                        : 'Try another filter to see more entries.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.s16, 0, AppTheme.s16, AppTheme.s24,
                    ),
                    itemBuilder: (context, i) {
                      final entry = logs[i];
                      return Card(
                        child: SmsLogItem(entry: entry),
                      );
                    },
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTheme.s8),
                    itemCount: logs.length,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    SmsGatewayController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        title: const Text('Clear all logs?'),
        content: const Text('This only affects logs shown in the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.logError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) controller.clearLogs();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final int count;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final bg = selected ? accent : theme.colorScheme.surface;
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    final border = selected
        ? accent
        : theme.colorScheme.onSurface.withValues(alpha: 0.12);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
