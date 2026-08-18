import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/auth_controller.dart';
import '../../customers/models/customer.dart';
import '../../inventory/models/product.dart';
import '../../riders/models/rider.dart';
import '../data/sale_repository.dart';
import '../receipt_page.dart';

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

/// A cylinder left with the customer during this sale (optional).
class _LeftCylinder {
  _LeftCylinder({
    required this.productId,
    required this.productName,
    this.quantity = 1,
    DateTime? followUpDate,
  }) : followUpDate = followUpDate ?? DateTime.now().add(const Duration(days: 7));

  final String productId;
  final String productName;
  int quantity;
  DateTime followUpDate;
}

class SaleForm extends StatefulWidget {
  const SaleForm({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  final _repo = SaleRepository();
  final _amountPaidCtrl = TextEditingController();
  final _mpesaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  List<Product> _products = [];
  List<Map<String, dynamic>> _branches = [];
  List<Customer> _customers = [];
  List<CustomerLocation> _locations = [];
  List<RiderSummary> _riders = [];

  final List<_LineItem> _items = [];
  final List<_LeftCylinder> _leftCylinders = [];
  List<RiderSummary> _selectedRiders = [];

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

  /// Opens the add-product bottom sheet: search -> pick -> qty + price.
  Future<void> _addProductFlow() async {
    final picked = await showModalBottomSheet<_PickedProduct>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddProductSheet(
        products: _products,
        stock: _stock,
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      final existing =
          _items.where((i) => i.product.id == picked.product.id);
      if (existing.isNotEmpty) {
        existing.first.quantity = picked.quantity;
        existing.first.priceCtrl.text = picked.priceText;
      } else {
        final item = _LineItem(product: picked.product)
          ..quantity = picked.quantity;
        item.priceCtrl.text = picked.priceText;
        if (item.isRefill) {
          item.returnCylinder = _defaultReturnCylinder(picked.product);
        }
        _items.add(item);
      }
    });
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
        cylindersLeft: [
          for (final lc in _leftCylinders)
            {
              'product_id': lc.productId,
              'quantity': lc.quantity,
              'follow_up_date':
                  lc.followUpDate.toIso8601String().substring(0, 10),
            },
        ],
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
    _leftCylinders.clear();
    _selectedRiders.clear();
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
          OutlinedButton.icon(
            onPressed: () {
              final saleId = result['sale_id'] as String?;
              Navigator.of(context).pop();
              if (saleId != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReceiptPage(saleId: saleId),
                  ),
                );
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print receipt'),
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
        _leftCylindersCard(),
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
      child: ListTile(
        onTap: _addProductFlow,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.add_shopping_cart_outlined,
              color: AppColors.primary),
        ),
        title: const Text(
          'Add product',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        subtitle: const Text(
          'Search the catalogue, set quantity & price',
          style: TextStyle(fontSize: 12.5),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _itemsCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              _items.isEmpty
                  ? 'Products being sold'
                  : 'Products being sold (${_items.length})',
              Icons.shopping_cart_outlined,
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No products added yet — tap "Add product" to start.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
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
            if (item.returnCylinder == null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 15, color: AppColors.danger),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'No empty returned — fleet reduces by this '
                        'quantity and it will be flagged for follow-up.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_hasExchangeMismatch(item))
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 15, color: AppColors.warning),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Different brand/size exchange — this will be '
                        'flagged for review.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  bool _hasExchangeMismatch(_LineItem item) {
    final ret = item.returnCylinder;
    if (ret == null) return false;
    return item.product.brand != ret.brand || item.product.sizeKg != ret.sizeKg;
  }

  Future<void> _addLeftCylinder() async {
    final picked = await showModalBottomSheet<_LeftCylinder>(
      context: context,
      isScrollControlled: true,
      builder: (context) => LeftCylinderSheet(
        cylinders: _products
            .where((p) => p.productType == ProductType.cylinder)
            .toList(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _leftCylinders.add(picked));
    }
  }

  Widget _leftCylindersCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              'Cylinder left with customer (optional)',
              Icons.cyclone_outlined,
            ),
            const SizedBox(height: 6),
            const Text(
              'Only if you left a cylinder behind — we log who has it, '
              'who left it and when to collect it.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (_leftCylinders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'None.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              )
            else
              for (final lc in _leftCylinders)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cyclone,
                      size: 20, color: AppColors.primary),
                  title: Text(
                    '${lc.productName} x${lc.quantity}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Collect by ${AppFormatters.date(lc.followUpDate)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _leftCylinders.remove(lc)),
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger, size: 20),
                  ),
                ),
            OutlinedButton.icon(
              onPressed: _addLeftCylinder,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Add cylinder left',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRiders() async {
    final ids = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RiderPickerSheet(
        riders: _riders,
        selectedIds: {for (final r in _selectedRiders) r.id},
      ),
    );
    if (ids == null || !mounted) return;
    setState(() {
      _selectedRiders = _riders.where((r) => ids.contains(r.id)).toList();
    });
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
            if (_selectedRiders.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No rider selected yet.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary.withValues(alpha: 0.8)),
                ),
              )
            else
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
                ],
              ),
            OutlinedButton.icon(
              onPressed: _pickRiders,
              icon: const Icon(Icons.two_wheeler_outlined, size: 18),
              label: Text(
                _selectedRiders.isEmpty ? 'Select rider' : 'Add / change rider',
                style: const TextStyle(fontSize: 13),
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
// test-1787029459

/// A product chosen from the picker, with the qty + price the cashier set.
class _PickedProduct {
  const _PickedProduct({
    required this.product,
    required this.quantity,
    required this.priceText,
  });

  final Product product;
  final int quantity;
  final String priceText;
}

/// Bottom sheet: search the catalogue -> tap a product -> set quantity &
/// selling price -> "Add to sale".
class AddProductSheet extends StatefulWidget {
  const AddProductSheet({
    super.key,
    required this.products,
    required this.stock,
  });

  final List<Product> products;
  final Map<String, int> stock;

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _searchCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  Product? _selected;
  int _qty = 1;
  String? _qtyError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  int _availableFor(Product p) {
    if (p.productType == ProductType.service) return 1 << 30;
    return widget.stock[p.id] ?? 0;
  }

  List<Product> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.products;
    return widget.products
        .where((p) => p.name.toLowerCase().contains(term))
        .toList();
  }

  void _select(Product p) {
    setState(() {
      _selected = p;
      _qty = 1;
      _qtyError = null;
      _priceCtrl.text = p.salePrice == p.salePrice.roundToDouble()
          ? p.salePrice.toStringAsFixed(0)
          : p.salePrice.toString();
    });
  }

  void _confirmAdd() {
    final product = _selected;
    if (product == null) return;
    final available = _availableFor(product);
    if (_qty < 1) {
      setState(() => _qtyError = 'Quantity must be at least 1.');
      return;
    }
    if (_qty > available) {
      setState(() =>
          _qtyError = 'Only $available available — reduce the quantity.');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) {
      setState(() => _qtyError = 'Enter a valid selling price.');
      return;
    }
    Navigator.of(context).pop(_PickedProduct(
      product: product,
      quantity: _qty,
      priceText: _priceCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected == null ? 'Add product' : _selected!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _selected == null
                  ? _buildList(scrollController)
                  : _buildDetail(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(ScrollController scrollController) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search products…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No products match.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final product = _filtered[i];
                    final available = _availableFor(product);
                    final isService =
                        product.productType == ProductType.service;
                    final outOfStock = !isService && available <= 0;
                    return ListTile(
                      dense: true,
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
                          fontWeight: outOfStock
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: outOfStock ? null : () => _select(product),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetail() {
    final product = _selected!;
    final available = _availableFor(product);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.productType.label}'
                    '${product.productType == ProductType.service ? '' : ' · available $available'}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
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
                          _qtyError = null;
                        }),
                        icon: const Icon(Icons.remove_circle_outline, size: 22),
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
                        onPressed: () => setState(() {
                          if (_qty < available) _qty++;
                          _qtyError = null;
                        }),
                        icon: const Icon(Icons.add_circle_outline, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() => _qtyError = null),
                    decoration: const InputDecoration(
                      labelText: 'Selling price KSh',
                      isDense: true,
                      prefixIcon: Icon(Icons.sell_outlined, size: 20),
                    ),
                  ),
                  if (_qtyError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _qtyError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _confirmAdd,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                    'Add · ${AppFormatters.kes(_qty * (double.tryParse(_priceCtrl.text.trim()) ?? product.salePrice))}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: pick one or more riders (empty by default).
class RiderPickerSheet extends StatefulWidget {
  const RiderPickerSheet({
    super.key,
    required this.riders,
    required this.selectedIds,
  });

  final List<RiderSummary> riders;
  final Set<String> selectedIds;

  @override
  State<RiderPickerSheet> createState() => _RiderPickerSheetState();
}

class _RiderPickerSheetState extends State<RiderPickerSheet> {
  late final Set<String> _selected = {...widget.selectedIds};
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RiderSummary> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.riders;
    return widget.riders
        .where((r) => r.fullName.toLowerCase().contains(term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select rider(s)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search riders…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No riders found.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final rider = _filtered[i];
                        final checked = _selected.contains(rider.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(rider.id);
                            } else {
                              _selected.remove(rider.id);
                            }
                          }),
                          title: Text(
                            rider.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            rider.branchName ?? '',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  icon: const Icon(Icons.check),
                  label: Text('Done (${_selected.length} selected)'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet: pick a cylinder + qty + follow-up date to log one left
/// with the customer during this sale.
class LeftCylinderSheet extends StatefulWidget {
  const LeftCylinderSheet({super.key, required this.cylinders});

  final List<Product> cylinders;

  @override
  State<LeftCylinderSheet> createState() => _LeftCylinderSheetState();
}

class _LeftCylinderSheetState extends State<LeftCylinderSheet> {
  Product? _selected;
  int _qty = 1;
  DateTime _followUp = DateTime.now().add(const Duration(days: 7));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cylinder left with customer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cylinder *',
              isDense: true,
            ),
            hint: const Text('Select cylinder'),
            items: [
              for (final c in widget.cylinders)
                DropdownMenuItem(
                  value: c.id,
                  child:
                      Text(c.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _selected = v == null
                  ? null
                  : widget.cylinders.firstWhere((c) => c.id == v);
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Quantity',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  if (_qty > 1) _qty--;
                }),
                icon: const Icon(Icons.remove_circle_outline, size: 22),
              ),
              Text(
                '$_qty',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _qty++),
                icon: const Icon(Icons.add_circle_outline, size: 22),
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
                lastDate:
                    DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _followUp = picked);
              }
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              'Collect by ${AppFormatters.date(_followUp)}',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              final product = _selected;
              if (product == null) return;
              Navigator.of(context).pop(_LeftCylinder(
                productId: product.id,
                productName: product.name,
                quantity: _qty,
                followUpDate: _followUp,
              ));
            },
            icon: const Icon(Icons.add),
            label: const Text('Add to sale'),
          ),
        ],
      ),
    );
  }
}
