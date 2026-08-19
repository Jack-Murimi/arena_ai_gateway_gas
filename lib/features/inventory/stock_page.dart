import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../inventory/models/product.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';
import 'order_form_page.dart';
import 'stock_init_page.dart';

/// Stock levels per branch (or all branches): cylinders grouped by size
/// showing which brands have gas (refills) and which are empty, plus a
/// total-cylinders summary at the bottom. Accessories & services listed
/// separately.
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
        _error = e.toString().replaceAll('Exception: ', '');
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
      if (!mounted) return;
      setState(() {
        _stock = _isAll ? _aggregateAll(stock) : stock;
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
        brand: r.brand,
        sizeKg: r.sizeKg,
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

  // -------------------------------------------------------------------------
  // Grouping
  // -------------------------------------------------------------------------

  List<StockItem> get _cylinders => _stock
      .where((s) =>
          s.productType == ProductType.refill ||
          s.productType == ProductType.cylinder)
      .toList();

  List<StockItem> get _accessories => _stock
      .where((s) => s.productType == ProductType.accessory)
      .toList();

  List<StockItem> get _services =>
      _stock.where((s) => s.productType == ProductType.service).toList();

  /// Sizes present, sorted (3, 6, 13, 22.5, ...).
  List<double?> get _sizes {
    final set = <double>{};
    for (final s in _cylinders) {
      if (s.sizeKg != null) set.add(s.sizeKg!);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<StockItem> _gasFor(double? size) => _cylinders
      .where((s) =>
          s.productType == ProductType.refill && s.sizeKg == size)
      .toList()
    ..sort((a, b) => (a.brand ?? a.productName)
        .toLowerCase()
        .compareTo((b.brand ?? b.productName).toLowerCase()));

  List<StockItem> _emptyFor(double? size) => _cylinders
      .where((s) =>
          s.productType == ProductType.cylinder && s.sizeKg == size)
      .toList()
    ..sort((a, b) => (a.brand ?? a.productName)
        .toLowerCase()
        .compareTo((b.brand ?? b.productName).toLowerCase()));

  int _gasQty(double? size) =>
      _gasFor(size).fold<int>(0, (sum, s) => sum + s.quantity);
  int _emptyQty(double? size) =>
      _emptyFor(size).fold<int>(0, (sum, s) => sum + s.quantity);

  int get _totalGas => _cylinders
      .where((s) => s.productType == ProductType.refill)
      .fold<int>(0, (sum, s) => sum + s.quantity);
  int get _totalEmpty => _cylinders
      .where((s) => s.productType == ProductType.cylinder)
      .fold<int>(0, (sum, s) => sum + s.quantity);
  int get _totalCylinders => _totalGas + _totalEmpty;
  int get _lowCount => _stock.where((s) => s.isLow).length;

  static String _sizeLabel(double? size) => size == null
      ? ''
      : (size == size.roundToDouble()
          ? '${size.toInt()}kg'
          : '${size}kg');

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _openReconcile() async {
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
                heroTag: 'reconcile-stock',
                onPressed: _branchId == null ? null : _openReconcile,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Reconcile stock'),
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
              'Select a branch to reconcile or order',
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
                'No stock recorded yet.\n'
                'Pick a branch and tap "Reconcile stock" to enter your '
                'counted quantities.',
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
          if (_cylinders.isNotEmpty) ...[
            const Text(
              'Cylinders by size',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Refills are cylinders with gas; empties are cylinders '
              'without gas.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final size in _sizes) ...[
              _sizeCard(size),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            _totalCylindersCard(),
            const SizedBox(height: 14),
          ],
          if (_accessories.isNotEmpty || _services.isNotEmpty) ...[
            _accessoriesCard(),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _summaryCards() {
    return Row(
      children: [
        Expanded(
          child: _totalCard(
            'With gas',
            '$_totalGas',
            AppColors.primary,
            Icons.local_fire_department,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _totalCard(
            'Empty',
            '$_totalEmpty',
            AppColors.textPrimary,
            Icons.propane_tank_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _totalCard(
            'Total cylinders',
            '$_totalCylinders',
            AppColors.accent,
            Icons.cyclone,
          ),
        ),
      ],
    );
  }

  /// One size: which brands have gas + which are empty, with subtotals.
  Widget _sizeCard(double? size) {
    final gas = _gasFor(size);
    final empty = _emptyFor(size);
    final gasQty = _gasQty(size);
    final emptyQty = _emptyQty(size);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _sizeLabel(size),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${gasQty + emptyQty} total',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            if (gas.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'WITH GAS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final g in gas)
                _brandLine(g.brand ?? g.productName, g.quantity),
              _subtotalLine('Gas subtotal', gasQty, AppColors.primary),
            ],
            if (empty.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'EMPTY',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final e in empty)
                _brandLine(e.brand ?? e.productName, e.quantity),
              _subtotalLine('Empty subtotal', emptyQty, AppColors.textPrimary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _brandLine(String brand, int qty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 4),
          const Icon(Icons.radio_button_unchecked,
              size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              brand,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          Text(
            '$qty',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtotalLine(String label, int qty, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '( $qty )',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom summary: total cylinders per size + grand total.
  Widget _totalCylindersCard() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.accent, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TOTAL CYLINDERS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 6),
            for (final size in _sizes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sizeLabel(size),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                    Text(
                      '${_gasQty(size) + _emptyQty(size)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$_totalCylinders',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessoriesCard() {
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _accessories)
              _accessoryChip(
                  a.brand ?? a.productName, a.quantity, AppColors.textPrimary),
            for (final s in _services)
              _accessoryChip(
                  s.brand ?? s.productName, s.quantity, AppColors.textSecondary),
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
}
