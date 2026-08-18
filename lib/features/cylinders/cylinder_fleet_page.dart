import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'cylinder_movements_page.dart';
import 'data/fleet_repository.dart';
import 'models/fleet_models.dart';

/// Cylinder fleet per branch: full (refill) + empty + out with customers
/// = total physical cylinders, per brand & size.
class CylinderFleetPage extends StatefulWidget {
  const CylinderFleetPage({super.key});

  @override
  State<CylinderFleetPage> createState() => _CylinderFleetPageState();
}

class _CylinderFleetPageState extends State<CylinderFleetPage> {
  final _repo = FleetRepository();

  List<Map<String, dynamic>> _branches = [];
  String? _branchId; // null = all branches
  List<FleetRow> _fleet = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await _repo.fetchBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branches.isEmpty ? null : branches.first['id'] as String;
        _loading = false;
      });
      if (_branchId != null) _loadFleet();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadFleet() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fleet = await _repo.fetchFleet(branchId: _branchId);
      if (!mounted) return;
      setState(() {
        _fleet = fleet;
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

  int get _totalFull => _fleet.fold<int>(0, (s, r) => s + r.fullQty);
  int get _totalEmpty => _fleet.fold<int>(0, (s, r) => s + r.emptyQty);
  int get _totalOut => _fleet.fold<int>(0, (s, r) => s + r.outQty);
  int get _grandTotal => _fleet.fold<int>(0, (s, r) => s + r.totalQty);

  Future<void> _openMovements() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CylinderMovementsPage(branchId: _branchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Branch',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All branches'),
                ),
                for (final b in _branches)
                  DropdownMenuItem<String?>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String),
                  ),
              ],
                onChanged: (v) {
                  setState(() => _branchId = v);
                  _loadFleet();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Movement history',
              icon: const Icon(Icons.history),
              onPressed: _openMovements,
            ),
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
                onPressed: _loadFleet,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFleet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Physical cylinders',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _stat('Full (refill)',
                            '$_totalFull', AppColors.primary),
                      ),
                      Expanded(
                        child: _stat('Empty',
                            '$_totalEmpty', AppColors.textPrimary),
                      ),
                      Expanded(
                        child: _stat('With customers',
                            '$_totalOut', AppColors.warning),
                      ),
                      Expanded(
                        child: _stat('Total',
                            '$_grandTotal', AppColors.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Full + Empty + With customers = Total physical '
                    'cylinders of each brand & size.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_fleet.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No cylinder fleet data yet.\nInit stock to start tracking '
                'your physical cylinders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final row in _fleet) ...[
              _fleetCard(row),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _fleetCard(FleetRow row) {
    final hasOut = row.outQty > 0;
    final nothingIn = row.fullQty + row.emptyQty == 0 && !hasOut;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.cyclone,
                size: 20,
                color: nothingIn ? AppColors.textSecondary : AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: nothingIn
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    hasOut
                        ? '$hasOut out with customers — follow up'
                        : 'All cylinders accounted for',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hasOut ? AppColors.warning : AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _count('Full', row.fullQty, AppColors.primary),
            const SizedBox(width: 8),
            _count('Empty', row.emptyQty, AppColors.textPrimary),
            const SizedBox(width: 8),
            _count('Out', row.outQty, AppColors.warning),
            const SizedBox(width: 8),
            _count('Total', row.totalQty, AppColors.accent, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int value, Color color, {bool bold = false}) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: bold ? 17 : 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
