import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../inventory/models/product.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';
import 'order_form_page.dart';
import 'stock_init_page.dart';

/// Stock levels: per branch (or all branches combined) — type totals,
/// refill/cylinder breakdowns by size, accessory & service quantities,
/// low-stock flags, monthly init and ordering.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final _repo = StockRepository();

  List<Map<String, dynamic>> _branches = [];
  String? _branchId; // null = All branches
  List<StockItem> _stock = [];
  Map<String, int> _totals = {};
  Map<String, int> _sizeTotals = {};
  bool _loading = true;
  String? _error;

  bool get _isAll => _branchId == null;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stock = await _repo.fetchStock(branchId: _branchId);
      final totals = await _repo.fetchBranchTypeTotals(branchId: _branchId);
      final sizeTotals = await _repo.fetchSizeTotals(branchId: _branchId);
      if (!mounted) return;
      setState(() {
        _stock = _isAll ? _aggregateAll(stock) : stock;
        _totals = totals;
        _sizeTotals = sizeTotals;
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

  /// Combine per-branch rows into one row per product (All branches view).
  List<StockItem> _aggregateAll(List<StockItem> rows) {
    final map = <String, StockItem>{};
    for (final r in rows) {
      final existing = map[r.productId];
      final qty = (existing?.quantity ?? 0) + r.quantity;
      map[r.productId] = StockItem(
        branchId: '',
        branchName: 'All branches',
        productId: r.productId,
        productName: r.productName,
        productType: r.productType,
        quantity: qty,
        lowStockThreshold: r.lowStockThreshold,
        isLow: qty <= r.lowStockThreshold,
      );
    }
    final list = map.values.toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));
    return list;
  }

  String get _branchName {
    if (_isAll) return 'All branches';
    return _branches
            .where((b) => b['id'] == _branchId)
            .map((b) => b['name'] as String)
            .firstOrNull ??
        '';
  }

  int get _lowCount => _stock.where((s) => s.isLow).length;

  Future<void> _openInit() async {
    if (_branchId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockReconciliationPage(
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
                    child: DropdownButtonFormField<String?>(
                      initialValue: _branchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        isDense: true,
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
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
                onPressed: _branchId == null ? null : _openInit,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Init stock'),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.extended(
                heroTag: 'place-order',
                onPressed: _branchId == null ? null : _openOrder,
                backgroundColor: AppColors.accent,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Place order'),
              ),
            ],
          ),
        ),
        if (_isAll)
          Positioned(
            left: 16,
            bottom: 24,
            child: Text(
              'Select a branch to init stock or place orders',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
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
          if (_stock.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No stock initialized yet.\n'
                'Pick a branch and tap "Init stock" to set opening '
                'quantities.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (_lowCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_lowCount product(s) low on stock — place an order.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _summaryCards(),
          const SizedBox(height: 14),
          _sizeBreakdown(
            'Refills by size',
            ProductType.refill,
            AppColors.primary,
          ),
          const SizedBox(height: 14),
          _sizeBreakdown(
            'Cylinders by size',
            ProductType.cylinder,
            AppColors.primary,
          ),
          const SizedBox(height: 14),
          _accessoriesCard(),
          const SizedBox(height: 14),
          if (_stock.isNotEmpty) ...[
            const Text(
              'All products',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in _stock) ...[
              _stockRow(item),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _summaryCards() {
    final refills = _totals['refill'] ?? 0;
    final cylinders = _totals['cylinder'] ?? 0;
    final accessories = _totals['accessory'] ?? 0;
    final services = _totals['service'] ?? 0;
    final totalUnits =
        _stock.fold<int>(0, (sum, s) => sum + s.quantity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stock summary',
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
                'Total units',
                '$totalUnits',
                AppColors.primary,
                Icons.inventory_2_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sizeBreakdown(String title, ProductType type, Color color) {
    final items = <(String, int)>[];
    for (final size in Product.refillSizes) {
      final key = '${type.name}|$size';
      items.add((Product.formatSizeKg(size), _sizeTotals[key] ?? 0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, qty) in items)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (qty > 0 ? color : AppColors.border)
                      .withValues(alpha: qty > 0 ? 0.12 : 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: qty > 0
                        ? color.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$qty',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: qty > 0 ? color : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _accessoriesCard() {
    final accessories =
        _stock.where((s) => s.productType == ProductType.accessory).toList();
    final services =
        _stock.where((s) => s.productType == ProductType.service).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accessories & services',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (accessories.isEmpty && services.isEmpty)
          const Text(
            'None in stock yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in accessories)
                _accessoryChip(a.productName, a.quantity, AppColors.textPrimary),
              for (final s in services)
                _accessoryChip(s.productName, s.quantity, AppColors.textSecondary),
            ],
          ),
      ],
    );
  }

  Widget _accessoryChip(String name, int qty, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$qty',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
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
