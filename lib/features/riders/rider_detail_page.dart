import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/rider_repository.dart';
import 'models/rider.dart';
import 'rider_form_page.dart';

/// Admin: single rider's stats + set/edit the monthly target.
class RiderDetailPage extends StatefulWidget {
  const RiderDetailPage({super.key, required this.rider});

  final RiderSummary rider;

  @override
  State<RiderDetailPage> createState() => _RiderDetailPageState();
}

class _RiderDetailPageState extends State<RiderDetailPage> {
  final _repo = RiderRepository();
  final _targetsCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _targetsCtrl.text = widget.rider.targetDeliveries.toString();
    _amountCtrl.text = widget.rider.targetAmount == 0
        ? ''
        : widget.rider.targetAmount.toStringAsFixed(0);
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    try {
      final results = await Future.wait([
        _repo.fetchBranches(),
        _repo.fetchTemporaryAssignments(widget.rider.id),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0];
        _assignments = results[1];
      });
    } catch (_) {}
  }

  Future<void> _editRider() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RiderFormPage(rider: widget.rider)),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _assignTemporaryBranch() async {
    if (_branches.isEmpty) return;
    String? branchId;
    DateTime startsOn = DateTime.now();
    DateTime endsOn = DateTime.now().add(const Duration(days: 7));
    final noteCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Temporary branch assignment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final branch in _branches)
                    DropdownMenuItem(
                      value: branch['id'] as String,
                      child: Text(branch['name'] as String),
                    ),
                ],
                onChanged: (value) => setDialogState(() => branchId = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startsOn,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDialogState(() => startsOn = picked);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text('Starts ${AppFormatters.date(startsOn)}'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: endsOn,
                    firstDate: startsOn,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDialogState(() => endsOn = picked);
                },
                icon: const Icon(Icons.event_available_outlined),
                label: Text('Ends ${AppFormatters.date(endsOn)}'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: branchId == null
                  ? null
                  : () async {
                      try {
                        await _repo.assignTemporaryBranch(
                          riderId: widget.rider.id,
                          branchId: branchId!,
                          startsOn: startsOn,
                          endsOn: endsOn,
                          note: noteCtrl.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(
                            dialogContext,
                          ).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    noteCtrl.dispose();
    if (saved == true) _loadAssignments();
  }

  @override
  void dispose() {
    _targetsCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String get _month {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
  }

  Future<void> _saveTarget() async {
    final deliveries = int.tryParse(_targetsCtrl.text.trim());
    final amount = double.tryParse(_amountCtrl.text.trim());

    if (deliveries == null || deliveries < 0) {
      setState(() => _error = 'Enter a valid target deliveries number.');
      return;
    }
    if (amount == null || amount < 0) {
      setState(() => _error = 'Enter a valid target amount.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _repo.setTarget(
        riderId: widget.rider.id,
        month: _month,
        targetDeliveries: deliveries,
        targetAmount: amount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target saved for this month')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = widget.rider;
    return Scaffold(
      appBar: AppBar(
        title: Text(rider.fullName),
        actions: [
          IconButton(
            tooltip: 'Edit rider',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editRider,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    foregroundColor: AppColors.primary,
                    child: Text(
                      rider.initials,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rider.fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            rider.branchName ?? 'No branch',
                            rider.phone ?? '',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Temporary branch assignments',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Assign temporary branch',
                        onPressed: _assignTemporaryBranch,
                        icon: const Icon(Icons.add_business_outlined),
                      ),
                    ],
                  ),
                  if (_assignments.isEmpty)
                    const Text(
                      'No temporary assignments.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    for (final assignment in _assignments.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (assignment['branches'] as Map?)?['name']
                                  as String? ??
                              'Branch',
                        ),
                        subtitle: Text(
                          '${assignment['starts_on']} to ${assignment['ends_on']}'
                          '${assignment['note'] != null ? ' · ${assignment['note']}' : ''}',
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'Delivered',
                  '${rider.deliveredCount}',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  'Value',
                  AppFormatters.kes(rider.deliveredAmount),
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  'Pending',
                  '${rider.pendingCount}',
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_outlined, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'Monthly target',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        _month,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _targetsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Target deliveries',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Target amount KSh',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _saveTarget,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save target'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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
