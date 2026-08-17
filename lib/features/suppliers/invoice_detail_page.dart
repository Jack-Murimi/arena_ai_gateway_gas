import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'models/supplier.dart';

/// One supplier invoice: header, line items posted, allocated payments.
class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({super.key, required this.invoice});

  final SupplierInvoice invoice;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  final _repo = SupplierRepository();

  List<SupplierInvoiceItem> _items = [];
  List<SupplierPayment> _payments = [];
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
      final items = await _repo.fetchInvoiceItems(widget.invoice.id);
      List<SupplierPayment> payments = [];
      try {
        final all = await _repo.fetchPayments(widget.invoice.supplierId);
        payments =
            all.where((p) => p.invoiceId == widget.invoice.id).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _items = items;
        _payments = payments;
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
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final color = switch (invoice.status) {
      'paid' => AppColors.success,
      'partial' => AppColors.warning,
      _ => AppColors.danger,
    };

    return Scaffold(
      appBar: AppBar(title: Text(invoice.invoiceNo)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off,
                            color: AppColors.danger, size: 40),
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
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    invoice.invoiceNo,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    invoice.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _detailRow('Supplier', invoice.supplierName ?? '—'),
                            _detailRow(
                              'Invoice date',
                              invoice.invoiceDate == null
                                  ? '—'
                                  : AppFormatters.date(invoice.invoiceDate!),
                            ),
                            _detailRow(
                                'Delivered to', invoice.branchName ?? '—'),
                            _detailRow('Items', '${invoice.itemCount}'),
                            const Divider(height: 20),
                            Row(
                              children: [
                                const Text(
                                  'Total amount',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                Text(
                                  AppFormatters.kes(invoice.totalAmount),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            if (invoice.notes != null &&
                                invoice.notes!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                invoice.notes!,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Products posted (${_items.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_items.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No items on this invoice.'),
                        ),
                      )
                    else
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              for (final item in _items)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.productName ?? 'Product',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13.5),
                                        ),
                                      ),
                                      Text(
                                        '${item.quantity} × '
                                        '${AppFormatters.kes(item.unitCost)}',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 90,
                                        child: Text(
                                          AppFormatters.kes(item.lineTotal),
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_payments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Payments allocated',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              for (final p in _payments)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          [
                                            p.paymentDate == null
                                                ? ''
                                                : AppFormatters.date(
                                                    p.paymentDate!),
                                            p.method.toUpperCase(),
                                            p.reference ?? '',
                                          ].where((s) => s.isNotEmpty).join(' · '),
                                          style: const TextStyle(
                                              fontSize: 12.5),
                                        ),
                                      ),
                                      Text(
                                        AppFormatters.kes(p.amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.success,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
