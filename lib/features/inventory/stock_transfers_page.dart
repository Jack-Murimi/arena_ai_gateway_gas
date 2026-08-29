import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/stock_repository.dart';

/// Inter-branch stock transfers. A refill line remains linked to its matching
/// physical cylinder until the receiving branch records the empty return.
class StockTransfersPage extends StatefulWidget {
  const StockTransfersPage({super.key});

  @override
  State<StockTransfersPage> createState() => _StockTransfersPageState();
}

class _StockTransfersPageState extends State<StockTransfersPage> {
  final _db = Supabase.instance.client;
  final _stockRepository = StockRepository();

  List<Map<String, dynamic>> _transfers = [];
  bool _loading = true;
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
      final rows = await _db
          .from('stock_transfers')
          .select(
            '*, '
            'source:branches!stock_transfers_source_branch_id_fkey(name), '
            'destination:branches!stock_transfers_destination_branch_id_fkey(name), '
            'stock_transfer_items(*, product:products(name,product_type))',
          )
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _transfers = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String rpc, Map<String, dynamic> parameters) async {
    try {
      await _db.rpc(rpc, params: parameters);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Transfer updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _newTransfer() async {
    final branches = await _stockRepository.fetchBranches();
    final products = List<Map<String, dynamic>>.from(
      await _db
          .from('products')
          .select('id,name,product_type')
          .eq('is_active', true)
          .neq('product_type', 'service')
          .order('name'),
    );
    if (!mounted) return;

    String? sourceBranchId;
    String? destinationBranchId;
    String? productId;
    final quantityController = TextEditingController(text: '1');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New stock transfer',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Each refill transfers with its physical cylinder. '
                      'Record the empty cylinder return after it comes back.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: sourceBranchId,
                      decoration: const InputDecoration(
                        labelText: 'From branch',
                      ),
                      items: [
                        for (final branch in branches)
                          DropdownMenuItem(
                            value: branch['id'] as String,
                            child: Text(branch['name'] as String),
                          ),
                      ],
                      onChanged: (value) {
                        setSheetState(() => sourceBranchId = value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: destinationBranchId,
                      decoration: const InputDecoration(labelText: 'To branch'),
                      items: [
                        for (final branch in branches)
                          if (branch['id'] != sourceBranchId)
                            DropdownMenuItem(
                              value: branch['id'] as String,
                              child: Text(branch['name'] as String),
                            ),
                      ],
                      onChanged: (value) {
                        setSheetState(() => destinationBranchId = value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: productId,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: [
                        for (final product in products)
                          DropdownMenuItem(
                            value: product['id'] as String,
                            child: Text(
                              '${product['name']} · ${product['product_type']}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setSheetState(() => productId = value);
                      },
                    ),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () async {
                          final quantity =
                              int.tryParse(quantityController.text) ?? 0;
                          if (sourceBranchId == null ||
                              destinationBranchId == null ||
                              productId == null ||
                              quantity < 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Complete all fields.'),
                              ),
                            );
                            return;
                          }
                          try {
                            final transfer = await _db
                                .from('stock_transfers')
                                .insert({
                                  'source_branch_id': sourceBranchId,
                                  'destination_branch_id': destinationBranchId,
                                })
                                .select('id')
                                .single();
                            await _db.from('stock_transfer_items').insert({
                              'transfer_id': transfer['id'],
                              'product_id': productId,
                              'quantity': quantity,
                            });
                            if (sheetContext.mounted)
                              Navigator.pop(sheetContext);
                            await _load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                        child: const Text('Save draft'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    quantityController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTransfer,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('New transfer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _transfers.isEmpty
          ? const Center(child: Text('No stock transfers yet.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _transfers.length,
                itemBuilder: (_, index) => _transferCard(_transfers[index]),
              ),
            ),
    );
  }

  Widget _transferCard(Map<String, dynamic> transfer) {
    final status = transfer['status'] as String;
    final items = List<Map<String, dynamic>>.from(
      transfer['stock_transfer_items'] ?? [],
    );
    final source = (transfer['source'] as Map?)?['name'] ?? 'Source branch';
    final destination =
        (transfer['destination'] as Map?)?['name'] ?? 'Destination branch';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transfer['transfer_no'] ?? 'Transfer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(status.toUpperCase())),
              ],
            ),
            Text('$source → $destination'),
            const SizedBox(height: 8),
            for (final item in items) _itemRow(item, status),
            if (status == 'draft')
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _runAction('dispatch_stock_transfer', {
                    'p_transfer_id': transfer['id'],
                  }),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Dispatch'),
                ),
              ),
            if (status == 'dispatched')
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _runAction('receive_stock_transfer', {
                    'p_transfer_id': transfer['id'],
                  }),
                  icon: const Icon(Icons.inventory_outlined),
                  label: const Text('Confirm receipt'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item, String status) {
    final product = Map<String, dynamic>.from(item['product'] ?? {});
    final quantity = item['quantity'] as int;
    final returned = item['cylinders_returned'] as int? ?? 0;
    final isRefill = product['product_type'] == 'refill';

    return Row(
      children: [
        Expanded(
          child: Text(
            '${product['name'] ?? 'Product'} × $quantity'
            '${isRefill ? ' · cylinder returned $returned/$quantity' : ''}',
          ),
        ),
        if (isRefill &&
            (status == 'received' || status == 'returned') &&
            returned < quantity)
          TextButton(
            onPressed: () => _runAction('return_transfer_cylinders', {
              'p_transfer_item_id': item['id'],
              'p_quantity': quantity - returned,
            }),
            child: const Text('Mark returned'),
          ),
      ],
    );
  }
}
