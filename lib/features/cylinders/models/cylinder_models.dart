import '../../../core/utils/num_parse.dart';

/// A cylinder left with a customer (cylinder_tracking_view row).
class CylinderTracking {
  const CylinderTracking({
    required this.id,
    this.customerId,
    this.customerName,
    this.locationName,
    this.productId,
    this.productName,
    this.quantity = 1,
    this.saleId,
    this.invoiceNo,
    this.leftByName,
    this.leftAt,
    this.followUpDate,
    this.note,
    this.status = 'out',
    this.returnedAt,
  });

  final String id;
  final String? customerId;
  final String? customerName;
  final String? locationName;
  final String? productId;
  final String? productName;
  final int quantity;
  final String? saleId;
  final String? invoiceNo;
  final String? leftByName;
  final DateTime? leftAt;
  final DateTime? followUpDate;
  final String? note;
  final String status;
  final DateTime? returnedAt;

  bool get isOut => status == 'out';
  bool get isOverdue =>
      isOut && followUpDate != null && followUpDate!.isBefore(DateTime.now());
  bool get isDueSoon =>
      isOut &&
      followUpDate != null &&
      !isOverdue &&
      followUpDate!.difference(DateTime.now()).inDays <= 2;
  bool get isReturned => status == 'returned';

  factory CylinderTracking.fromMap(Map<String, dynamic> map) =>
      CylinderTracking(
        id: (map['id'] as String?) ?? '',
        customerId: map['customer_id'] as String?,
        customerName: map['customer_name'] as String?,
        locationName: map['location_name'] as String?,
        productId: map['product_id'] as String?,
        productName: map['product_name'] as String?,
        quantity: parseInt(map['quantity']) ?? 1,
        saleId: map['sale_id'] as String?,
        invoiceNo: map['invoice_no'] as String?,
        leftByName: map['left_by_name'] as String?,
        leftAt: map['left_at'] != null
            ? DateTime.tryParse(map['left_at'] as String)
            : null,
        followUpDate: map['follow_up_date'] != null
            ? DateTime.tryParse(map['follow_up_date'] as String)
            : null,
        note: map['note'] as String?,
        status: (map['status'] as String?) ?? 'out',
        returnedAt: map['returned_at'] != null
            ? DateTime.tryParse(map['returned_at'] as String)
            : null,
      );
}

/// A flagged exchange mismatch (cylinder_exchange_alerts_view row).
class ExchangeAlert {
  const ExchangeAlert({
    required this.id,
    this.saleId,
    this.invoiceNo,
    this.branchName,
    this.customerName,
    this.soldProductName,
    this.receivedProductName,
    this.status = 'pending',
    this.resolvedByName,
    this.resolvedAt,
    this.note,
    this.createdAt,
  });

  final String id;
  final String? saleId;
  final String? invoiceNo;
  final String? branchName;
  final String? customerName;
  final String? soldProductName;
  final String? receivedProductName;
  final String status;
  final String? resolvedByName;
  final DateTime? resolvedAt;
  final String? note;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory ExchangeAlert.fromMap(Map<String, dynamic> map) => ExchangeAlert(
        id: (map['id'] as String?) ?? '',
        saleId: map['sale_id'] as String?,
        invoiceNo: map['invoice_no'] as String?,
        branchName: map['branch_name'] as String?,
        customerName: map['customer_name'] as String?,
        soldProductName: map['sold_product_name'] as String?,
        receivedProductName: map['received_product_name'] as String?,
        status: (map['status'] as String?) ?? 'pending',
        resolvedByName: map['resolved_by_name'] as String?,
        resolvedAt: map['resolved_at'] != null
            ? DateTime.tryParse(map['resolved_at'] as String)
            : null,
        note: map['note'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
