import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'data/stock_repository.dart';
import 'models/stock_item.dart';

/// Monthly stock initialization for one branch: set the opening quantity
/// of every product. Logged as 'opening' stock movements (audit trail).
class StockInitPage extends StatefulWidget {
  const StockInitPage({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  final String branchId;
  final String branchName;

  @override
  State<StockInitPage> createState() => _StockInitPageState();
}

class _StockInitPageState extends State<StockInitPage> {
  final _repo = StockRepository();

  List<StockItem> _current = [];
  final Map<String, TextEditingController> _qtyCtrls = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

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
      final current = await _repo.fetchStock(branchId: widget.branchId);
      if (!mounted) return;
      setState(() {
        _current = current;
        for (final item in current) {
          _qtyCtrls[item.productId] = TextEditingController(
            text: item.quantity.toString(),
          );
        }
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
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (final item in _current) {
      final qty = int.tryParse(_qtyCtrls[item.productId]!.text.trim());
      if (qty != null && qty > 0) {
        items.add({'product_id': item.productId, 'quantity': qty});
      }
    }
    if (items.isEmpty) {
      setState(() => _error = 'Enter at least one quantity above zero.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      await _repo.initStock(branchId: widget.branchId, items: items);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = 'Stock saved for ${widget.branchName} (${items.length} products).';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_success!)),
      );
      Navigator.of(context).pop(true);
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
        title: Text('Init stock — ${widget.branchName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _current.isEmpty
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
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Set the opening quantities for this month. '
                              'Values replace the current stock level.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (_current.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'No products initialized yet — enter the '
                                'starting quantities below.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_current.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No stock rows for this branch yet. '
                          'Add products below after initializing once.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final item in _current) _row(item),
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
                      label: Text(
                        'Save stock for ${widget.branchName}',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _row(StockItem item) {
    final ctrl = _qtyCtrls[item.productId]!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(item.productType.icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    '${item.productType.label} · '
                    'current ${item.quantity}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Qty',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
