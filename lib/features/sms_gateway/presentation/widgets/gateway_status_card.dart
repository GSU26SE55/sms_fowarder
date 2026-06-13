import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/animated_status_dot.dart';
import '../../data/datasources/sms_gateway_realtime_datasource.dart';
import '../controllers/sms_gateway_controller.dart';

/// Hero header trên Home — gradient theo trạng thái, label lớn, last-poll line,
/// kèm chip realtime để user biết đang chạy push (SignalR) hay polling-only.
class GatewayHeroHeader extends StatelessWidget {
  const GatewayHeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SmsGatewayController>();
    final gradient = _gradientFor(controller.status);
    final dotColor = _dotColorFor(controller.status);
    final label = _labelFor(controller.status);
    final lastPoll = controller.lastPollAt;
    final lastPollText = lastPoll == null
        ? 'Waiting for first poll…'
        : 'Last poll · ${DateFormat('HH:mm:ss').format(lastPoll)}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        boxShadow: [
          BoxShadow(
            color: dotColor.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedStatusDot(
                  color: Colors.white,
                  pulsing: controller.status == GatewayStatus.running ||
                      controller.status == GatewayStatus.starting,
                ),
                const SizedBox(width: AppTheme.s8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (controller.isRunning)
                  _RealtimeChip(
                    state: controller.realtimeState,
                    pollInterval: controller.activePollInterval,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.s16),
            Text(
              controller.statusMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppTheme.s12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lastPollText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Gradient _gradientFor(GatewayStatus status) {
    switch (status) {
      case GatewayStatus.running:
        return AppTheme.runningGradient;
      case GatewayStatus.starting:
        return AppTheme.startingGradient;
      case GatewayStatus.errored:
        return AppTheme.erroredGradient;
      case GatewayStatus.stopped:
        return AppTheme.stoppedGradient;
    }
  }

  static Color _dotColorFor(GatewayStatus status) {
    switch (status) {
      case GatewayStatus.running:
        return AppTheme.statusRunning;
      case GatewayStatus.starting:
        return AppTheme.statusStarting;
      case GatewayStatus.errored:
        return AppTheme.statusErrored;
      case GatewayStatus.stopped:
        return AppTheme.statusStopped;
    }
  }

  static String _labelFor(GatewayStatus status) {
    switch (status) {
      case GatewayStatus.running:
        return 'RUNNING';
      case GatewayStatus.starting:
        return 'STARTING';
      case GatewayStatus.errored:
        return 'ERROR';
      case GatewayStatus.stopped:
        return 'STOPPED';
    }
  }
}

class _RealtimeChip extends StatelessWidget {
  final RealtimeConnectionState state;
  final Duration pollInterval;

  const _RealtimeChip({required this.state, required this.pollInterval});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _decor(state, pollInterval);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, String) _decor(
      RealtimeConnectionState s, Duration poll) {
    switch (s) {
      case RealtimeConnectionState.connected:
        return (Icons.bolt_rounded, 'REALTIME');
      case RealtimeConnectionState.connecting:
        return (Icons.sync_rounded, 'CONNECTING');
      case RealtimeConnectionState.reconnecting:
        return (Icons.sync_problem_rounded, 'RECONNECTING');
      case RealtimeConnectionState.failed:
      case RealtimeConnectionState.disconnected:
        return (Icons.cloud_off_rounded, 'POLL ${poll.inSeconds}s');
    }
  }
}
