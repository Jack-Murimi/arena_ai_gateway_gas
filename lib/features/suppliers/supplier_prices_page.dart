import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'models/supplier.dart';

/// Compare which supplier sells a product cheapest (from invoice history).
class SupplierPricesPage extends StatefulWidget {
  const SupplierPricesPage({super.key});

  @override
  State<SupplierPricesPage> createState() => _SupplierPricesPageState();
}

class _SupplierPricesPageState extends State<SupplierPricesPage> {
  final _repo = SupplierRepository();

  List<Map<String, dynamic>> _products = [];
  String? _productId;
  String? _productName;
  List<SupplierProductPrice> _prices = [];
  bool _loadingPrices = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _repo.fetchProducts();
      if (!mounted) return;
      setState(() => _products = products);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSheet(products: _products),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _productId = picked['id'] as String;
      _productName = picked['name'] as String?;
      _prices = [];
    });
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final productId = _productId;
    if (productId == null) return;
    setState(() {
      _loadingPrices = true;
      _error = null;
    });
    try {
      final prices = await _repo.fetchPricesForProduct(productId);
      if (!mounted) return;
      setState(() {
        _prices = prices;
        _loadingPrices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loadingPrices = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier prices')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                onTap: _pickProduct,
                leading: const Icon(Icons.search, color: AppColors.primary),
                title: Text(
                  _productName ?? 'Choose a product…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        _productName == null ? FontWeight.w500 : FontWeight.w800,
                    color: _productName == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_productId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pick a product to compare which supplier sells it cheapest.\n\n'
            'Prices come from recorded supplier invoices.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_loadingPrices) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ),
      );
    }
    if (_prices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No supplier prices for this product yet.\n'
            'Record supplier invoices to build the comparison.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final cheapest = _prices.first.unitCost;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _prices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = _prices[i];
        final isCheapest = p.unitCost == cheapest && i == 0;
        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCheapest
                ? const BorderSide(color: AppColors.success, width: 1.5)
                : BorderSide.none,
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: (isCheapest ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.12),
              foregroundColor:
                  isCheapest ? AppColors.success : AppColors.primary,
              child: Text(
                '${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    p.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                if (isCheapest) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'BEST PRICE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: p.updatedAt == null
                ? null
                : Text(
                    'Last quoted ${AppFormatters.date(p.updatedAt!)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
            trailing: Text(
              AppFormatters.kes(p.unitCost),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isCheapest ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.products});

  final List<Map<String, dynamic>> products;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.products;
    return widget.products
        .where((p) =>
            ((p['name'] as String?) ?? '').toLowerCase().contains(term))
        .toList();
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
                      onChanged: (_) => setState(() {}),
                      autofocus: true,
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
                        final p = _filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            (p['name'] as String?) ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            (p['product_type'] as String?) ?? '',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onTap: () => Navigator.of(context).pop(p),
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
