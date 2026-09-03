import 'package:flutter_test/flutter_test.dart';
import 'package:arena_ai_gateway_gas/features/sales/models/receipt.dart';

void main() {
  group('ReceiptLine', () {
    test('fromMap creates ReceiptLine with all fields', () {
      final map = {
        'product_name': 'Test Product',
        'quantity': 5,
        'unit_price': 1000.0,
        'line_total': 5000.0,
        'cost_price': 700.0,
        'profit': 300.0,
        'products': {'name': 'Product from join'},
      };

      final line = ReceiptLine.fromMap(map);

      expect(line.productName, 'Test Product');
      expect(line.quantity, 5);
      expect(line.unitPrice, 1000.0);
      expect(line.lineTotal, 5000.0);
      expect(line.costPrice, 700.0);
      expect(line.profit, 300.0);
    });

    test('fromMap handles null costPrice and profit', () {
      final map = {
        'product_name': 'Test Product',
        'quantity': 5,
        'unit_price': 1000.0,
        'line_total': 5000.0,
        // cost_price and profit are null
      };

      final line = ReceiptLine.fromMap(map);

      expect(line.productName, 'Test Product');
      expect(line.quantity, 5);
      expect(line.costPrice, isNull);
      expect(line.profit, isNull);
    });

    test('fromMap uses product name from join if product_name is null', () {
      final map = {
        'product_name': null,
        'quantity': 5,
        'unit_price': 1000.0,
        'line_total': 5000.0,
        'products': {'name': 'Product from join'},
      };

      final line = ReceiptLine.fromMap(map);

      expect(line.productName, 'Product from join');
    });

    test('fromMap handles missing products join', () {
      final map = {
        'product_name': null,
        'quantity': 5,
        'unit_price': 1000.0,
        'line_total': 5000.0,
        // products is null
      };

      final line = ReceiptLine.fromMap(map);

      expect(line.productName, '');
    });
  });

  group('ReceiptData', () {
    test('default values work correctly', () {
      final receipt = ReceiptData(
        saleId: 'sale-123',
        invoiceNo: 'INV-001',
      );

      expect(receipt.saleId, 'sale-123');
      expect(receipt.invoiceNo, 'INV-001');
      expect(receipt.total, 0);
      expect(receipt.amountPaid, 0);
      expect(receipt.balanceDue, 0);
      expect(receipt.paymentStatus, 'paid');
      expect(receipt.totalCost, 0);
      expect(receipt.totalProfit, 0);
      expect(receipt.profitMarginPercentage, 0);
      expect(receipt.hasFifoData, false);
      expect(receipt.items, isEmpty);
    });

    test('hasFifoData returns true when cost or profit is positive', () {
      final receipt1 = ReceiptData(
        saleId: 'sale-1',
        invoiceNo: 'INV-1',
        totalCost: 1000,
        totalProfit: 500,
      );
      expect(receipt1.hasFifoData, true);

      final receipt2 = ReceiptData(
        saleId: 'sale-2',
        invoiceNo: 'INV-2',
        totalCost: 1000,
        totalProfit: 0,
      );
      expect(receipt2.hasFifoData, true);

      final receipt3 = ReceiptData(
        saleId: 'sale-3',
        invoiceNo: 'INV-3',
        totalCost: 0,
        totalProfit: 500,
      );
      expect(receipt3.hasFifoData, true);

      final receipt4 = ReceiptData(
        saleId: 'sale-4',
        invoiceNo: 'INV-4',
        totalCost: 0,
        totalProfit: 0,
      );
      expect(receipt4.hasFifoData, false);
    });

    test('calculatedProfitMarginPercentage calculates correctly', () {
      // Test with positive profit
      final receipt1 = ReceiptData(
        saleId: 'sale-1',
        invoiceNo: 'INV-1',
        total: 10000,
        totalProfit: 2500,
      );
      expect(receipt1.calculatedProfitMarginPercentage, 25.0);

      // Test with zero total
      final receipt2 = ReceiptData(
        saleId: 'sale-2',
        invoiceNo: 'INV-2',
        total: 0,
        totalProfit: 1000,
      );
      expect(receipt2.calculatedProfitMarginPercentage, 0);

      // Test with negative profit (loss)
      final receipt3 = ReceiptData(
        saleId: 'sale-3',
        invoiceNo: 'INV-3',
        total: 10000,
        totalProfit: -1000,
      );
      expect(receipt3.calculatedProfitMarginPercentage, -10.0);

      // Test with zero profit
      final receipt4 = ReceiptData(
        saleId: 'sale-4',
        invoiceNo: 'INV-4',
        total: 10000,
        totalProfit: 0,
      );
      expect(receipt4.calculatedProfitMarginPercentage, 0);
    });

    test('calculatedProfitMarginPercentage handles division by zero', () {
      final receipt = ReceiptData(
        saleId: 'sale-5',
        invoiceNo: 'INV-5',
        total: 0,
        totalProfit: 0,
      );
      expect(receipt.calculatedProfitMarginPercentage, 0);
    });
  });
}
