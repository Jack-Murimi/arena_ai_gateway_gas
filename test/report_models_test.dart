import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/features/reports/models/report_models.dart';

void main() {
  test('DailySalesRow tolerates stringified numbers', () {
    final row = DailySalesRow.fromMap({
      'sale_date': '2026-08-16',
      'branch_name': 'Nextgen',
      'sales_count': '3',
      'total_sales': '6000.00',
      'paid_total': '4000.00',
      'unpaid_total': '2000.00',
      'partial_total': '0',
    });
    expect(row.salesCount, 3);
    expect(row.totalSales, 6000.0);
    expect(row.paidTotal, 4000.0);
    expect(row.unpaidTotal, 2000.0);
  });

  test('BestSellerRow + DebtorRow tolerate stringified numbers', () {
    final best = BestSellerRow.fromMap({
      'product_name': '13kg Afrigas refill',
      'product_type': 'refill',
      'quantity_sold': '12',
      'revenue': '24000.00',
    });
    expect(best.quantitySold, 12);
    expect(best.revenue, 24000.0);

    final debtor = DebtorRow.fromMap({
      'id': 'c1',
      'name': 'Mama Njeri',
      'balance': '1500.50',
      'credit_limit': '5000',
    });
    expect(debtor.balance, 1500.5);
    expect(debtor.creditLimit, 5000.0);
  });

  test('ValuationRow tolerates stringified numbers', () {
    final v = ValuationRow.fromMap({
      'branch_name': 'Jamhuri',
      'product_count': '42',
      'cost_value': '150000.00',
      'retail_value': '180000.00',
    });
    expect(v.productCount, 42);
    expect(v.costValue, 150000.0);
    expect(v.retailValue, 180000.0);
  });
}
