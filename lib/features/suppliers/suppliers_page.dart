import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'invoice_form_page.dart';
import 'models/supplier.dart';
import 'supplier_detail_page.dart';
import 'supplier_form_page.dart';
import 'supplier_return_form_page.dart';

/// All suppliers with their account balances.
class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _repo = SupplierRepository();
  final _searchCtrl = TextEditingController();

  List<SupplierSummary> _suppliers = [];
  String _statusFilter = 'all'; // all | active | archived
  String _sortBy = 'name'; // name | balance | recent
  bool _loading = true;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suppliers = await _repo.fetchSuppliers();
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

  List<SupplierSummary> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    final list = _suppliers.where((s) {
      final matchesStatus = switch (_statusFilter) {
        'active' => s.isActive,
        'archived' => !s.isActive,
        _ => true,
      };
      if (!matchesStatus) return false;
      if (term.isEmpty) return true;
      return s.name.toLowerCase().contains(term);
    }).toList();
    switch (_sortBy) {
      case 'balance':
        list.sort((a, b) => b.balance.compareTo(a.balance));
      case 'recent':
        list.sort((a, b) => a.name.compareTo(b.name)); // stable fallback
      default:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  /// One-tap actions: pick a supplier, then go to the requested form.
  Future<void> _pickSupplierFor(String action) async {
    final active = _suppliers.where((s) => s.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a supplier first.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<SupplierSummary>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SupplierSheet(suppliers: active),
    );
    if (picked == null || !mounted) return;

    switch (action) {
      case 'invoice':
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => InvoiceFormPage(supplier: picked),
          ),
        );
      case 'return':
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => SupplierReturnFormPage(supplier: picked),
          ),
        );
    }
    if (mounted) _load();
  }

  Future<void> _openForm({SupplierSummary? supplier}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            supplier == null ? const SupplierFormPage() : SupplierFormPage(supplier: supplier),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(SupplierSummary supplier) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SupplierDetailPage(supplier: supplier)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search suppliers…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Sort suppliers',
                icon: const Icon(Icons.sort),
                onSelected: (v) => setState(() => _sortBy = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'name',
                    child: Row(children: [
                      Icon(Icons.sort_by_alpha, size: 18),
                      SizedBox(width: 8),
                      Text('Name A–Z'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'balance',
                    child: Row(children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Owed (highest first)'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'recent',
                    child: Row(children: [
                      Icon(Icons.schedule, size: 18),
                      SizedBox(width: 8),
                      Text('Recently added'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (value, label) in [
                ('all', 'All'),
                ('active', 'Active'),
                ('archived', 'Archived'),
              ]) ...[
                if (value != 'all') const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(label),
                  selected: _statusFilter == value,
                  onSelected: (_) => setState(() => _statusFilter = value),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: _statusFilter == value
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('Supplier',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickSupplierFor('invoice'),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Invoice',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickSupplierFor('return'),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Return',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
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
    if (_suppliers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No suppliers yet.\nTap "New supplier" to add one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No suppliers match this filter.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _supplierTile(filtered[i]),
      ),
    );
  }

  Widget _supplierTile(SupplierSummary supplier) {
    return Card(
      margin: EdgeInsets.zero,
      color: supplier.isActive ? null : AppColors.surface.withValues(alpha: 0.6),
      child: InkWell(
        onTap: () => _openDetail(supplier),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                foregroundColor: AppColors.primary,
                child: Text(
                  supplier.initials,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: supplier.isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      [
                        supplier.phone ?? '',
                        supplier.contactPerson ?? '',
                        if (!supplier.isActive) 'Archived',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.kes(supplier.balance),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: supplier.owes
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                  Text(
                    supplier.owes ? 'We owe' : 'Fully paid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: supplier.owes
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierSheet extends StatefulWidget {
  const _SupplierSheet({required this.suppliers});

  final List<SupplierSummary> suppliers;

  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SupplierSummary> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.suppliers;
    return widget.suppliers
        .where((s) => s.name.toLowerCase().contains(term))
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
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search suppliers…',
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
              child: ListView.separated(
                controller: scrollController,
                itemCount: _filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = _filtered[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      foregroundColor: AppColors.primary,
                      child: Text(
                        s.initials,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      s.owes
                          ? 'Balance ${AppFormatters.kes(s.balance)}'
                          : 'Fully paid',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => Navigator.of(context).pop(s),
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
