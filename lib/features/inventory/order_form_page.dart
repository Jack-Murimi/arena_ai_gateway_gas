import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/product_repository.dart';
import 'data/stock_repository.dart';
import 'models/product.dart';
import 'models/stock_item.dart';

/// Place a purchase order for a branch. Low-stock products can be
/// pre-loaded; unit cost defaults to the product's current buying cost.
class OrderFormPage extends StatefulWidget {
  const OrderFormPage({
    super.key,
    required this.branchId,
    required this.branchName,
    this.lowStockProducts = const [],
  });

  final String branchId;
  final String branchName;
  final List<StockItem> lowStockProducts;

  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderLine {
  _OrderLine({required this.stockItem}) {
    qtyCtrl = TextEditingController(text: '0');
    costCtrl = TextEditingController();
  }

  final StockItem stockItem;
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;

  int get quantity => int.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get unitCost => double.tryParse(costCtrl.text.trim()) ?? 0;

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}

class _OrderFormPageState extends State<OrderFormPage> {
  final _repo = StockRepository();

  List<Map<String, dynamic>> _suppliers = [];
  String? _supplierId;
  String? _notes;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final List<_OrderLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final suppliers = await _repo.fetchSuppliers();
      // Pre-load low-stock products with quantity = threshold (suggested).
      for (final item in widget.lowStockProducts) {
        final line = _OrderLine(stockItem: item);
        line.qtyCtrl.text = item.lowStockThreshold.toString();
        _lines.add(line);
      }
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
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

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addProduct(Map<String, dynamic> product) {
    setState(() {
      final line = _OrderLine(
        stockItem: StockItem(
          branchId: widget.branchId,
          branchName: widget.branchName,
          productId: product['id'] as String,
          productName: (product['name'] as String?) ?? '',
          productType: ProductType.fromString(
              product['product_type'] as String?),
          quantity: 0,
        ),
      );
      line.qtyCtrl.text = '10';
      line.costCtrl.text =
          ((product['cost_price'] as num?) ?? 0).toStringAsFixed(0);
      _lines.add(line);
    });
  }

  Future<void> _placeOrder() async {
    final items = <Map<String, dynamic>>[
      for (final line in _lines)
        if (line.quantity > 0)
          {
            'product_id': line.stockItem.productId,
            'quantity': line.quantity,
            'unit_cost': line.unitCost,
          },
    ];
    if (items.isEmpty) {
      setState(() => _error = 'Add at least one item with a quantity.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await _repo.placeOrder(
        branchId: widget.branchId,
        supplierId: _supplierId,
        notes: _notes?.trim().isEmpty ?? true ? null : _notes!.trim(),
        items: items,
      );
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.success),
              SizedBox(width: 8),
              Text('Order placed'),
            ],
          ),
          content: Text(
            '${result['order_no']} created for ${widget.branchName} '
            '(${items.length} items).\n\nReceive it in Purchase orders '
            'when the stock arrives.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
      appBar: AppBar(title: Text('Place order — ${widget.branchName}')),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _supplierId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Supplier (optional)',
                            isDense: true,
                            prefixIcon:
                                Icon(Icons.local_shipping_outlined, size: 20),
                          ),
                          hint: const Text('None selected'),
                          items: [
                            for (final s in _suppliers)
                              DropdownMenuItem(
                                value: s['id'] as String,
                                child: Text(s['name'] as String),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _supplierId = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (v) => _notes = v,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            isDense: true,
                            prefixIcon: Icon(Icons.notes, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Suggested from low stock',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in _lines) _orderLineCard(line),
                const SizedBox(height: 12),
                _addProductRow(),
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
                  onPressed: _saving ? null : _placeOrder,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Place order'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _orderLineCard(_OrderLine line) {
    final isLow = widget.lowStockProducts
        .any((s) => s.productId == line.stockItem.productId);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              line.stockItem.productType.icon,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.stockItem.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    isLow ? 'Low stock' : line.stockItem.productType.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isLow ? AppColors.danger : AppColors.textSecondary,
                      fontWeight: isLow ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 82,
              child: TextField(
                controller: line.qtyCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Qty',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: TextField(
                controller: line.costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Cost KSh',
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                line.dispose();
                _lines.remove(line);
              }),
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _ProductPickerSheet(),
    );
    if (picked != null && mounted) {
      _addProduct(picked);
    }
  }

  Widget _addProductRow() {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.add, color: AppColors.primary),
        title: const Text(
          'Add products',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: const Text('Tap to browse the catalogue'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickProduct,
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _repo = ProductRepository();
  final _searchCtrl = TextEditingController();

  List<Product> _products = [];
  bool _loading = true;

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
    try {
      final products =
          await _repo.fetchProducts(search: _searchCtrl.text);
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => _load(),
                      decoration: const InputDecoration(
                        hintText: 'Search products…',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _products.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final product = _products[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            product.productType.icon,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${product.productType.label} · '
                            '${AppFormatters.kes(product.costPrice)}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onTap: () => Navigator.of(context).pop({
                            'id': product.id,
                            'name': product.name,
                            'product_type': product.productType.name,
                            'cost_price': product.costPrice,
                          }),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
