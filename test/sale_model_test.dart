import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/features/sales/models/sale.dart';

void main() {
  test('SaleRecord.fromMap tolerates stringified numbers', () {
    final sale = SaleRecord.fromMap({
      'id': 's1',
      'invoice_no': 'INV-2026-0001',
      'sale_date': '2026-08-16',
      'branch_name': 'Nextgen',
      'customer_name': 'Mama Njeri',
      'subtotal': '1950.00',
      'discount': '0',
      'tax': '0',
      'total': '1950.00',
      'payment_status': 'paid',
    });
    expect(sale.invoiceNo, 'INV-2026-0001');
    expect(sale.total, 1950.0);
    expect(sale.isPaid, true);
    expect(sale.saleDate, DateTime(2026, 8, 16));
  });
}
