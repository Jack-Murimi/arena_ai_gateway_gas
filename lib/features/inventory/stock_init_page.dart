import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../inventory/models/product.dart';
import 'data/product_repository.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';

/// Stock reconciliation for one branch: pick the date, then for every
/// brand × size enter the counted refills (with gas) and empties
/// (without gas). The Total column shows the physical cylinders live.
/// Differences vs. recorded levels are saved as audited 'opening'
/// movements with the date in the note.
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

/// One brand × size row with its refill (gas) and empty (cylinder)
/// products.
class _ComboRow {
  _ComboRow({
    required this.brand,
    required this.sizeKg,
  }) {
    refillCtrl = TextEditingController(text: '0');
    emptyCtrl = TextEditingController(text: '0');
  }

  final String brand;
  final double? sizeKg;
  String? refillProductId;
  String? emptyProductId;
  late final TextEditingController refillCtrl;
  late final TextEditingController emptyCtrl;

  int get refill => int.tryParse(refillCtrl.text.trim()) ?? 0;
  int get empty => int.tryParse(emptyCtrl.text.trim()) ?? 0;
  int get total => refill + empty;

  void dispose() {
    refillCtrl.dispose();
    emptyCtrl.dispose();
  }
}

class _StockReconciliationPageState extends State<StockReconciliationPage> {
  final _stockRepo = StockRepository();
  final _productRepo = ProductRepository();

  DateTime _reconDate = DateTime.now();
  final Map<String, _ComboRow> _rows = {}; // key: brand|size
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
      final results = await Future.wait([
        _stockRepo.fetchStock(branchId: widget.branchId),
        _productRepo.fetchProducts(),
      ]);
      final current = results[0] as List<StockItem>;
      final products = results[1] as List<Product>;

      final qtyByProduct = {
        for (final s in current) s.productId: s.quantity,
      };

      final rows = <String, _ComboRow>{};
      for (final p in products) {
        if (p.productType != ProductType.refill &&
            p.productType != ProductType.cylinder) {
          continue;
        }
        final key = '${p.brand ?? 'Other'}|${p.sizeKg}';
        final row = rows.putIfAbsent(
          key,
          () => _ComboRow(
            brand: p.brand ?? 'Other',
            sizeKg: p.sizeKg,
          ),
        );
        if (p.productType == ProductType.refill) {
          row.refillProductId = p.id;
        } else {
          row.emptyProductId = p.id;
        }
      }

      // prefill with current recorded quantities
      for (final row in rows.values) {
        if (row.refillProductId != null) {
          row.refillCtrl.text =
              (qtyByProduct[row.refillProductId] ?? 0).toString();
        }
        if (row.emptyProductId != null) {
          row.emptyCtrl.text =
              (qtyByProduct[row.emptyProductId] ?? 0).toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
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
    for (final r in _rows.values) {
      r.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Grouping helpers
  // -------------------------------------------------------------------------

  List<double?> get _sizes {
    final set = <double>{};
    for (final r in _rows.values) {
      if (r.sizeKg != null) set.add(r.sizeKg!);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<_ComboRow> _rowsFor(double? size) => _rows.values
      .where((r) => r.sizeKg == size)
      .toList()
    ..sort((a, b) => a.brand.toLowerCase().compareTo(b.brand.toLowerCase()));

  int get _totalRefill =>
      _rows.values.fold<int>(0, (s, r) => s + r.refill);
  int get _totalEmpty =>
      _rows.values.fold<int>(0, (s, r) => s + r.empty);
  int get _totalCylinders => _totalRefill + _totalEmpty;

  static String _sizeLabel(double? size) => size == null
      ? ''
      : (size == size.roundToDouble()
          ? '${size.toInt()}kg'
          : '${size}kg');

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[
      for (final row in _rows.values) ...[
        if (row.refillProductId != null)
          {'product_id': row.refillProductId, 'quantity': row.refill},
        if (row.emptyProductId != null)
          {'product_id': row.emptyProductId, 'quantity': row.empty},
      ],
    ];
    if (items.isEmpty) {
      setState(() => _error = 'Nothing to save.');
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
            '(${items.length} entries, '
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

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reconcile — ${widget.branchName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off,
                            color: AppColors.danger, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _headerCard(),
                    const SizedBox(height: 12),
                    _totalsCard(),
                    const SizedBox(height: 12),
                    for (final size in _sizes) ...[
                      _sizeHeader(size),
                      const SizedBox(height: 6),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final row in _rowsFor(size)) ...[
                              _rowTile(row),
                              if (row != _rowsFor(size).last)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
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

  Widget _headerCard() {
    return Card(
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
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    AppFormatters.date(_reconDate),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the ACTUAL quantities you counted — refills (with '
              'gas) and empties (without gas). The Total column shows the '
              'physical cylinders. Differences are logged as audited '
              'opening movements.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _stat('With gas', '$_totalRefill', AppColors.primary),
            ),
            Expanded(
              child: _stat('Empty', '$_totalEmpty', AppColors.textPrimary),
            ),
            Expanded(
              child: _stat('Total cylinders', '$_totalCylinders',
                  AppColors.accent, big: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color,
      {bool big = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: big ? 19 : 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
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
    );
  }

  Widget _sizeHeader(double? size) {
    final rows = _rowsFor(size);
    final sizeTotal = rows.fold<int>(0, (s, r) => s + r.total);
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$sizeTotal total',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_ComboRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
          _qtyField(
            row.refillCtrl,
            label: 'Gas',
            color: AppColors.primary,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(width: 6),
          _qtyField(
            row.emptyCtrl,
            label: 'Empty',
            color: AppColors.textPrimary,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  '${row.total}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: row.total > 0
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyField(
    TextEditingController controller, {
    required String label,
    required Color color,
    required VoidCallback onChanged,
  }) {
    return SizedBox(
      width: 58,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: (_) => onChanged(),
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: FontWeight.w700,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }
}
