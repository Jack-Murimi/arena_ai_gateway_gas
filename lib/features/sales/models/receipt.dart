import '../../../core/utils/num_parse.dart';

/// One line on a receipt.
class ReceiptLine {
  const ReceiptLine({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  factory ReceiptLine.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>?;
    return ReceiptLine(
      productName: (map['product_name'] as String?) ??
          (product?['name'] as String? ?? ''),
      quantity: parseInt(map['quantity']) ?? 0,
      unitPrice: parseDouble(map['unit_price']) ?? 0,
      lineTotal: parseDouble(map['line_total']) ?? 0,
    );
  }
}

/// Everything needed to render/print a receipt for one sale.
class ReceiptData {
  const ReceiptData({
    required this.saleId,
    required this.invoiceNo,
    this.saleDate,
    this.branchName,
    this.customerName,
    this.locationName,
    this.cashierName,
    this.items = const [],
    this.total = 0,
    this.amountPaid = 0,
    this.balanceDue = 0,
    this.paymentStatus = 'paid',
    this.paymentMethod,
    this.mpesaCode,
    this.riders,
    this.note,
  });

  final String saleId;
  final String invoiceNo;
  final DateTime? saleDate;
  final String? branchName;
  final String? customerName;
  final String? locationName;
  final String? cashierName;
  final List<ReceiptLine> items;
  final double total;
  final double amountPaid;
  final double balanceDue;
  final String paymentStatus;
  final String? paymentMethod;
  final String? mpesaCode;
  final String? riders;
  final String? note;
}
