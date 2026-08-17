import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'models/supplier.dart';
import 'supplier_detail_page.dart';
import 'supplier_form_page.dart';

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
    return _suppliers.where((s) {
      final matchesStatus = switch (_statusFilter) {
        'active' => s.isActive,
        'archived' => !s.isActive,
        _ => true,
      };
      if (!matchesStatus) return false;
      if (term.isEmpty) return true;
      return s.name.toLowerCase().contains(term);
    }).toList();
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
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
            Expanded(child: _buildBody()),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton.extended(
            heroTag: 'add-supplier',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('New supplier'),
          ),
        ),
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
