/// A flagged selling-price change, awaiting admin/director confirmation.
///
/// Cashiers can override a product's selling price during a sale; the
/// override lands here as `pending`. Admin/director confirm (which makes
/// the new price the official one) or reject.
class PriceChangeRequest {
  const PriceChangeRequest({
    required this.id,
    required this.productId,
    this.productName,
    required this.oldPrice,
    required this.newPrice,
    this.status = 'pending',
    this.changedByName,
    this.changedByRole,
    this.saleId,
    this.note,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String? productName;
  final double oldPrice;
  final double newPrice;
  final String status; // pending | confirmed | rejected
  final String? changedByName;
  final String? changedByRole;
  final String? saleId;
  final String? note;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory PriceChangeRequest.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>?;
    final profile = map['profiles'] as Map<String, dynamic>?;
    return PriceChangeRequest(
      id: map['id'] as String,
      productId: (map['product_id'] as String?) ?? '',
      productName: product?['name'] as String?,
      oldPrice: ((map['old_price'] as num?) ?? 0).toDouble(),
      newPrice: ((map['new_price'] as num?) ?? 0).toDouble(),
      status: (map['status'] as String?) ?? 'pending',
      changedByName: profile?['full_name'] as String?,
      changedByRole: profile?['role'] as String?,
      saleId: map['sale_id'] as String?,
      note: map['note'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
