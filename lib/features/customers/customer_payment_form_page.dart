import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/customer_repository.dart';
import 'models/customer.dart';

/// Record a payment against a customer's account.
class CustomerPaymentFormPage extends StatefulWidget {
  const CustomerPaymentFormPage({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerPaymentFormPage> createState() => _CustomerPaymentFormPageState();
}

class _CustomerPaymentFormPageState extends State<CustomerPaymentFormPage> {
  final _repo = CustomerRepository();
  final _formKey = GlobalKey<FormState>();

  final _amountCtrl = TextEditingController();
  final _mpesaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _paymentDate = DateTime.now();
  String _method = 'cash';
  bool _saving = false;
  String? _error;

  static const _methods = ['cash', 'mpesa', 'pdq', 'cheque'];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _mpesaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

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
      final result = await _repo.recordPayment(
        customerId: widget.customer.id,
        amount: amount,
        method: _method,
        mpesaCode: _mpesaCtrl.text.trim().isEmpty
            ? null
            : _mpesaCtrl.text.trim(),
        paymentDate: _paymentDate,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      final balanceAfter =
          (result['balance_after'] as num?)?.toDouble() ?? 0;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment of ${AppFormatters.kes(amount)} recorded — '
            'balance now ${AppFormatters.kes(balanceAfter)}',
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
      appBar: AppBar(title: Text('Payment from ${widget.customer.name}')),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (widget.customer.balance > 0.001
                                ? AppColors.warning
                                : AppColors.success)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Current balance: '
                        '${AppFormatters.kes(widget.customer.balance)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: widget.customer.balance > 0.001
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        prefixIcon:
                            Icon(Icons.account_balance_wallet_outlined),
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
                    if (_method == 'mpesa') ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _mpesaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'M-Pesa code',
                          hintText: 'e.g. SGH1234XYZ',
                          prefixIcon: Icon(Icons.sms_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _noteCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.notes),
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
