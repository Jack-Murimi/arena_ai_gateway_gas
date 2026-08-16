import 'package:flutter_test/flutter_test.dart';

import 'package:arena_ai_gateway_gas/features/inventory/models/product.dart';

void main() {
  test('ProductType.fromString maps correctly', () {
    expect(ProductType.fromString('refill'), ProductType.refill);
    expect(ProductType.fromString('cylinder'), ProductType.cylinder);
    expect(ProductType.fromString('accessory'), ProductType.accessory);
    expect(ProductType.fromString('service'), ProductType.service);
    expect(ProductType.fromString(null), ProductType.refill);
    expect(ProductType.fromString('bogus'), ProductType.refill);
  });

  test('refill sizes include the full catalogue', () {
    expect(Product.refillSizes, [3, 6, 13, 22.5, 35, 45, 50]);
  });

  test('formatSizeKg handles integers and decimals', () {
    expect(Product.formatSizeKg(13), '13kg');
    expect(Product.formatSizeKg(22.5), '22.5kg');
    expect(Product.formatSizeKg(null), '');
  });

  test('Product.fromMap reads product_type', () {
    final product = Product.fromMap({
      'id': 'abc',
      'name': 'Refill 13kg',
      'product_type': 'cylinder',
      'size_kg': 13,
      'sale_price': 1950,
      'cost_price': 1700,
    });
    expect(product.productType, ProductType.cylinder);
    expect(product.displayName, 'Refill 13kg');
  });

  test('subtitle skips size/brand already in name', () {
    final afrigas = Product.fromMap({
      'id': '1',
      'name': 'Afrigas 13kg',
      'product_type': 'refill',
      'size_kg': 13,
      'brand': 'Afrigas',
    });
    expect(afrigas.subtitle, 'Refill');

    final regulator = Product.fromMap({
      'id': '2',
      'name': 'Regulator',
      'product_type': 'accessory',
      'brand': 'Kabsons',
    });
    expect(regulator.subtitle, 'Accessory · Kabsons');
  });
}
