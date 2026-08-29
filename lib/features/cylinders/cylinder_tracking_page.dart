import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../auth/auth_controller.dart';
import '../customers/data/customer_repository.dart';
import '../customers/models/customer.dart';
import '../inventory/models/product.dart';
import 'data/cylinder_repository.dart';
import 'models/cylinder_models.dart';

/// Cylinders left with customers: who has what, who left it, when to
/// go back for it. Plus logging new ones.
class CylinderTrackingPage extends StatefulWidget {
  const CylinderTrackingPage({super.key});

  @override
  State<CylinderTrackingPage> createState() => _CylinderTrackingPageState();
}

class _CylinderTrackingPageState extends State<CylinderTrackingPage> {
  final _repo = CylinderRepository();
  final _customerRepo = CustomerRepository();
  final _searchCtrl = TextEditingController();

  List<CylinderTracking> _items = [];
  List<Customer> _customers = [];
  List<Product> _cylinders = [];
  String _status = 'out';
  bool _loading = true;
  String? _error;
  String? _busyId;

  // Filters
  String? _customerFilter;
  String? _cylinderFilter;
  bool _overdueFilter = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetchTracking(status: _status);
      final customers = await _customerRepo.fetchCustomers();
      final products = await _customerRepo.fetchProducts();
      if (!mounted) return;
      setState(() {
        _items = items;
        _customers = customers;
        _cylinders = products
            .where((p) => p.productType == ProductType.cylinder)
            .toList();
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

  List<CylinderTracking> get _filteredItems {
    var result = _items;

    // Customer filter
    if (_customerFilter != null) {
      result = result.where((t) => t.customerId == _customerFilter).toList();
    }

    // Cylinder type filter
    if (_cylinderFilter != null) {
      result = result.where((t) => t.productId == _cylinderFilter).toList();
    }

    // Overdue filter
    if (_overdueFilter) {
      result = result.where((t) => t.isOverdue).toList();
    }

    // Search filter
    final search = _searchCtrl.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      result = result.where((t) {
        return (t.customerName?.toLowerCase().contains(search) ?? false) ||
            (t.productName?.toLowerCase().contains(search) ?? false) ||
            (t.invoiceNo?.toLowerCase().contains(search) ?? false) ||
            (t.id.toLowerCase().contains(search)) ||
            (t.locationName?.toLowerCase().contains(search) ?? false);
      }).toList();
    }

    return result;
  }

  int get _totalOut => _filteredItems.where((t) => t.isOut).length;
  int get _totalReturned => _filteredItems.where((t) => !t.isOut).length;
  int get _totalOverdue => _filteredItems.where((t) => t.isOverdue).length;
  int get _totalQuantity => _filteredItems
      .where((t) => t.isOut)
      .fold(0, (sum, t) => sum + t.quantity);

  Future<void> _markReturned(CylinderTracking item) async {
    setState(() => _busyId = item.id);
    try {
      await _repo.markReturned(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.productName ?? 'Cylinder'} collected from '
            '${item.customerName ?? 'customer'}',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed: ${e.toString().replaceAll('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _logLeft() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _LogCylinderLeftPage()));
    _load();
  }

  void _clearFilters() {
    setState(() {
      _customerFilter = null;
      _cylinderFilter = null;
      _overdueFilter = false;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cylinder Tracking'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Stats cards
          _statsCards(),
          const Divider(height: 1),
          // Filters
          _filtersBar(),
          const Divider(height: 1),
          // Search
          _searchBar(),
          const Divider(height: 1),
          // List
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'log-cylinder-left',
        tooltip: 'Log cylinder left',
        onPressed: _logLeft,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _statsCards() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              'Out',
              _totalOut,
              AppColors.warning,
              Icons.arrow_circle_right_outlined,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCard(
              'Returned',
              _totalReturned,
              AppColors.success,
              Icons.check_circle_outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCard(
              'Overdue',
              _totalOverdue,
              AppColors.danger,
              Icons.warning_amber_outlined,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statCard(
              'Total Qty',
              _totalQuantity,
              AppColors.primary,
              Icons.inventory_2_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, Color color, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Status filter
          ChoiceChip(
            label: const Text('Outstanding'),
            selected: _status == 'out',
            onSelected: (selected) {
              setState(() {
                _status = selected ? 'out' : 'out';
                _load();
              });
            },
            selectedColor: AppColors.primary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          ChoiceChip(
            label: const Text('Returned'),
            selected: _status == 'returned',
            onSelected: (selected) {
              setState(() {
                _status = selected ? 'returned' : 'out';
                _load();
              });
            },
            selectedColor: AppColors.primary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          // Overdue filter
          FilterChip(
            label: const Text('Overdue Only'),
            selected: _overdueFilter,
            onSelected: (selected) => setState(() => _overdueFilter = selected),
          ),
          // Customer filter
          if (_customers.isNotEmpty) ...[
            FilterChip(
              label: const Text('Customer'),
              selected: _customerFilter != null,
              onSelected: (selected) async {
                if (!selected) {
                  setState(() => _customerFilter = null);
                  return;
                }
                final customer = await showDialog<Customer>(
                  context: context,
                  builder: (context) => _CustomerPickerDialog(
                    customers: _customers,
                    selectedId: _customerFilter,
                  ),
                );
                if (customer != null) {
                  setState(() => _customerFilter = customer.id);
                }
              },
            ),
          ],
          // Cylinder type filter
          if (_cylinders.isNotEmpty) ...[
            FilterChip(
              label: const Text('Cylinder Type'),
              selected: _cylinderFilter != null,
              onSelected: (selected) async {
                if (!selected) {
                  setState(() => _cylinderFilter = null);
                  return;
                }
                final product = await showDialog<Product>(
                  context: context,
                  builder: (context) => _ProductPickerDialog(
                    products: _cylinders,
                    selectedId: _cylinderFilter,
                  ),
                );
                if (product != null) {
                  setState(() => _cylinderFilter = product.id);
                }
              },
            ),
          ],
          // Clear filters
          if (_customerFilter != null ||
              _cylinderFilter != null ||
              _overdueFilter) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Clear'),
              onPressed: _clearFilters,
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search by invoice, customer, cylinder...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                )
              : null,
          border: const OutlineInputBorder(),
        ),
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
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
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _status == 'out'
                ? 'No cylinders out with customers. 🎉\n\nUse the + button '
                      'to log a cylinder left behind.'
                : 'Nothing collected yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _trackingCard(_items[i]),
    );
  }

  Widget _trackingCard(CylinderTracking item) {
    final followUpColor = item.isOverdue
        ? AppColors.danger
        : item.isDueSoon
        ? AppColors.warning
        : AppColors.textSecondary;

    return Card(
      margin: EdgeInsets.zero,
      color: item.isReturned
          ? AppColors.success.withValues(alpha: 0.05)
          : item.isOverdue
          ? AppColors.danger.withValues(alpha: 0.05)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Invoice + Status
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (item.invoiceNo != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.invoiceNo!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (item.invoiceNo != null) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.productName ?? 'Cylinder',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.quantity > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'x${item.quantity}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Customer info
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.customerName ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (item.locationName != null && item.locationName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 22),
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.locationName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            // Left by and date
            Row(
              children: [
                Icon(
                  Icons.person_pin_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Left by ${item.leftByName ?? '—'}${item.leftAt != null ? ' · ${AppFormatters.date(item.leftAt!)}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (item.followUpDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      item.isOverdue
                          ? Icons.error_outline
                          : Icons.event_outlined,
                      size: 15,
                      color: followUpColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.isOverdue
                            ? 'Follow-up was ${AppFormatters.date(item.followUpDate!)} — OVERDUE'
                            : 'Follow-up: ${AppFormatters.date(item.followUpDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: followUpColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (item.note != null && item.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 22),
                  Expanded(
                    child: Text(
                      item.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Status badge and action
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: item.isReturned
                        ? AppColors.success.withValues(alpha: 0.1)
                        : item.isOverdue
                        ? AppColors.danger.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.isReturned
                        ? 'RETURNED'
                        : item.isOverdue
                        ? 'OVERDUE'
                        : 'OUTSTANDING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: item.isReturned
                          ? AppColors.success
                          : item.isOverdue
                          ? AppColors.danger
                          : AppColors.warning,
                    ),
                  ),
                ),
                const Spacer(),
                if (item.isOut)
                  OutlinedButton.icon(
                    onPressed: _busyId == item.id
                        ? null
                        : () => _markReturned(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    icon: _busyId == item.id
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Mark Returned'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog to pick a customer for filtering
class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({required this.customers, this.selectedId});

  final List<Customer> customers;
  final String? selectedId;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.customers;
    return widget.customers
        .where((c) => c.name.toLowerCase().contains(term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Customer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: _filtered.isEmpty
                  ? const Center(child: Text('No customers found'))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final customer = _filtered[i];
                        final selected = _selectedId == customer.id;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          selectedTileColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          title: Text(customer.name),
                          subtitle: Text(customer.phone ?? ''),
                          trailing: selected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to pick a cylinder type for filtering
class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products, this.selectedId});

  final List<Product> products;
  final String? selectedId;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _searchCtrl = TextEditingController();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Product> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.products;
    return widget.products
        .where((p) => p.name.toLowerCase().contains(term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Cylinder Type',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search cylinders...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: _filtered.isEmpty
                  ? const Center(child: Text('No cylinders found'))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final product = _filtered[i];
                        final selected = _selectedId == product.id;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          selectedTileColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          title: Text(product.name),
                          subtitle: Text(
                            '${product.brand ?? ''} ${product.sizeKg != null ? '${product.sizeKg}kg' : ''}'
                                .trim(),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(product),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone form: log a cylinder left with a customer (no sale).
class _LogCylinderLeftPage extends StatefulWidget {
  const _LogCylinderLeftPage();

  @override
  State<_LogCylinderLeftPage> createState() => _LogCylinderLeftPageState();
}

class _LogCylinderLeftPageState extends State<_LogCylinderLeftPage> {
  final _repo = CylinderRepository();
  final _customerRepo = CustomerRepository();
  final _noteCtrl = TextEditingController();

  List<Customer> _customers = [];
  List<Product> _cylinders = [];
  String? _customerId;
  String? _locationId;
  String? _productId;
  int _qty = 1;
  DateTime _followUp = DateTime.now().add(const Duration(days: 7));
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final customers = await _customerRepo.fetchCustomers();
      final cylinders = await _customerRepo.fetchProducts();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _cylinders = cylinders
            .where((p) => p.productType == ProductType.cylinder)
            .toList();
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
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_customerId == null || _productId == null) {
      setState(() => _error = 'Select the customer and the cylinder.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final branchId = context.read<AuthController>().branchId;
      await _repo.logCylinderLeft(
        customerId: _customerId!,
        locationId: _locationId,
        productId: _productId!,
        quantity: _qty,
        followUpDate: _followUp,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        branchId: branchId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cylinder left logged')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Log cylinder left')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _customerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Customer *',
                            isDense: true,
                          ),
                          hint: const Text('Select customer'),
                          items: [
                            for (final c in _customers)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _customerId = v;
                            _locationId = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _productId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cylinder *',
                            isDense: true,
                          ),
                          hint: const Text('Select cylinder'),
                          items: [
                            for (final c in _cylinders)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _productId = v),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              'Quantity',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                if (_qty > 1) _qty--;
                              }),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 22,
                              ),
                            ),
                            Text(
                              '$_qty',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _qty++),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _followUp,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _followUp = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text(
                            'Follow-up: ${AppFormatters.date(_followUp)}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
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
                  label: const Text('Log cylinder left'),
                ),
              ],
            ),
    );
  }
}
