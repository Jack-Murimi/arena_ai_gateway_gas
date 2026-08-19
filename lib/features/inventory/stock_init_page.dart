import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../inventory/models/product.dart';
import 'data/product_repository.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';

/// Stock reconciliation for one branch: pick the date, pick products and
/// enter the ACTUAL counted quantity. The difference vs. the recorded
/// level is saved as an audited 'opening' movement (with the date in the
/// note), so future reconciliations have a clean baseline.
class StockReconciliationPage extends StatefulWidget {
  const StockReconciliationPage({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  final String branchId;
  final String branchName;

  @override
  State<StockReconciliationPage> createState() =>
      _StockReconciliationPageState();
}

class _ReconLine {
  _ReconLine({
    required this.productId,
    required this.productName,
    required this.productType,
    this.currentQty = 0,
  }) {
    qtyCtrl = TextEditingController(text: '0');
  }

  final String productId;
  final String productName;
  final ProductType productType;
  final int currentQty;
  late final TextEditingController qtyCtrl;

  int get qty => int.tryParse(qtyCtrl.text.trim()) ?? 0;
  int get diff => qty - currentQty;

  void dispose() => qtyCtrl.dispose();
}

class _StockReconciliationPageState extends State<StockReconciliationPage> {
  final _stockRepo = StockRepository();

  DateTime _reconDate = DateTime.now();
  List<StockItem> _current = [];
  final Map<String, _ReconLine> _lines = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final current = await _stockRepo.fetchStock(branchId: widget.branchId);
      if (!mounted) return;
      setState(() {
        _current = current;
        for (final item in current) {
          if (!_lines.containsKey(item.productId)) {
            _lines[item.productId] = _ReconLine(
              productId: item.productId,
              productName: item.productName,
              productType: item.productType,
              currentQty: item.quantity,
            )..qtyCtrl.text = item.quantity.toString();
          }
        }
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
    for (final l in _lines.values) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSheet(
        products: [],
        stockLines: _lines,
        branchId: widget.branchId,
      ),
    );
    if (picked != null && mounted) {
      final pid = picked['id'] as String;
      final existing =
          _current.where((s) => s.productId == pid).firstOrNull;
      setState(() {
        if (!_lines.containsKey(pid)) {
          _lines[pid] = _ReconLine(
            productId: pid,
            productName: (picked['name'] as String?) ?? '',
            productType:
                ProductType.fromString(picked['product_type'] as String?),
            currentQty: existing?.quantity ?? 0,
          )..qtyCtrl.text = (picked['current_qty'] as int?)?.toString() ?? '0';
        }
      });
    }
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[
      for (final line in _lines.values)
        if (line.qty >= 0)
          {'product_id': line.productId, 'quantity': line.qty},
    ];
    if (items.isEmpty) {
      setState(() => _error = 'Enter at least one quantity.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _stockRepo.initStock(
        branchId: widget.branchId,
        items: items,
        date: _reconDate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reconciliation saved for ${widget.branchName} '
            '(${items.length} products, '
            '${AppFormatters.date(_reconDate)})',
          ),
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
      appBar: AppBar(
        title: Text('Reconcile — ${widget.branchName}'),
      ),
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
                        Row(
                          children: [
                            const Icon(Icons.event_outlined,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Reconciliation date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _reconDate,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setState(() => _reconDate = picked);
                                }
                              },
                              icon: const Icon(
                                  Icons.calendar_today_outlined, size: 16),
                              label: Text(
                                AppFormatters.date(_reconDate),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter the ACTUAL quantities you counted. '
                          'Differences vs. the recorded levels are logged '
                          'as audited opening movements for this date.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: _pickProduct,
                    leading: const Icon(Icons.add, color: AppColors.primary),
                    title: const Text(
                      'Add products to count',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    subtitle:
                        const Text('Pick any product from the catalogue'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 12),
                if (_lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No products yet — tap "Add products to count" to '
                      'pick items and enter their counted quantities.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final line in _lines.values) ...[
                    _lineCard(line),
                    const SizedBox(height: 6),
                  ],
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
                  label: const Text('Save reconciliation'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _lineCard(_ReconLine line) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(line.productType.icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    'Recorded ${line.currentQty}'
                    '${line.diff != 0 ? ' · diff ${line.diff > 0 ? '+' : ''}${line.diff}' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: line.diff == 0
                          ? AppColors.textSecondary
                          : line.diff > 0
                              ? AppColors.success
                              : AppColors.danger,
                      fontWeight:
                          line.diff == 0 ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: line.qtyCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Counted',
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                line.dispose();
                _lines.remove(line.productId);
              }),
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({
    required this.products,
    required this.stockLines,
    required this.branchId,
  });

  final List<Map<String, dynamic>> products;
  final Map<String, _ReconLine> stockLines;
  final String branchId;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
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
      final products = await _repo.fetchProducts(search: _searchCtrl.text);
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
    final available =
        _products.where((p) => !widget.stockLines.containsKey(p.id)).toList();
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : available.isEmpty
                      ? const Center(
                          child: Text(
                            'No more products to add — everything is in '
                            'the count.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: available.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = available[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                p.productType.icon,
                                size: 20,
                                color: AppColors.primary,
                              ),
                              title: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                p.productType.label,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: const Icon(Icons.add, size: 18),
                              onTap: () => Navigator.of(context).pop({
                                'id': p.id,
                                'name': p.name,
                                'product_type': p.productType.name,
                                'current_qty': 0,
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
