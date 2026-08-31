import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'data/stock_repository.dart';
import 'models/product.dart';
import 'models/stock_item.dart';
import 'order_form_page.dart';
import 'products_page.dart';
import 'stock_init_page.dart';
import 'stock_transfers_page.dart';

/// Stock levels & inventory management screen:
/// - Filter by branch or view all branches combined.
/// - On large screens (tablets, desktop, landscape), shows a multi-branch
///   comparison matrix with every branch's stock side by side.
/// - Clear stock status badges (in stock, low stock, out of stock).
/// - Instant search & category filtering.
/// - Cylinder fleet breakdown mode (refills vs empties by size).
/// - Fast actions: stock transfers, reconciliation, purchase ordering.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final _repo = StockRepository();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId; // null = All branches
  List<StockItem> _rawStock = [];
  bool _loading = true;
  String? _error;

  ProductType? _selectedCategory;
  String _statusFilter =
      'all'; // 'all', 'in_stock', 'low_stock', 'out_of_stock'
  String _viewMode =
      'inventory'; // 'inventory' (table/cards) | 'fleet' (by size)
  String _sortBy = 'name'; // 'name', 'qty_desc', 'qty_asc'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isAllBranches => _selectedBranchId == null;

  String get _selectedBranchName {
    if (_isAllBranches) return 'All branches';
    return _branches
            .where((b) => b['id'] == _selectedBranchId)
            .map((b) => b['name'] as String)
            .firstOrNull ??
        'Branch';
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final branches = await _repo.fetchBranches();
      // Fetch all stock records so multi-branch comparison and fast client-side
      // branch switching are instantaneous without refetches.
      final stockRows = await _repo.fetchStock();

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _rawStock = stockRows;
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

  // ---------------------------------------------------------------------------
  // Data Aggregation & Filtering
  // ---------------------------------------------------------------------------

  /// Group all stock rows by product into multi-branch summary rows.
  List<ProductStockRow> get _allProductRows {
    final map = <String, ProductStockRow>{};

    for (final item in _rawStock) {
      final existing = map[item.productId];
      if (existing == null) {
        map[item.productId] = ProductStockRow(
          productId: item.productId,
          productName: item.productName,
          productType: item.productType,
          brand: item.brand,
          sizeKg: item.sizeKg,
          lowStockThreshold: item.lowStockThreshold,
          branchQuantities: {item.branchId: item.quantity},
          branchNames: {item.branchId: item.branchName},
        );
      } else {
        existing.branchQuantities[item.branchId] = item.quantity;
        existing.branchNames[item.branchId] = item.branchName;
      }
    }

    return map.values.toList();
  }

  /// Filtered product rows according to branch, category, search, and status.
  List<ProductStockRow> get _filteredProductRows {
    final query = _searchCtrl.text.trim().toLowerCase();

    return _allProductRows.where((row) {
      // Category filter
      if (_selectedCategory != null && row.productType != _selectedCategory) {
        return false;
      }

      // Search filter
      if (query.isNotEmpty) {
        final nameMatch = row.productName.toLowerCase().contains(query);
        final brandMatch =
            row.brand != null && row.brand!.toLowerCase().contains(query);
        final sizeMatch =
            row.sizeKg != null && '${row.sizeKg}kg'.contains(query);
        if (!nameMatch && !brandMatch && !sizeMatch) return false;
      }

      // Status filter (evaluated against selected branch or company total)
      if (row.productType == ProductType.service && _statusFilter != 'all') {
        return false;
      }
      final qty = row.quantityFor(_selectedBranchId);
      final isOut = qty <= 0;
      final isLow = qty > 0 && qty <= row.lowStockThreshold;
      final isHealthy = qty > row.lowStockThreshold;

      if (_statusFilter == 'in_stock' && !isHealthy) return false;
      if (_statusFilter == 'low_stock' && !isLow) return false;
      if (_statusFilter == 'out_of_stock' && !isOut) return false;

      return true;
    }).toList()..sort((a, b) {
      if (_sortBy == 'qty_desc') {
        return b
            .quantityFor(_selectedBranchId)
            .compareTo(a.quantityFor(_selectedBranchId));
      }
      if (_sortBy == 'qty_asc') {
        return a
            .quantityFor(_selectedBranchId)
            .compareTo(b.quantityFor(_selectedBranchId));
      }
      return a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
    });
  }

  // ---------------------------------------------------------------------------
  // Summary Metrics (for selected branch or all branches combined)
  // ---------------------------------------------------------------------------

  int get _metricGasTotal {
    return _allProductRows
        .where((r) => r.productType == ProductType.refill)
        .fold(0, (sum, r) => sum + r.quantityFor(_selectedBranchId));
  }

  int get _metricEmptyTotal {
    return _allProductRows
        .where((r) => r.productType == ProductType.cylinder)
        .fold(0, (sum, r) => sum + r.quantityFor(_selectedBranchId));
  }

  int get _metricCylindersTotal => _metricGasTotal + _metricEmptyTotal;

  int get _metricAccessoriesTotal {
    return _allProductRows
        .where((r) => r.productType == ProductType.accessory)
        .fold(0, (sum, r) => sum + r.quantityFor(_selectedBranchId));
  }

  int get _metricLowStockCount {
    return _allProductRows
        .where(
          (r) =>
              r.productType != ProductType.service &&
              r.isLowStockFor(_selectedBranchId),
        )
        .length;
  }

  int get _metricOutOfStockCount {
    return _allProductRows
        .where(
          (r) =>
              r.productType != ProductType.service &&
              r.isOutOfStockFor(_selectedBranchId),
        )
        .length;
  }

  int get _metricInStockCount {
    return _allProductRows
        .where(
          (r) =>
              r.productType != ProductType.service &&
              r.isHealthyFor(_selectedBranchId),
        )
        .length;
  }

  // ---------------------------------------------------------------------------
  // Cylinder Fleet Breakdown by Size
  // ---------------------------------------------------------------------------

  List<StockItem> get _activeStockItems {
    if (_isAllBranches) {
      // Aggregate into 1 item per product
      final map = <String, StockItem>{};
      for (final r in _rawStock) {
        final existing = map[r.productId];
        final total = (existing?.quantity ?? 0) + r.quantity;
        map[r.productId] = StockItem(
          branchId: '',
          branchName: 'All branches',
          productId: r.productId,
          productName: r.productName,
          productType: r.productType,
          brand: r.brand,
          sizeKg: r.sizeKg,
          quantity: total,
          lowStockThreshold: r.lowStockThreshold,
          isLow: total <= r.lowStockThreshold,
        );
      }
      return map.values.toList();
    }
    return _rawStock.where((s) => s.branchId == _selectedBranchId).toList();
  }

  List<StockItem> get _fleetCylinders => _activeStockItems
      .where(
        (s) =>
            s.productType == ProductType.refill ||
            s.productType == ProductType.cylinder,
      )
      .toList();

  List<double?> get _cylinderSizes {
    final set = <double>{};
    for (final s in _fleetCylinders) {
      if (s.sizeKg != null) set.add(s.sizeKg!);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<StockItem> _gasForSize(double? size) =>
      _fleetCylinders
          .where((s) => s.productType == ProductType.refill && s.sizeKg == size)
          .toList()
        ..sort(
          (a, b) => (a.brand ?? a.productName).toLowerCase().compareTo(
            (b.brand ?? b.productName).toLowerCase(),
          ),
        );

  List<StockItem> _emptyForSize(double? size) =>
      _fleetCylinders
          .where(
            (s) => s.productType == ProductType.cylinder && s.sizeKg == size,
          )
          .toList()
        ..sort(
          (a, b) => (a.brand ?? a.productName).toLowerCase().compareTo(
            (b.brand ?? b.productName).toLowerCase(),
          ),
        );

  int _gasQtyForSize(double? size) =>
      _gasForSize(size).fold<int>(0, (sum, s) => sum + s.quantity);

  int _emptyQtyForSize(double? size) =>
      _emptyForSize(size).fold<int>(0, (sum, s) => sum + s.quantity);

  static String _sizeLabel(double? size) => size == null
      ? ''
      : (size == size.roundToDouble() ? '${size.toInt()}kg' : '${size}kg');

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleReconcile() async {
    String? branchId = _selectedBranchId;
    String branchName = _selectedBranchName;

    if (branchId == null) {
      // Pick branch dialog
      final picked = await _pickBranchDialog(
        title: 'Reconcile stock',
        subtitle: 'Select which branch stock you are counting:',
      );
      if (picked == null) return;
      branchId = picked['id'] as String;
      branchName = picked['name'] as String;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockReconciliationPage(
          branchId: branchId!,
          branchName: branchName,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _handleOrder() async {
    String? branchId = _selectedBranchId;
    String branchName = _selectedBranchName;

    if (branchId == null) {
      final picked = await _pickBranchDialog(
        title: 'Place purchase order',
        subtitle: 'Select destination branch for the order:',
      );
      if (picked == null) return;
      branchId = picked['id'] as String;
      branchName = picked['name'] as String;
    }

    final lowItems = _rawStock
        .where((s) => s.branchId == branchId && s.isLow)
        .toList();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderFormPage(
          branchId: branchId!,
          branchName: branchName,
          lowStockProducts: lowItems,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _handleTransfers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StockTransfersPage()));
    _loadData();
  }

  Future<void> _openProductCatalogue() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Product catalogue')),
          body: const ProductsPage(),
        ),
      ),
    );
    _loadData();
  }

  Future<Map<String, dynamic>?> _pickBranchDialog({
    required String title,
    required String subtitle,
  }) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            for (final b in _branches)
              ListTile(
                dense: true,
                leading: const Icon(Icons.storefront, color: AppColors.primary),
                title: Text(
                  b['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () => Navigator.of(ctx).pop(b),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 750;

        return Scaffold(
          body: Column(
            children: [
              _buildTopControlsBar(isWide),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _buildErrorView()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _viewMode == 'fleet'
                            ? _buildFleetView(isWide)
                            : _buildInventoryView(isWide),
                      ),
              ),
            ],
          ),
          floatingActionButton: _buildFloatingActions(isWide),
        );
      },
    );
  }

  Widget _buildTopControlsBar(bool isWide) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Branch Filter Chips + View Mode + Quick Catalogue button
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Branch:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _branchFilterChip(
                        id: null,
                        label: isWide
                            ? 'All branches (Matrix)'
                            : 'All branches',
                        selected: _isAllBranches,
                      ),
                      for (final b in _branches) ...[
                        const SizedBox(width: 6),
                        _branchFilterChip(
                          id: b['id'] as String,
                          label: b['name'] as String,
                          selected: _selectedBranchId == b['id'],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // View mode toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _viewToggleButton(
                      mode: 'inventory',
                      icon: Icons.table_chart_outlined,
                      tooltip: isWide
                          ? 'Stock matrix & inventory'
                          : 'Stock inventory',
                    ),
                    _viewToggleButton(
                      mode: 'fleet',
                      icon: Icons.cyclone_outlined,
                      tooltip: 'Cylinder fleet by size',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Product catalogue & prices',
                icon: const Icon(Icons.tune_outlined, size: 20),
                onPressed: _openProductCatalogue,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Search Box + Category Filter Chips
          Row(
            children: [
              Expanded(
                flex: isWide ? 4 : 5,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search products, brands, sizes…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Sort dropdown
              SizedBox(
                height: 38,
                child: DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox.shrink(),
                  icon: const Icon(Icons.sort, size: 18),
                  borderRadius: BorderRadius.circular(8),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name (A-Z)')),
                    DropdownMenuItem(
                      value: 'qty_desc',
                      child: Text('Stock (High-Low)'),
                    ),
                    DropdownMenuItem(
                      value: 'qty_asc',
                      child: Text('Stock (Low-High)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sortBy = val);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 3: Category & Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(null, 'All types'),
                const SizedBox(width: 6),
                _categoryChip(ProductType.refill, 'Refills'),
                const SizedBox(width: 6),
                _categoryChip(ProductType.cylinder, 'Empty Cylinders'),
                const SizedBox(width: 6),
                _categoryChip(ProductType.accessory, 'Accessories'),
                const SizedBox(width: 6),
                _categoryChip(ProductType.service, 'Services'),
                const SizedBox(width: 14),
                Container(height: 18, width: 1, color: AppColors.border),
                const SizedBox(width: 14),
                _statusFilterChip(
                  id: 'all',
                  label: 'All (${_allProductRows.length})',
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                _statusFilterChip(
                  id: 'in_stock',
                  label: 'In stock ($_metricInStockCount)',
                  color: AppColors.success,
                ),
                const SizedBox(width: 6),
                _statusFilterChip(
                  id: 'low_stock',
                  label: 'Low stock ($_metricLowStockCount)',
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                _statusFilterChip(
                  id: 'out_of_stock',
                  label: 'Out of stock ($_metricOutOfStockCount)',
                  color: AppColors.danger,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchFilterChip({
    required String? id,
    required String label,
    required bool selected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _selectedBranchId = id);
      },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _viewToggleButton({
    required String mode,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(ProductType? type, String label) {
    final selected = _selectedCategory == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedCategory = type),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.background,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _statusFilterChip({
    required String id,
    required String label,
    required Color color,
  }) {
    final selected = _statusFilter == id;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = id),
      selectedColor: color.withValues(alpha: 0.18),
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: selected ? color : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: selected ? color : AppColors.border,
        width: selected ? 1.4 : 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ---------------------------------------------------------------------------
  // Summary Metrics Banner
  // ---------------------------------------------------------------------------

  Widget _buildSummaryMetricsRow(bool isWide) {
    final cards = [
      _summaryCard(
        label: 'Gas on hand',
        value: '$_metricGasTotal',
        subtitle: 'Refill cylinders',
        icon: Icons.local_fire_department,
        color: AppColors.primary,
      ),
      _summaryCard(
        label: 'Empty cylinders',
        value: '$_metricEmptyTotal',
        subtitle: 'Awaiting gas',
        icon: Icons.propane_tank_outlined,
        color: AppColors.textPrimary,
      ),
      _summaryCard(
        label: 'Total cylinders',
        value: '$_metricCylindersTotal',
        subtitle: 'Gas + Empty',
        icon: Icons.cyclone,
        color: AppColors.accent,
      ),
      _summaryCard(
        label: 'Accessories',
        value: '$_metricAccessoriesTotal',
        subtitle: 'Fittings, hoses, stoves',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF2563EB),
      ),
      _summaryCard(
        label: 'Low stock',
        value: '$_metricLowStockCount',
        subtitle: 'Order required',
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
      ),
      _summaryCard(
        label: 'Out of stock',
        value: '$_metricOutOfStockCount',
        subtitle: 'Zero quantity',
        icon: Icons.error_outline,
        color: AppColors.danger,
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map(
              (c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: c,
                ),
              ),
            )
            .toList(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: cards
            .map(
              (c) => Container(
                width: 140,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: c,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View 1: Stock Inventory View (Large Screen Matrix vs Mobile Cards)
  // ---------------------------------------------------------------------------

  Widget _buildInventoryView(bool isWide) {
    final rows = _filteredProductRows;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _buildSummaryMetricsRow(isWide),
        const SizedBox(height: 12),

        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off,
                  size: 44,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  _searchCtrl.text.isNotEmpty
                      ? 'No products match "${_searchCtrl.text}".'
                      : 'No products match the selected filters.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else if (isWide && _isAllBranches)
          // Highlight feature: Multi-branch comparison matrix for large screens
          _buildLargeScreenMultiBranchMatrix(rows)
        else if (isWide)
          // Large screen single-branch focused table
          _buildLargeScreenSingleBranchTable(rows)
        else
          // Mobile / compact card-based stock list
          _buildCompactStockCards(rows),
      ],
    );
  }

  /// Multi-Branch Matrix: Columns for every branch side-by-side + Total
  Widget _buildLargeScreenMultiBranchMatrix(List<ProductStockRow> rows) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 700),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                AppColors.primary.withValues(alpha: 0.06),
              ),
              headingRowHeight: 44,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 56,
              columnSpacing: 20,
              columns: [
                const DataColumn(
                  label: Text(
                    'PRODUCT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'TYPE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Dynamic columns for every branch in the system
                for (final branch in _branches)
                  DataColumn(
                    numeric: true,
                    label: Text(
                      (branch['name'] as String).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                const DataColumn(
                  numeric: true,
                  label: Text(
                    'TOTAL STOCK',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'ACTION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
              rows: rows.map((row) {
                final total = row.totalQuantity;
                final isOut = total <= 0;
                final isLow = total > 0 && total <= row.lowStockThreshold;

                return DataRow(
                  cells: [
                    // Product name & size
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            row.productType.icon,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (row.brand != null || row.sizeKg != null)
                                Text(
                                  [
                                    if (row.brand != null) row.brand,
                                    if (row.sizeKg != null)
                                      _sizeLabel(row.sizeKg),
                                  ].join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Type chip
                    DataCell(_typeBadge(row.productType)),

                    // Per-branch quantities
                    for (final branch in _branches)
                      DataCell(
                        row.productType == ProductType.service
                            ? const Text('—')
                            : _branchStockCell(
                                qty: row.branchQuantities[branch['id']] ?? 0,
                                threshold: row.lowStockThreshold,
                              ),
                      ),

                    // Total stock
                    DataCell(
                      row.productType == ProductType.service
                          ? const Text(
                              'Service',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isOut
                                    ? AppColors.danger.withValues(alpha: 0.12)
                                    : isLow
                                    ? AppColors.warning.withValues(alpha: 0.14)
                                    : AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '$total',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: isOut
                                      ? AppColors.danger
                                      : isLow
                                      ? AppColors.warning
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                    ),

                    // Status
                    DataCell(
                      row.productType == ProductType.service
                          ? _serviceBadge()
                          : _statusBadge(isOut: isOut, isLow: isLow),
                    ),

                    // Action
                    DataCell(
                      TextButton.icon(
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Transfer'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: _handleTransfers,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Large screen table when a single branch is selected
  Widget _buildLargeScreenSingleBranchTable(List<ProductStockRow> rows) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 700),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                AppColors.primary.withValues(alpha: 0.06),
              ),
              headingRowHeight: 44,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 56,
              columnSpacing: 24,
              columns: [
                const DataColumn(
                  label: Text(
                    'PRODUCT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'TYPE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                DataColumn(
                  numeric: true,
                  label: Text(
                    '$_selectedBranchName STOCK',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const DataColumn(
                  numeric: true,
                  label: Text(
                    'MIN ALERT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'STATUS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'ACTION',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
              rows: rows.map((row) {
                final qty = row.quantityFor(_selectedBranchId);
                final isOut = qty <= 0;
                final isLow = qty > 0 && qty <= row.lowStockThreshold;

                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            row.productType.icon,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (row.brand != null || row.sizeKg != null)
                                Text(
                                  [
                                    if (row.brand != null) row.brand,
                                    if (row.sizeKg != null)
                                      _sizeLabel(row.sizeKg),
                                  ].join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    DataCell(_typeBadge(row.productType)),
                    DataCell(
                      row.productType == ProductType.service
                          ? const Text('—')
                          : _branchStockCell(
                              qty: qty,
                              threshold: row.lowStockThreshold,
                            ),
                    ),
                    DataCell(
                      row.productType == ProductType.service
                          ? const Text('—')
                          : Text(
                              '${row.lowStockThreshold} units',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                    ),
                    DataCell(
                      row.productType == ProductType.service
                          ? _serviceBadge()
                          : _statusBadge(isOut: isOut, isLow: isLow),
                    ),
                    DataCell(
                      TextButton.icon(
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Transfer'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: _handleTransfers,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact mobile cards layout
  Widget _buildCompactStockCards(List<ProductStockRow> rows) {
    return Column(
      children: [
        for (final row in rows) ...[
          _compactProductCard(row),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _compactProductCard(ProductStockRow row) {
    final isService = row.productType == ProductType.service;
    final qty = row.quantityFor(_selectedBranchId);
    final isOut = qty <= 0;
    final isLow = qty > 0 && qty <= row.lowStockThreshold;

    final badgeBg = isOut
        ? AppColors.danger.withValues(alpha: 0.12)
        : isLow
        ? AppColors.warning.withValues(alpha: 0.14)
        : AppColors.success.withValues(alpha: 0.12);
    final badgeFg = isOut
        ? AppColors.danger
        : isLow
        ? AppColors.warning
        : AppColors.success;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isLow
              ? AppColors.warning.withValues(alpha: 0.5)
              : isOut
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                  child: Icon(row.productType.icon, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _typeBadge(row.productType),
                          if (row.brand != null || row.sizeKg != null) ...[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                [
                                  if (row.brand != null) row.brand,
                                  if (row.sizeKg != null)
                                    _sizeLabel(row.sizeKg),
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Big Stock Quantity Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeFg.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isService)
                        const Text(
                          'Service',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else ...[
                        Text(
                          '$qty',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: badgeFg,
                          ),
                        ),
                        Text(
                          isOut
                              ? 'Out of stock'
                              : isLow
                              ? 'Low stock'
                              : 'In stock',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // If All branches is selected, show per-branch breakdown pill row
            if (_isAllBranches && _branches.isNotEmpty) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Text(
                    'Branches: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final b in _branches) ...[
                            _branchPill(
                              branchName: b['name'] as String,
                              qty: row.branchQuantities[b['id']] ?? 0,
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _branchPill({required String branchName, required int qty}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$branchName: $qty',
        style: TextStyle(
          fontSize: 11,
          fontWeight: qty > 0 ? FontWeight.w700 : FontWeight.w500,
          color: qty > 0 ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _branchStockCell({required int qty, required int threshold}) {
    final isOut = qty <= 0;
    final isLow = qty > 0 && qty <= threshold;

    Color bg;
    Color fg;

    if (isOut) {
      bg = Colors.grey.withValues(alpha: 0.12);
      fg = AppColors.textSecondary;
    } else if (isLow) {
      bg = AppColors.warning.withValues(alpha: 0.14);
      fg = AppColors.warning;
    } else {
      bg = AppColors.success.withValues(alpha: 0.12);
      fg = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$qty',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          color: fg,
        ),
      ),
    );
  }

  Widget _statusBadge({required bool isOut, required bool isLow}) {
    if (isOut) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 12, color: AppColors.danger),
            SizedBox(width: 4),
            Text(
              'Out of stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      );
    }

    if (isLow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 12,
              color: AppColors.warning,
            ),
            SizedBox(width: 4),
            Text(
              'Low stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 12, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'In stock',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Service',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _typeBadge(ProductType type) {
    Color color;
    switch (type) {
      case ProductType.refill:
        color = AppColors.primary;
        break;
      case ProductType.cylinder:
        color = const Color(0xFF0284C7);
        break;
      case ProductType.accessory:
        color = const Color(0xFF7C3AED);
        break;
      case ProductType.service:
        color = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View 2: Cylinder Fleet Breakdown View (Refills vs Empties by Size)
  // ---------------------------------------------------------------------------

  Widget _buildFleetView(bool isWide) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _buildSummaryMetricsRow(isWide),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          color: AppColors.primary.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Physical cylinder fleet for $_selectedBranchName: '
                    'Refills are cylinders with gas; empties are cylinders without gas.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_cylinderSizes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'No cylinder inventory recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else ...[
          for (final size in _cylinderSizes) ...[
            _fleetSizeCard(size),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _fleetTotalCard(),
        ],
      ],
    );
  }

  Widget _fleetSizeCard(double? size) {
    final gas = _gasForSize(size);
    final empty = _emptyForSize(size);
    final gasQty = _gasQtyForSize(size);
    final emptyQty = _emptyQtyForSize(size);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${gasQty + emptyQty} total cylinders',
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
              const SizedBox(height: 10),
              const Text(
                'WITH GAS (REFILLS)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              for (final g in gas)
                _fleetBrandRow(g.brand ?? g.productName, g.quantity),
              _fleetSubtotalRow('Gas subtotal', gasQty, AppColors.primary),
            ],
            if (empty.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'EMPTY CYLINDERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              for (final e in empty)
                _fleetBrandRow(e.brand ?? e.productName, e.quantity),
              _fleetSubtotalRow(
                'Empty subtotal',
                emptyQty,
                AppColors.textPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fleetBrandRow(String brand, int qty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          const SizedBox(width: 4),
          const Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(brand, style: const TextStyle(fontSize: 13))),
          Text(
            '$qty',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fleetSubtotalRow(String label, int qty, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
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

  Widget _fleetTotalCard() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TOTAL FLEET BREAKDOWN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 8),
            for (final size in _cylinderSizes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sizeLabel(size),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                    Text(
                      '${_gasQtyForSize(size) + _emptyQtyForSize(size)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'GRAND TOTAL CYLINDERS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$_metricCylindersTotal',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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

  // ---------------------------------------------------------------------------
  // Floating Actions (Transfers, Reconcile, Order)
  // ---------------------------------------------------------------------------

  Widget _buildFloatingActions(bool isWide) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'stock-transfers-btn',
          onPressed: _handleTransfers,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.swap_horiz_outlined),
          label: Text(isWide ? 'Branch transfers' : 'Transfer'),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.extended(
          heroTag: 'stock-reconcile-btn',
          onPressed: _handleReconcile,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(isWide ? 'Reconcile stock' : 'Count'),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.extended(
          heroTag: 'stock-order-btn',
          onPressed: _handleOrder,
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Order'),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: AppColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
