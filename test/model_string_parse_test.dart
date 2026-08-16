import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/features/customers/models/customer.dart';
import 'package:arena_ai_gateway_gas/features/deliveries/models/delivery.dart';
import 'package:arena_ai_gateway_gas/features/inventory/models/price_change_request.dart';

void main() {
  test('Customer.fromMap tolerates stringified numbers', () {
    final customer = Customer.fromMap({
      'id': 'c1',
      'name': 'Mama Njeri',
      'credit_limit': '5000.00',
      'balance': '1500.50',
      'is_active': true,
    });
    expect(customer.creditLimit, 5000.0);
    expect(customer.balance, 1500.5);
  });

  test('Delivery.fromMap tolerates stringified amount', () {
    final delivery = Delivery.fromMap({
      'id': 'd1',
      'customer_name': 'Mama Njeri',
      'amount': '1950.00',
      'status': 'pending',
    });
    expect(delivery.amount, 1950.0);
    expect(delivery.isPending, true);
  });

  test('PriceChangeRequest.fromMap tolerates stringified prices', () {
    final request = PriceChangeRequest.fromMap({
      'id': 'p1',
      'product_id': 'prod1',
      'old_price': '1950.00',
      'new_price': '2050.00',
      'status': 'pending',
    });
    expect(request.oldPrice, 1950.0);
    expect(request.newPrice, 2050.0);
    expect(request.isPending, true);
  });
}
