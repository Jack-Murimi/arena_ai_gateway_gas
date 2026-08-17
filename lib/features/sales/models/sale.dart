import '../../../core/utils/num_parse.dart';

/// A recorded sale row (from the sales_view).
class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.invoiceNo,
    this.saleDate,
    this.branchName,
    this.customerName,
    this.locationName,
    this.cashierName,
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.total = 0,
    this.paymentStatus = 'paid',
    this.note,
    this.itemsSummary,
    this.ridersSummary,
    this.createdAt,
  });

  final String id;
  final String invoiceNo;
  final DateTime? saleDate;
  final String? branchName;
  final String? customerName;
  final String? locationName;
  final String? cashierName;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String paymentStatus; // paid | unpaid | partial
  final String? note;
  final String? itemsSummary;
  final String? ridersSummary;
  final DateTime? createdAt;

  bool get isPaid => paymentStatus == 'paid';
  bool get isUnpaid => paymentStatus == 'unpaid';

  factory SaleRecord.fromMap(Map<String, dynamic> map) => SaleRecord(
        id: map['id'] as String,
        invoiceNo: (map['invoice_no'] as String?) ?? '',
        saleDate: map['sale_date'] != null
            ? DateTime.tryParse(map['sale_date'] as String)
            : null,
        branchName: map['branch_name'] as String?,
        customerName: map['customer_name'] as String?,
        locationName: map['location_name'] as String?,
        cashierName: map['cashier_name'] as String?,
        subtotal: parseDouble(map['subtotal']) ?? 0,
        discount: parseDouble(map['discount']) ?? 0,
        tax: parseDouble(map['tax']) ?? 0,
        total: parseDouble(map['total']) ?? 0,
        paymentStatus: (map['payment_status'] as String?) ?? 'paid',
        note: map['note'] as String?,
        itemsSummary: map['items_summary'] as String?,
        ridersSummary: map['riders_summary'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
