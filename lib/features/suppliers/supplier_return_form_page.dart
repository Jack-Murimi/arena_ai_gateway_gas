import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'models/supplier.dart';

/// Return damaged goods to a supplier (stock-out + credit on their account).
class SupplierReturnFormPage extends StatefulWidget {
  const SupplierReturnFormPage({super.key, required this.supplier});

  final SupplierSummary supplier;

  @override
  State<SupplierReturnFormPage> createState() => _SupplierReturnFormPageState();
}

class _ReturnLine {
  _ReturnLine({
    required this.productId,
    required this.productName,
  }) {
    qtyCtrl = TextEditingController(text: '1');
    costCtrl = TextEditingController();
  }

  final String productId;
  final String productName;
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;

  int get quantity => int.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get unitCost => double.tryParse(costCtrl.text.trim()) ?? 0;
  double get lineTotal => quantity * unitCost;

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}

class _SupplierReturnFormPageState extends State<SupplierReturnFormPage> {
  final _repo = SupplierRepository();
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _products = [];
  String? _branchId;
  DateTime _returnDate = DateTime.now();
  String _reason = 'damaged';

  final List<_ReturnLine> _lines = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _reasons = ['damaged', 'expired', 'wrong_stock', 'other'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.fetchBranches(),
        _repo.fetchProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0];
        _products = results[1];
        _branchId =
            _branches.isEmpty ? null : (_branches.first['id'] as String);
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
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSheet(products: _products),
    );
    if (picked != null && mounted) {
      setState(() {
        _lines.add(_ReturnLine(
          productId: picked['id'] as String,
          productName: (picked['name'] as String?) ?? '',
        )..costCtrl.text =
            ((picked['cost_price'] as num?) ?? 0).toStringAsFixed(0));
      });
    }
  }

  double get _total =>
      _lines.fold<double>(0, (sum, l) => sum + l.lineTotal);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_branchId == null) {
      setState(() => _error = 'Select the branch.');
      return;
    }
    final items = <Map<String, dynamic>>[
      for (final l in _lines)
        if (l.quantity > 0)
          {
            'product_id': l.productId,
            'quantity': l.quantity,
            'unit_cost': l.unitCost,
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
      final result = await _repo.saveReturn(
        supplierId: widget.supplier.id,
        branchId: _branchId!,
        returnDate: _returnDate,
        reason: _reason,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: items,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['return_no']} saved — '
            '${AppFormatters.kes((result['total_amount'] as num?)?.toDouble() ?? 0)} '
            'credited to ${widget.supplier.name}',
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
      appBar: AppBar(title: Text('Return to ${widget.supplier.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _returnDate,
                                      firstDate: DateTime(2024),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null) {
                                      setState(() => _returnDate = picked);
                                    }
                                  },
                                  icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18),
                                  label: Text(
                                      AppFormatters.date(_returnDate)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _branchId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch *',
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final b in _branches)
                                      DropdownMenuItem(
                                        value: b['id'] as String,
                                        child: Text(b['name'] as String),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _branchId = v),
                                  validator: (v) => v == null
                                      ? 'Select the branch'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _reason,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Reason',
                              isDense: true,
                              prefixIcon: Icon(Icons.report_problem_outlined,
                                  size: 20),
                            ),
                            items: [
                              for (final r in _reasons)
                                DropdownMenuItem(
                                  value: r,
                                  child: Text(
                                    r.replaceAll('_', ' ').toUpperCase(),
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _reason = v ?? 'damaged'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesCtrl,
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
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      onTap: _pickProduct,
                      leading:
                          const Icon(Icons.add, color: AppColors.primary),
                      title: const Text(
                        'Add damaged items',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in _lines) ...[
                    _lineCard(line),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Text(
                            'Credit total',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
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
                        : const Icon(Icons.assignment_return_outlined),
                    label: const Text('Save return'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _lineCard(_ReturnLine line) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            SizedBox(
              width: 64,
              child: TextField(
                controller: line.qtyCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Qty'),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 88,
              child: TextField(
                controller: line.costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Cost'),
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
                            AppFormatters.kes(
                                ((p['cost_price'] as num?) ?? 0).toDouble()),
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
