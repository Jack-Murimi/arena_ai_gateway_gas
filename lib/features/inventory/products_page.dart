import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/product_repository.dart';
import 'models/product.dart';
import 'price_approvals_page.dart';
import 'product_form_page.dart';

/// Products catalogue: refills, cylinders, accessories & services.
/// Admin/director see the price-approvals entry (flagged price changes).
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _repo = ProductRepository();
  final _searchCtrl = TextEditingController();

  List<Product> _products = [];
  ProductType? _typeFilter;
  bool _loading = true;
  String? _error;
  bool _isReviewer = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadRole();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    final isReviewer = await _repo.isAdminOrDirector();
    if (!mounted) return;
    setState(() {
      _isReviewer = isReviewer;
    });
    if (isReviewer) _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final pending = await _repo.fetchPriceChangeRequests(status: 'pending');
      if (!mounted) return;
      setState(() => _pendingCount = pending.length);
    } catch (_) {/* non-fatal */}
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _repo.fetchProducts(
        search: _searchCtrl.text,
        type: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
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

  Future<void> _openForm({Product? product}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormPage(product: product)),
    );
    if (saved == true) {
      _loadProducts();
      if (_isReviewer) _loadPendingCount();
    }
  }

  Future<void> _openApprovals() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PriceApprovalsPage()),
    );
    _loadProducts();
    _loadPendingCount();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => _loadProducts(),
                      decoration: const InputDecoration(
                        hintText: 'Search products…',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_isReviewer) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Price approvals',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      ),
                      onPressed: _openApprovals,
                      icon: Badge.count(
                        count: _pendingCount,
                        isLabelVisible: _pendingCount > 0,
                        child: const Icon(Icons.flag_outlined),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  _typeChip(null, 'All'),
                  for (final type in ProductType.values) ...[
                    const SizedBox(width: 8),
                    _typeChip(type, type.label),
                  ],
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton.extended(
            heroTag: 'add-product',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('New product'),
          ),
        ),
      ],
    );
  }

  Widget _typeChip(ProductType? type, String label) {
    final selected = _typeFilter == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _typeFilter = type);
        _loadProducts();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loadProducts,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_products.isEmpty) {
      return const Center(
        child: Text(
          'No products match.\nTap "New product" to add one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: _products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final product = _products[i];
        return _ProductTile(
          product: product,
          onTap: () => _openForm(product: product),
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                foregroundColor: AppColors.primary,
                child: Icon(product.productType.icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (product.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.kes(product.salePrice),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cost ${AppFormatters.kes(product.costPrice)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
