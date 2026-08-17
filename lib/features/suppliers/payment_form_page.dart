import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/supplier_repository.dart';
import 'models/supplier.dart';

/// Record a payment to a supplier (optionally allocated to an invoice).
class PaymentFormPage extends StatefulWidget {
  const PaymentFormPage({
    super.key,
    required this.supplier,
    required this.invoices,
  });

  final SupplierSummary supplier;
  final List<SupplierInvoice> invoices;

  @override
  State<PaymentFormPage> createState() => _PaymentFormPageState();
}

class _PaymentFormPageState extends State<PaymentFormPage> {
  final _repo = SupplierRepository();
  final _formKey = GlobalKey<FormState>();

  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();

  DateTime _paymentDate = DateTime.now();
  String _method = 'cash';
  String? _invoiceId;

  bool _saving = false;
  String? _error;

  static const _methods = ['cash', 'mpesa', 'bank', 'cheque'];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  List<SupplierInvoice> get _openInvoices => widget.invoices
      .where((i) => !i.isPaid)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.recordPayment(
        supplierId: widget.supplier.id,
        invoiceId: _invoiceId,
        amount: amount,
        paymentDate: _paymentDate,
        method: _method,
        reference: _referenceCtrl.text.trim().isEmpty
            ? null
            : _referenceCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment of ${AppFormatters.kes(amount)} to '
            '${widget.supplier.name} recorded',
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
      appBar: AppBar(title: Text('Payment to ${widget.supplier.name}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount KSh *',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (v) {
                        final value = double.tryParse((v ?? '').trim());
                        if (value == null || value <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _paymentDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _paymentDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(AppFormatters.date(_paymentDate)),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: [
                        for (final m in _methods)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m.toUpperCase()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _method = v ?? 'cash'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: _invoiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Allocate to invoice (optional)',
                        prefixIcon: Icon(Icons.receipt_outlined),
                      ),
                      hint: const Text('None — general payment'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None — general payment'),
                        ),
                        for (final i in _openInvoices)
                          DropdownMenuItem<String?>(
                            value: i.id,
                            child: Text(
                              '${i.invoiceNo} · ${AppFormatters.kes(i.totalAmount)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _invoiceId = v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _referenceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reference (optional)',
                        hintText: 'e.g. M-Pesa code, cheque no.',
                        prefixIcon: Icon(Icons.tag_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}
