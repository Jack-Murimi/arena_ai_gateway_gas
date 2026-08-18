import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/fleet_repository.dart';
import 'models/fleet_models.dart';

/// History of every change to refill/cylinder stock, so problems are
/// traceable (who/what/why/when).
class CylinderMovementsPage extends StatefulWidget {
  const CylinderMovementsPage({super.key, this.branchId});

  final String? branchId;

  @override
  State<CylinderMovementsPage> createState() => _CylinderMovementsPageState();
}

class _CylinderMovementsPageState extends State<CylinderMovementsPage> {
  final _repo = FleetRepository();

  List<CylinderMovement> _movements = [];
  String? _typeFilter;
  bool _loading = true;
  String? _error;

  static const _types = [
    'sale',
    'return',
    'purchase',
    'adjustment',
    'opening',
  ];

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
      final movements = await _repo.fetchMovements(
        branchId: widget.branchId,
        movementType: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cylinder movement history')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _typeFilter == null,
                  onSelected: (_) {
                    setState(() => _typeFilter = null);
                    _load();
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _typeFilter == null
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                ),
                for (final t in _types) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(t),
                    selected: _typeFilter == t,
                    onSelected: (_) {
                      setState(() => _typeFilter = t);
                      _load();
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _typeFilter == t
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
      ),
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
    if (_movements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No cylinder movements yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _movements.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _movementRow(_movements[i]),
    );
  }

  Widget _movementRow(CylinderMovement m) {
    final color = m.isPositive ? AppColors.success : AppColors.danger;
    final typeColor = switch (m.movementType) {
      'sale' => AppColors.primary,
      'return' => AppColors.success,
      'purchase' => AppColors.accent,
      'opening' => AppColors.textSecondary,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              m.movementType ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: typeColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.productName ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  [
                    m.branchName ?? '',
                    if (m.createdAt != null)
                      AppFormatters.dateTime(m.createdAt!),
                    if (m.note != null && m.note!.isNotEmpty) m.note!,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${m.isPositive ? '+' : ''}${m.quantityChange}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
