import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/cylinder_repository.dart';
import 'models/cylinder_models.dart';

/// Exchange mismatches (received cylinder ≠ sold refill) for
/// admin/director follow-up.
class ExchangeAlertsPage extends StatefulWidget {
  const ExchangeAlertsPage({super.key});

  @override
  State<ExchangeAlertsPage> createState() => _ExchangeAlertsPageState();
}

class _ExchangeAlertsPageState extends State<ExchangeAlertsPage> {
  final _repo = CylinderRepository();

  List<ExchangeAlert> _alerts = [];
  String _status = 'pending';
  bool _loading = true;
  String? _error;
  String? _busyId;

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
      final alerts = await _repo.fetchAlerts(status: _status);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _resolve(ExchangeAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as resolved?'),
        content: const Text(
          'This confirms you have followed up on the cylinder exchange '
          'mismatch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resolved'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyId = alert.id);
    try {
      await _repo.resolveAlert(alert.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exchange marked as resolved')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final (value, label) in [
                  ('pending', 'Pending'),
                  ('resolved', 'Resolved'),
                ]) ...[
                  if (value != 'pending') const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) {
                      setState(() => _status = value);
                      _load();
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _status == value
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
    );
  }

  Widget _buildBody() {
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
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
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
    if (_alerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _status == 'pending'
                ? 'No exchange mismatches pending. 🎉\n\nMismatches are '
                    'flagged automatically when a customer returns a '
                    'cylinder of a different brand/size than the refill '
                    'sold.'
                : 'Nothing resolved yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _alertCard(_alerts[i]),
    );
  }

  Widget _alertCard(ExchangeAlert alert) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: alert.isPending
            ? const BorderSide(color: AppColors.warning, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  alert.isPending
                      ? Icons.flag_outlined
                      : Icons.check_circle_outline,
                  color:
                      alert.isPending ? AppColors.warning : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.invoiceNo ?? 'Exchange',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (!alert.isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'RESOLVED',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Sold: ${alert.soldProductName ?? '—'}\n'
                'Received: ${alert.receivedProductName ?? '—'}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (alert.customerName != null)
                  _meta(Icons.person_outline, alert.customerName!),
                if (alert.branchName != null)
                  _meta(Icons.storefront_outlined, alert.branchName!),
                if (alert.createdAt != null)
                  _meta(Icons.schedule, AppFormatters.dateTime(alert.createdAt!)),
              ],
            ),
            if (alert.note != null && alert.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                alert.note!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            if (alert.isPending) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _busyId == alert.id ? null : () => _resolve(alert),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  ),
                  icon: _busyId == alert.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Mark resolved'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
