import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../auth/auth_controller.dart';
import 'data/rider_repository.dart';
import 'models/rider.dart';

/// Rider view: this month's performance vs target, and comparison
/// against the other riders.
class PerformancePage extends StatefulWidget {
  const PerformancePage({super.key});

  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  final _repo = RiderRepository();

  List<RiderSummary> _riders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final riders = await _repo.fetchRiderSummaries();
      riders.sort((a, b) => b.deliveredCount.compareTo(a.deliveredCount));
      if (!mounted) return;
      setState(() {
        _riders = riders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_riders.isEmpty) {
      return const Center(
        child: Text(
          'No performance data yet.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final myId = context
        .read<AuthController>()
        .user
        ?.id;
    final maxCount = _riders
        .map((r) => r.deliveredCount)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'This month',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        for (final rider in _riders) ...[
          _riderCard(rider, maxCount, isMe: rider.id == myId),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _riderCard(RiderSummary rider, int maxCount, {required bool isMe}) {
    final rank = _riders.indexOf(rider) + 1;
    final isTop = rank == 1;
    final progress = (rider.deliveredCount / maxCount).clamp(0.0, 1.0);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMe
            ? const BorderSide(color: AppColors.accent, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      (isTop ? AppColors.accent : AppColors.primary)
                          .withValues(alpha: 0.12),
                  foregroundColor: isTop ? AppColors.accent : AppColors.primary,
                  child: Text(
                    '$rank',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe ? '${rider.fullName} (you)' : rider.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: isMe ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        [
                          rider.branchName ?? '',
                          '${rider.deliveredCount} deliveries',
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isTop)
                  const Icon(Icons.emoji_events, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  AppFormatters.kes(rider.deliveredAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: isTop ? AppColors.accent : AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              rider.targetDeliveries > 0
                  ? 'Target: ${rider.targetDeliveries} deliveries · '
                      '${AppFormatters.kes(rider.targetAmount)}'
                  : 'No target set',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
