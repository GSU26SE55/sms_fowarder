import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/permissions/sms_permission_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../controllers/gateway_settings_controller.dart';
import '../controllers/sms_gateway_controller.dart';
import '../widgets/gateway_status_card.dart';
import '../widgets/sms_log_item.dart';
import 'gateway_logs_page.dart';
import 'gateway_settings_page.dart';

class GatewayHomePage extends StatefulWidget {
  const GatewayHomePage({super.key});

  @override
  State<GatewayHomePage> createState() => _GatewayHomePageState();
}

class _GatewayHomePageState extends State<GatewayHomePage> {
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final settings = context.read<GatewaySettingsController>();
      final controller = context.read<SmsGatewayController>();
      await settings.load();
      if (!mounted) return;
      setState(() => _bootstrapped = true);
      if (settings.config.autoStart && settings.config.isComplete) {
        await controller.start();
      }
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GatewaySettingsPage()),
    );
  }

  Future<void> _openLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GatewayLogsPage()),
    );
  }

  Future<void> _toggleGateway() async {
    final controller = context.read<SmsGatewayController>();
    final permissionService = context.read<SmsPermissionService>();
    final settings = context.read<GatewaySettingsController>();

    if (controller.isRunning) {
      await controller.stop();
      return;
    }

    if (!settings.config.isComplete) {
      _snack('Please configure backend URL and token first', icon: Icons.settings_outlined);
      return;
    }

    final hasPermission = await permissionService.hasSmsPermission();
    if (!hasPermission) {
      final granted = await permissionService.requestSmsPermission();
      if (!granted) {
        if (!mounted) return;
        await _showPermissionDialog();
        return;
      }
    }

    await controller.start();
  }

  void _snack(String message, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _showPermissionDialog() async {
    final permissionService = context.read<SmsPermissionService>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.sms_outlined,
              color: Theme.of(ctx).colorScheme.primary, size: 28),
        ),
        title: const Text('SMS permission required'),
        content: const Text(
          'This app needs the SEND_SMS permission to forward queued messages '
          'through your SIM. Please grant it from app settings.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open settings'),
            onPressed: () async {
              await permissionService.openSettings();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SmsGatewayController>();
    final settings = context.watch<GatewaySettingsController>();
    final theme = Theme.of(context);

    if (!_bootstrapped) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isConfigured = settings.config.isComplete;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Gateway'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Logs',
            onPressed: _openLogs,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !isConfigured
            ? _WelcomeBody(onConfigure: _openSettings)
            : RefreshIndicator(
                onRefresh: () async {
                  if (controller.isRunning) {
                    await controller.processPendingMessages();
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.s16, AppTheme.s8, AppTheme.s16, AppTheme.s24,
                  ),
                  children: [
                    const GatewayHeroHeader(),
                    const SizedBox(height: AppTheme.s16),
                    _StatsRow(controller: controller),
                    const SizedBox(height: AppTheme.s16),
                    AppButton(
                      label: controller.isRunning
                          ? 'Stop gateway'
                          : 'Start gateway',
                      icon: controller.isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      variant: controller.isRunning
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      loading: controller.status == GatewayStatus.starting,
                      onPressed: controller.status == GatewayStatus.starting
                          ? null
                          : _toggleGateway,
                    ),
                    const SizedBox(height: AppTheme.s24),
                    _DeviceInfoCard(
                      backendUrl: settings.config.backendUrl,
                      deviceCode: settings.config.deviceCode,
                      pollingInterval: settings.config.pollingIntervalSeconds,
                    ),
                    const SizedBox(height: AppTheme.s24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent activity',
                          style: theme.textTheme.titleMedium,
                        ),
                        TextButton.icon(
                          onPressed: _openLogs,
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('View all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.s8),
                    _RecentLogs(controller: controller),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final SmsGatewayController controller;
  const _StatsRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.check_circle_outline_rounded,
            accent: AppTheme.statusRunning,
            label: 'Sent',
            value: controller.sentCount.toString(),
          ),
        ),
        const SizedBox(width: AppTheme.s12),
        Expanded(
          child: StatCard(
            icon: Icons.error_outline_rounded,
            accent: AppTheme.statusErrored,
            label: 'Failed',
            value: controller.failedCount.toString(),
          ),
        ),
        const SizedBox(width: AppTheme.s12),
        Expanded(
          child: StatCard(
            icon: Icons.sync_rounded,
            accent: Theme.of(context).colorScheme.primary,
            label: 'Status',
            value: controller.isRunning ? 'On' : 'Off',
          ),
        ),
      ],
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final String backendUrl;
  final String deviceCode;
  final int pollingInterval;

  const _DeviceInfoCard({
    required this.backendUrl,
    required this.deviceCode,
    required this.pollingInterval,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'CONNECTION',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s12),
            _InfoRow(label: 'Backend', value: backendUrl, icon: Icons.cloud_outlined),
            const SizedBox(height: AppTheme.s8),
            _InfoRow(label: 'Device', value: deviceCode, icon: Icons.smartphone_outlined),
            const SizedBox(height: AppTheme.s8),
            _InfoRow(
              label: 'Polling',
              value: 'Every $pollingInterval s',
              icon: Icons.timer_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 10),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentLogs extends StatelessWidget {
  final SmsGatewayController controller;
  const _RecentLogs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final recent = controller.logs.take(8).toList();
    if (recent.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.s32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: AppTheme.s8),
                Text(
                  'No activity yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.s8),
        child: Column(
          children: [
            for (var i = 0; i < recent.length; i++) ...[
              SmsLogItem(entry: recent[i]),
              if (i < recent.length - 1)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.08),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WelcomeBody extends StatelessWidget {
  final VoidCallback onConfigure;
  const _WelcomeBody({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.sms_outlined,
      title: 'Welcome to SMS Gateway',
      message:
          'Configure your backend URL, device code, and gateway token to start '
          'forwarding queued SMS through this phone’s SIM.',
      action: FilledButton.icon(
        onPressed: onConfigure,
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Configure now'),
      ),
    );
  }
}
