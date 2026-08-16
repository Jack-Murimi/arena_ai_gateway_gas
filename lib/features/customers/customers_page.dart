import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.people_outline,
      title: 'Customers',
      description:
          'Customer registry with credit accounts, ledger history, cylinder '
          'deposits and debt collection.',
      upcoming: [
        'Add/edit customers with phone & credit limit',
        'Credit sales — balances tracked per customer',
        'Customer ledger (payments, invoices, receipts)',
        'Cylinder deposits & returns per customer',
        'Debtors report',
      ],
    );
  }
}
