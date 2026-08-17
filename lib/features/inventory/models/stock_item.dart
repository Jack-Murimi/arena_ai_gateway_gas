import '../../../core/utils/num_parse.dart';
import 'product.dart';

/// One product's stock level at one branch (branch_stock_summary view).
class StockItem {
  const StockItem({
    required this.branchId,
    required this.branchName,
    required this.productId,
    required this.productName,
    this.productType = ProductType.refill,
    this.quantity = 0,
    this.lowStockThreshold = 5,
    this.isLow = false,
  });

  final String branchId;
  final String branchName;
  final String productId;
  final String productName;
  final ProductType productType;
  final int quantity;
  final int lowStockThreshold;
  final bool isLow;

  factory StockItem.fromMap(Map<String, dynamic> map) => StockItem(
        branchId: (map['branch_id'] as String?) ?? '',
        branchName: (map['branch_name'] as String?) ?? '',
        productId: (map['product_id'] as String?) ?? '',
        productName: (map['product_name'] as String?) ?? '',
        productType:
            ProductType.fromString(map['product_type'] as String?),
        quantity: parseInt(map['quantity']) ?? 0,
        lowStockThreshold: parseInt(map['low_stock_threshold']) ?? 5,
        isLow: map['is_low'] as bool? ?? false,
      );
}

/// A purchase order (purchase_orders_view row).
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.orderNo,
    this.branchName,
    this.supplierName,
    this.status = 'placed',
    this.notes,
    this.createdAt,
    this.receivedAt,
    this.createdByName,
    this.itemCount = 0,
    this.totalQuantity = 0,
    this.totalCost = 0,
  });

  final String id;
  final String orderNo;
  final String? branchName;
  final String? supplierName;
  final String status; // draft | placed | received | cancelled
  final String? notes;
  final DateTime? createdAt;
  final DateTime? receivedAt;
  final String? createdByName;
  final int itemCount;
  final int totalQuantity;
  final double totalCost;

  bool get isPlaced => status == 'placed';
  bool get isReceived => status == 'received';

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) => PurchaseOrder(
        id: map['id'] as String,
        orderNo: (map['order_no'] as String?) ?? '',
        branchName: map['branch_name'] as String?,
        supplierName: map['supplier_name'] as String?,
        status: (map['status'] as String?) ?? 'draft',
        notes: map['notes'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
        receivedAt: map['received_at'] != null
            ? DateTime.tryParse(map['received_at'] as String)
            : null,
        createdByName: map['created_by_name'] as String?,
        itemCount: parseInt(map['item_count']) ?? 0,
        totalQuantity: parseInt(map['total_quantity']) ?? 0,
        totalCost: parseDouble(map['total_cost']) ?? 0,
      );
}
