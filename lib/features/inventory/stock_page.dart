import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';
import 'order_form_page.dart';
import 'stock_init_page.dart';

/// Stock levels per branch: type totals, per-product quantities,
/// low-stock flags, monthly init and ordering.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final _repo = StockRepository();

  List<Map<String, dynamic>> _branches = [];
  String? _branchId;
  List<StockItem> _stock = [];
  Map<String, int> _totals = {};
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
      if (_branchId != null) _loadStock();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadStock() async {
    final branchId = _branchId;
    if (branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stock = await _repo.fetchBranchStock(branchId);
      final totals = await _repo.fetchBranchTypeTotals(branchId);
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _totals = totals;
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

  Future<void> _openInit() async {
    if (_branchId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockInitPage(
          branchId: _branchId!,
          branchName: _branchName,
        ),
      ),
    );
    _loadStock();
  }

  Future<void> _openOrder() async {
    if (_branchId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderFormPage(
          branchId: _branchId!,
          branchName: _branchName,
          lowStockProducts: _stock.where((s) => s.isLow).toList(),
        ),
      ),
    );
  }

  String get _branchName => _branches
          .where((b) => b['id'] == _branchId)
          .map((b) => b['name'] as String)
          .firstOrNull ??
      '';

  int get _lowCount => _stock.where((s) => s.isLow).length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        isDense: true,
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                      ),
                      items: [
                        for (final b in _branches)
                          DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _branchId = v);
                        _loadStock();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'init-stock',
                onPressed: _openInit,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Init stock'),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.extended(
                heroTag: 'place-order',
                onPressed: _openOrder,
                backgroundColor: AppColors.accent,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Place order'),
              ),
            ],
          ),
        ),
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
                onPressed: _loadStock,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStock,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          _totalsRow(),
          const SizedBox(height: 12),
          if (_stock.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No stock initialized for this branch yet.\n'
                'Tap "Init stock" to set opening quantities.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final item in _stock) _stockRow(item),
        ],
      ),
    );
  }

  Widget _totalsRow() {
    final refills = _totals['refill'] ?? 0;
    final cylinders = _totals['cylinder'] ?? 0;
    final accessories = _totals['accessory'] ?? 0;
    final services = _totals['service'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stock by type',
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
              child: _totalCard(
                'Refills',
                '$refills',
                AppColors.primary,
                Icons.local_fire_department,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _totalCard(
                'Cylinders',
                '$cylinders',
                AppColors.primary,
                Icons.propane_tank_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _totalCard(
                'Refill+Cyl',
                '${refills + cylinders}',
                AppColors.accent,
                Icons.cyclone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _totalCard(
                'Accessories',
                '$accessories',
                AppColors.textPrimary,
                Icons.extension_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _totalCard(
                'Services',
                '$services',
                AppColors.textPrimary,
                Icons.handyman_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _totalCard(
                'Low stock',
                '$_lowCount',
                _lowCount > 0 ? AppColors.danger : AppColors.success,
                Icons.priority_high_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _totalCard(String label, String value, Color color, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockRow(StockItem item) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              item.productType.icon,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    item.productType.label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (item.isLow)
              const Tooltip(
                message: 'Low stock',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (item.isLow ? AppColors.danger : AppColors.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${item.quantity}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: item.isLow ? AppColors.danger : AppColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
