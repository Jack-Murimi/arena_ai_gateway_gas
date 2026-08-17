import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/auth_controller.dart';
import '../../customers/models/customer.dart';
import '../../inventory/models/product.dart';
import '../../riders/models/rider.dart';
import '../data/sale_repository.dart';

/// One line item in the current sale.
class _LineItem {
  _LineItem({required this.product}) {
    priceCtrl = TextEditingController(
      text: product.salePrice == product.salePrice.roundToDouble()
          ? product.salePrice.toStringAsFixed(0)
          : product.salePrice.toString(),
    );
  }

  final Product product;
  int quantity = 1;
  late final TextEditingController priceCtrl;
  Product? returnCylinder; // for refills: the empty cylinder coming back

  double get unitPrice =>
      double.tryParse(priceCtrl.text.trim()) ?? product.salePrice;
  double get lineTotal => quantity * unitPrice;
  bool get isRefill => product.productType == ProductType.refill;

  void dispose() => priceCtrl.dispose();
}

class SaleForm extends StatefulWidget {
  const SaleForm({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  final _repo = SaleRepository();
  final _searchCtrl = TextEditingController();
  final _amountPaidCtrl = TextEditingController();
  final _mpesaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  List<Product> _products = [];
  List<Map<String, dynamic>> _branches = [];
  List<Customer> _customers = [];
  List<CustomerLocation> _locations = [];
  List<RiderSummary> _riders = [];

  final List<_LineItem> _items = [];
  final List<RiderSummary> _selectedRiders = [];

  DateTime _saleDate = DateTime.now();
  String? _branchId;
  String? _customerId;
  String? _locationId;
  int _paymentMethod = 0; // 0 mpesa, 1 cash, 2 pdq, 3 cheque
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // productId -> available quantity for the selected branch
  Map<String, int> _stock = {};

  int _availableFor(String productId) => _stock[productId] ?? 0;

  Future<void> _loadStock(String branchId) async {
    try {
      final stock = await _repo.fetchStockMap(branchId);
      if (!mounted) return;
      setState(() => _stock = stock);
    } catch (_) {
      // non-fatal — the DB still guards against overselling
    }
  }

  static const _methods = ['mpesa', 'cash', 'pdq', 'cheque'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountPaidCtrl.dispose();
    _mpesaCtrl.dispose();
    _noteCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.fetchProducts(),
        _repo.fetchBranches(),
        _repo.fetchCustomers(),
        _repo.fetchRiders(),
      ]);
      final products = results[0] as List<Product>;
      final branches = results[1] as List<Map<String, dynamic>>;
      final customers = results[2] as List<Customer>;
      final riders = results[3] as List<RiderSummary>;
      if (!mounted) return;

      final profileBranchId = context.read<AuthController>().branchId;
      setState(() {
        _products = products;
        _branches = branches;
        _customers = customers;
        _riders = riders;
        _branchId = branches.any((b) => b['id'] == profileBranchId)
            ? profileBranchId
            : (branches.isNotEmpty ? branches.first['id'] as String : null);
        if (riders.isNotEmpty) {
          _selectedRiders.add(riders.first); // default: one rider
        }
        _loading = false;
      });
      final branchId = _branchId;
      if (branchId != null) _loadStock(branchId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Items
  // -------------------------------------------------------------------------

  void _addProduct(Product product) {
    final available = _availableFor(product.id);
    if (available <= 0 && product.productType != ProductType.service) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} is out of stock '
              '(available: $available)'),
        ),
      );
      return;
    }
    setState(() {
      final existing = _items.where((i) => i.product.id == product.id);
      if (existing.isNotEmpty) {
        final item = existing.first;
        if (item.quantity < available ||
            product.productType == ProductType.service) {
          item.quantity++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Only $available of ${product.name} available.'),
            ),
          );
        }
      } else {
        final item = _LineItem(product: product);
        if (item.isRefill) {
          item.returnCylinder = _defaultReturnCylinder(product);
        }
        _items.add(item);
      }
    });
  }

  /// Default returned cylinder for a refill: same brand + size; else size.
  Product? _defaultReturnCylinder(Product refill) {
    final cylinders =
        _products.where((p) => p.productType == ProductType.cylinder);
    Product? match;
    for (final c in cylinders) {
      if (c.brand == refill.brand && c.sizeKg == refill.sizeKg) {
        match = c;
        break;
      }
    }
    if (match == null) {
      for (final c in cylinders) {
        if (c.sizeKg == refill.sizeKg) {
          match = c;
          break;
        }
      }
    }
    return match;
  }

  List<Product> get _filteredProducts {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return _products;
    return _products
        .where((p) => p.name.toLowerCase().contains(term))
        .toList();
  }

  double get _total =>
      _items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _paidAmount =>
      double.tryParse(_amountPaidCtrl.text.trim()) ?? _total;

  double get _balanceDue => _total - _paidAmount;

  int get _cylinderCount => _items
      .where((i) =>
          i.product.productType == ProductType.refill ||
          i.product.productType == ProductType.cylinder)
      .fold<int>(0, (sum, i) => sum + i.quantity);

  int get _fiftyKgCount => _items
      .where((i) => i.product.sizeKg == 50)
      .fold<int>(0, (sum, i) => sum + i.quantity);

  bool get _heavyDelivery => _cylinderCount > 2 || _fiftyKgCount >= 2;

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save({required bool asInvoice}) async {
    if (_branchId == null) {
      setState(() => _error = 'Select a branch.');
      return;
    }
    if (_customerId == null) {
      setState(() => _error = 'Select a customer.');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final amountPaid = asInvoice ? 0.0 : _paidAmount;

    try {
      final result = await _repo.recordSale(
        saleDate: _saleDate,
        branchId: _branchId!,
        customerId: _customerId!,
        locationId: _locationId,
        items: [
          for (final item in _items)
            {
              'product_id': item.product.id,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'cylinder_return_product_id': item.returnCylinder?.id,
            },
        ],
        riderIds: [for (final r in _selectedRiders) r.id],
        paymentMethod: asInvoice ? 'credit' : _methods[_paymentMethod],
        amountPaid: amountPaid,
        mpesaCode: _mpesaCtrl.text.trim().isEmpty
            ? null
            : _mpesaCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;

      _showResult(result);
      _resetForm();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString().replaceAll('Exception: ', '');
    if (msg.contains('Insufficient stock')) {
      final match = RegExp(r'Insufficient stock for (.*?) \(available (\d+), requested (\d+)\)')
          .firstMatch(msg);
      if (match != null) {
        return 'Not enough ${match.group(1)} — only ${match.group(2)} '
            'in stock (you need ${match.group(3)}).';
      }
      return 'Not enough stock for one of the items. '
          'Check availability and try again.';
    }
    return msg;
  }

  void _resetForm() {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _selectedRiders.clear();
    if (_riders.isNotEmpty) _selectedRiders.add(_riders.first);
    _amountPaidCtrl.clear();
    _mpesaCtrl.clear();
    _noteCtrl.clear();
    setState(() => _saving = false);
  }

  void _showResult(Map<String, dynamic> result) {
    final status = result['payment_status'] as String? ?? 'paid';
    final balanceDue = (result['balance_due'] as num?)?.toDouble() ?? 0;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              status == 'unpaid'
                  ? Icons.receipt_long_outlined
                  : status == 'partial'
                      ? Icons.account_balance_wallet_outlined
                      : Icons.check_circle_outline,
              color: status == 'unpaid'
                  ? AppColors.warning
                  : status == 'partial'
                      ? AppColors.warning
                      : AppColors.success,
            ),
            const SizedBox(width: 8),
            const Text('Sale recorded'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('Invoice', result['invoice_no']?.toString() ?? ''),
            _resultRow('Total', AppFormatters.kes(
                (result['total'] as num?)?.toDouble() ?? 0)),
            _resultRow('Paid', AppFormatters.kes(
                (result['amount_paid'] as num?)?.toDouble() ?? 0)),
            if (status == 'unpaid')
              _resultRow('To be billed', AppFormatters.kes(balanceDue))
            else if (status == 'partial')
              _resultRow('Balance due', AppFormatters.kes(balanceDue))
            else if (balanceDue < 0)
              _resultRow('Overpayment (credit)', AppFormatters.kes(-balanceDue)),
            const SizedBox(height: 8),
            Text(
              status == 'unpaid'
                  ? 'Added to the customer\'s account. It will show on '
                      'their balance.'
                  : status == 'partial'
                      ? 'The unpaid balance has been added to the '
                          'customer\'s account.'
                      : 'Payment complete.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _products.isEmpty) {
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
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _detailsCard(),
        const SizedBox(height: 12),
        _productsCard(),
        const SizedBox(height: 12),
        _itemsCard(),
        const SizedBox(height: 12),
        _ridersCard(),
        const SizedBox(height: 12),
        _paymentCard(),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
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
        _actionButtons(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _detailsCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Sale details', Icons.receipt_outlined),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _saleDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _saleDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(AppFormatters.date(_saleDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      isDense: true,
                    ),
                    items: [
                      for (final b in _branches)
                        DropdownMenuItem(
                          value: b['id'] as String,
                          child: Text(b['name'] as String),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _branchId = v;
                        _stock = {};
                      });
                      if (v != null) _loadStock(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _customerId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Customer *',
                isDense: true,
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              hint: const Text('Select customer'),
              items: [
                for (final c in _customers)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) async {
                setState(() {
                  _customerId = v;
                  _locationId = null;
                  _locations = [];
                });
                if (v != null) {
                  final locations = await _repo.fetchLocations(v);
                  if (!mounted) return;
                  setState(() {
                    _locations = locations;
                    _locationId =
                        locations.isEmpty ? null : locations.first.id;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _locationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Customer location',
                isDense: true,
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
              hint: _customerId == null
                  ? const Text('Select a customer first')
                  : const Text('Select location'),
              items: [
                for (final l in _locations)
                  DropdownMenuItem(
                    value: l.id,
                    child: Text(
                      '${l.name}${l.isPrimary ? ' ⭐' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _locationId = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productsCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Add products', Icons.add_shopping_cart_outlined),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search products…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _filteredProducts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final product = _filteredProducts[i];
                  final inCart = _items.any((it) => it.product.id == product.id);
                  final available = _availableFor(product.id);
                  final isService =
                      product.productType == ProductType.service;
                  final outOfStock = !isService && available <= 0;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      product.productType.icon,
                      size: 20,
                      color: outOfStock
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: outOfStock
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      isService
                          ? AppFormatters.kes(product.salePrice)
                          : '${AppFormatters.kes(product.salePrice)} · '
                              'avail $available',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: outOfStock
                            ? AppColors.danger
                            : AppColors.textSecondary,
                        fontWeight:
                            outOfStock ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: outOfStock ? null : () => _addProduct(product),
                      icon: Icon(
                        inCart ? Icons.add_circle : Icons.add_circle_outline,
                        color: outOfStock
                            ? AppColors.textSecondary
                            : inCart
                                ? AppColors.success
                                : AppColors.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemsCard() {
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Items', Icons.shopping_cart_outlined),
            const SizedBox(height: 8),
            for (final item in _items) _lineItemTile(item),
            const Divider(height: 20),
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  AppFormatters.kes(_total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineItemTile(_LineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  if (item.quantity > 1) item.quantity--;
                }),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              Text('${item.quantity}'),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  final available = _availableFor(item.product.id);
                  final isService =
                      item.product.productType == ProductType.service;
                  if (isService || item.quantity < available) {
                    item.quantity++;
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Only $available of ${item.product.name} '
                            'available.'),
                      ),
                    );
                  }
                }),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: item.priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: 'KSh ',
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  item.dispose();
                  _items.remove(item);
                }),
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
              ),
            ],
          ),
          if (item.isRefill) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.cyclone_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text(
                  'Cylinder returned:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: item.returnCylinder?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final c in _products.where(
                          (p) => p.productType == ProductType.cylinder))
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      item.returnCylinder = v == null
                          ? null
                          : _products.firstWhere((p) => p.id == v);
                    }),
                  ),
                ),
              ],
            ),
          ],
          Row(
            children: [
              const Spacer(),
              Text(
                AppFormatters.kes(item.lineTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ridersCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Delivery rider(s)', Icons.two_wheeler_outlined),
            const SizedBox(height: 8),
            if (_heavyDelivery)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Multiple cylinders / 50kg — consider adding a '
                        'second rider.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rider in _selectedRiders)
                  Chip(
                    label: Text(
                      rider.fullName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    avatar: CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        rider.initials,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    onDeleted: () => setState(
                        () => _selectedRiders.remove(rider)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  ),
                DropdownButton<String?>(
                  value: null,
                  hint: const Text('+ Add rider'),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final r in _riders.where(
                        (r) => !_selectedRiders.any((s) => s.id == r.id)))
                      DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          r.fullName,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedRiders
                          .add(_riders.firstWhere((r) => r.id == v));
                    });
                  },
                ),
              ],
            ),
            if (_selectedRiders.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No rider selected — no delivery will be created.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard() {
    final balanceDue = _balanceDue;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Payment', Icons.payments_outlined),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('M-Pesa'),
                  icon: Icon(Icons.phone_android, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Cash'),
                  icon: Icon(Icons.payments_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('PDQ'),
                  icon: Icon(Icons.credit_card, size: 16),
                ),
                ButtonSegment(
                  value: 3,
                  label: Text('Cheque'),
                  icon: Icon(Icons.receipt_outlined, size: 16),
                ),
              ],
              selected: {_paymentMethod},
              onSelectionChanged: (s) =>
                  setState(() => _paymentMethod = s.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountPaidCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount paid',
                isDense: true,
                prefixIcon: const Icon(Icons.currency_exchange, size: 20),
                suffixIcon: IconButton(
                  tooltip: 'Set to total',
                  onPressed: () => setState(() {
                    _amountPaidCtrl.text = _total
                        .toStringAsFixed(_total == _total.roundToDouble()
                            ? 0
                            : 2);
                  }),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                ),
              ),
            ),
            if (_paymentMethod == 0) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _mpesaCtrl,
                decoration: const InputDecoration(
                  labelText: 'M-Pesa code (optional)',
                  hintText: 'e.g. SGH1234XYZ',
                  isDense: true,
                  prefixIcon: Icon(Icons.sms_outlined, size: 20),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                isDense: true,
                prefixIcon: Icon(Icons.notes, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  AppFormatters.kes(_total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (balanceDue > 0.001) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text(
                    'Will be billed to customer',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    AppFormatters.kes(balanceDue),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ] else if (balanceDue < -0.001) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text(
                    'Overpayment (customer credit)',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    AppFormatters.kes(-balanceDue),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
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

  Widget _actionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(asInvoice: true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Save as invoice'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saving ? null : () => _save(asInvoice: false),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('Save sale'),
          ),
        ),
      ],
    );
  }
}
