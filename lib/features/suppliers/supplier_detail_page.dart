import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'invoice_detail_page.dart';
import 'invoice_form_page.dart';
import 'models/supplier.dart';
import 'payment_form_page.dart';

/// One supplier: account summary, invoices (totals by date), payments
/// (totals by date), and the invoice list.
class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({super.key, required this.supplier});

  final SupplierSummary supplier;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  final _repo = SupplierRepository();

  List<SupplierInvoice> _invoices = [];
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
      final invoices = await _repo.fetchInvoices(widget.supplier.id);
      final payments = await _repo.fetchPayments(widget.supplier.id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
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

  Future<void> _openInvoiceForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InvoiceFormPage(supplier: widget.supplier),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openPaymentForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentFormPage(
          supplier: widget.supplier,
          invoices: _invoices,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openInvoice(SupplierInvoice invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(invoice: invoice),
      ),
    );
    _load();
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive supplier?'),
        content: Text(
          '${widget.supplier.name} will be hidden from the supplier '
          'list, but their invoices and payments stay on record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.archiveSupplier(widget.supplier.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.supplier.name} archived')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            tooltip: 'Archive supplier',
            icon: const Icon(Icons.archive_outlined),
            onPressed: _archive,
          ),
        ],
      ),
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
                    _headerCard(),
                    const SizedBox(height: 12),
                    _actionsRow(),
                    const SizedBox(height: 16),
                    _totalsCard(),
                    const SizedBox(height: 16),
                    if (_invoices.isNotEmpty) ...[
                      _invoiceTotalsByDate(),
                      const SizedBox(height: 16),
                    ],
                    if (_payments.isNotEmpty) ...[
                      _paymentTotalsByDate(),
                      const SizedBox(height: 16),
                    ],
                    _invoicesSection(),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _headerCard() {
    final s = widget.supplier;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              foregroundColor: AppColors.primary,
              child: Text(
                s.initials,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    [s.phone ?? '', s.contactPerson ?? '']
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _openInvoiceForm,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Record invoice'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openPaymentForm,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record payment'),
          ),
        ),
      ],
    );
  }

  Widget _totalsCard() {
    final s = widget.supplier;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _stat('Invoiced', AppFormatters.kes(s.invoicedTotal),
                      AppColors.textPrimary),
                ),
                Expanded(
                  child: _stat('Paid', AppFormatters.kes(s.paidTotal),
                      AppColors.success),
                ),
                Expanded(
                  child: _stat(
                    s.owes ? 'We owe' : 'Balance',
                    AppFormatters.kes(s.balance),
                    s.owes ? AppColors.warning : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _invoiceTotalsByDate() {
    final byDate = <String, double>{};
    for (final i in _invoices) {
      final key = i.invoiceDate == null
          ? 'Unknown'
          : AppFormatters.date(i.invoiceDate!);
      byDate[key] = (byDate[key] ?? 0) + i.totalAmount;
    }
    final entries = byDate.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invoice totals by date',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(e.key,
                        style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                      AppFormatters.kes(e.value),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentTotalsByDate() {
    final byDate = <String, double>{};
    for (final p in _payments) {
      final key = p.paymentDate == null
          ? 'Unknown'
          : AppFormatters.date(p.paymentDate!);
      byDate[key] = (byDate[key] ?? 0) + p.amount;
    }
    final entries = byDate.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payments by date',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                      AppFormatters.kes(e.value),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _invoicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invoices (${_invoices.length})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (_invoices.isEmpty)
          const Text(
            'No invoices recorded yet.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final invoice in _invoices) ...[
            _invoiceTile(invoice),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  Widget _invoiceTile(SupplierInvoice invoice) {
    final color = switch (invoice.status) {
      'paid' => AppColors.success,
      'partial' => AppColors.warning,
      _ => AppColors.danger,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openInvoice(invoice),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      [
                        if (invoice.invoiceDate != null)
                          AppFormatters.date(invoice.invoiceDate!),
                        invoice.branchName ?? '',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (invoice.itemsSummary != null &&
                        invoice.itemsSummary!.isNotEmpty)
                      Text(
                        invoice.itemsSummary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.kes(invoice.totalAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      invoice.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
