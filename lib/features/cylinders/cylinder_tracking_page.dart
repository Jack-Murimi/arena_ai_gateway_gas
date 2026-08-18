import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../auth/auth_controller.dart';
import '../customers/data/customer_repository.dart';
import '../customers/models/customer.dart';
import '../inventory/models/product.dart';
import 'data/cylinder_repository.dart';
import 'models/cylinder_models.dart';

/// Cylinders left with customers: who has what, who left it, when to
/// go back for it. Plus logging new ones.
class CylinderTrackingPage extends StatefulWidget {
  const CylinderTrackingPage({super.key});

  @override
  State<CylinderTrackingPage> createState() => _CylinderTrackingPageState();
}

class _CylinderTrackingPageState extends State<CylinderTrackingPage> {
  final _repo = CylinderRepository();

  List<CylinderTracking> _items = [];
  String _status = 'out';
  bool _loading = true;
  String? _error;
  String? _busyId;

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
      final items = await _repo.fetchTracking(status: _status);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _markReturned(CylinderTracking item) async {
    setState(() => _busyId = item.id);
    try {
      await _repo.markReturned(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.productName ?? 'Cylinder'} collected from '
              '${item.customerName ?? 'customer'}'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _logLeft() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _LogCylinderLeftPage()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cylinder tracking'),
        actions: [
          IconButton(
            tooltip: 'Log cylinder left',
            icon: const Icon(Icons.add),
            onPressed: _logLeft,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final (value, label) in [
                  ('out', 'Out with customers'),
                  ('returned', 'Collected'),
                ]) ...[
                  if (value != 'out') const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) {
                      setState(() => _status = value);
                      _load();
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _status == value
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _status == 'out'
                ? 'No cylinders out with customers. 🎉\n\nUse the + button '
                    'to log a cylinder left behind.'
                : 'Nothing collected yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _trackingCard(_items[i]),
    );
  }

  Widget _trackingCard(CylinderTracking item) {
    final followUpColor = item.isOverdue
        ? AppColors.danger
        : item.isDueSoon
            ? AppColors.warning
            : AppColors.textSecondary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.productName ?? 'Cylinder',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (item.quantity > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'x${item.quantity}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _meta(Icons.person_outline, item.customerName ?? '—'),
            if (item.locationName != null && item.locationName!.isNotEmpty)
              _meta(Icons.place_outlined, item.locationName!),
            _meta(
              Icons.person_pin_outlined,
              'Left by ${item.leftByName ?? '—'}'
              '${item.leftAt != null ? ' · ${AppFormatters.dateTime(item.leftAt!)}' : ''}',
            ),
            if (item.invoiceNo != null)
              _meta(Icons.receipt_outlined, 'Sale ${item.invoiceNo}'),
            if (item.followUpDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      item.isOverdue
                          ? Icons.error_outline
                          : Icons.event_outlined,
                      size: 15,
                      color: followUpColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.isOverdue
                          ? 'Follow-up was ${AppFormatters.date(item.followUpDate!)} — OVERDUE'
                          : 'Follow-up ${AppFormatters.date(item.followUpDate!)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: followUpColor,
                      ),
                    ),
                  ],
                ),
              ),
            if (item.note != null && item.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.note!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            if (item.isOut) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _busyId == item.id
                      ? null
                      : () => _markReturned(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  ),
                  icon: _busyId == item.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Collected'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone form: log a cylinder left with a customer (no sale).
class _LogCylinderLeftPage extends StatefulWidget {
  const _LogCylinderLeftPage();

  @override
  State<_LogCylinderLeftPage> createState() => _LogCylinderLeftPageState();
}

class _LogCylinderLeftPageState extends State<_LogCylinderLeftPage> {
  final _repo = CylinderRepository();
  final _customerRepo = CustomerRepository();
  final _noteCtrl = TextEditingController();

  List<Customer> _customers = [];
  List<Product> _cylinders = [];
  String? _customerId;
  String? _locationId;
  String? _productId;
  int _qty = 1;
  DateTime _followUp = DateTime.now().add(const Duration(days: 7));
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final customers = await _customerRepo.fetchCustomers();
      final cylinders = await _customerRepo.fetchProducts();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _cylinders = cylinders
            .where((p) => p.productType == ProductType.cylinder)
            .toList();
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
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_customerId == null || _productId == null) {
      setState(() => _error = 'Select the customer and the cylinder.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final branchId =
          context.read<AuthController>().branchId;
      await _repo.logCylinderLeft(
        customerId: _customerId!,
        locationId: _locationId,
        productId: _productId!,
        quantity: _qty,
        followUpDate: _followUp,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        branchId: branchId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cylinder left logged')),
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
      appBar: AppBar(title: const Text('Log cylinder left')),
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
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _customerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Customer *',
                            isDense: true,
                          ),
                          hint: const Text('Select customer'),
                          items: [
                            for (final c in _customers)
                              DropdownMenuItem(
                                value: c.id,
                                child:
                                    Text(c.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _customerId = v;
                            _locationId = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _productId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cylinder *',
                            isDense: true,
                          ),
                          hint: const Text('Select cylinder'),
                          items: [
                            for (final c in _cylinders)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _productId = v),
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
                              }),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 22),
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
                              onPressed: () => setState(() => _qty++),
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 22),
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
                              lastDate: DateTime.now().add(
                                  const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() => _followUp = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text(
                            'Follow-up: ${AppFormatters.date(_followUp)}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                            isDense: true,
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
                      : const Icon(Icons.save_outlined),
                  label: const Text('Log cylinder left'),
                ),
              ],
            ),
    );
  }
}
