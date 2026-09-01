import '../../../core/utils/num_parse.dart';

/// Represents a batch of inventory received at a specific cost.
/// Used for FIFO (First-In-First-Out) cost accounting.
class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.branchId,
    this.branchName,
    required this.productId,
    this.productName,
    this.productType,
    this.brand,
    this.sizeKg,
    required this.quantityReceived,
    required this.quantityRemaining,
    required this.unitCost,
    required this.purchaseDate,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String branchId;
  final String? branchName;
  final String productId;
  final String? productName;
  final String? productType;
  final String? brand;
  final double? sizeKg;
  final int quantityReceived;
  final int quantityRemaining;
  final double unitCost;
  final DateTime purchaseDate;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Returns true if this batch still has available quantity
  bool get hasStock => quantityRemaining > 0;

  /// Returns the total value of this batch at cost
  double get totalValue => quantityReceived * unitCost;

  /// Returns the remaining value of this batch at cost
  double get remainingValue => quantityRemaining * unitCost;

  /// Returns the percentage of this batch that has been consumed
  double get percentConsumed {
    if (quantityReceived <= 0) return 0;
    return 1.0 - (quantityRemaining / quantityReceived);
  }

  factory InventoryBatch.fromMap(Map<String, dynamic> map) => InventoryBatch(
        id: map['id'] as String,
        branchId: map['branch_id'] as String,
        branchName: map['branch_name'] as String?,
        productId: map['product_id'] as String,
        productName: map['product_name'] as String?,
        productType: map['product_type'] as String?,
        brand: map['brand'] as String?,
        sizeKg: parseDouble(map['size_kg']),
        quantityReceived: parseInt(map['quantity_received']) ?? 0,
        quantityRemaining: parseInt(map['quantity_remaining']) ?? 0,
        unitCost: parseDouble(map['unit_cost']) ?? 0,
        purchaseDate: map['purchase_date'] != null
            ? DateTime.tryParse(map['purchase_date'] as String)
            : DateTime.now(),
        referenceType: map['reference_type'] as String?,
        referenceId: map['reference_id'] as String?,
        notes: map['notes'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : DateTime.now(),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'branch_id': branchId,
        'branch_name': branchName,
        'product_id': productId,
        'product_name': productName,
        'product_type': productType,
        'brand': brand,
        'size_kg': sizeKg,
        'quantity_received': quantityReceived,
        'quantity_remaining': quantityRemaining,
        'unit_cost': unitCost,
        'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
        'reference_type': referenceType,
        'reference_id': referenceId,
        'notes': notes,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}

/// Represents the allocation of inventory batches to a sale line item.
/// Used for FIFO cost tracking and historical accuracy.
class SaleFifoAllocation {
  const SaleFifoAllocation({
    required this.id,
    required this.saleId,
    this.saleItemId,
    required this.batchId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    this.totalCost,
    required this.createdAt,
  });

  final String id;
  final String saleId;
  final String? saleItemId;
  final String batchId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double? totalCost;
  final DateTime createdAt;

  /// Calculates total cost (quantity * unit_cost)
  double get calculatedTotalCost => quantity * unitCost;

  factory SaleFifoAllocation.fromMap(Map<String, dynamic> map) =>
      SaleFifoAllocation(
        id: map['id'] as String,
        saleId: map['sale_id'] as String,
        saleItemId: map['sale_item_id'] as String?,
        batchId: map['batch_id'] as String,
        productId: map['product_id'] as String,
        quantity: parseInt(map['quantity']) ?? 0,
        unitCost: parseDouble(map['unit_cost']) ?? 0,
        totalCost: parseDouble(map['total_cost']),
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'sale_item_id': saleItemId,
        'batch_id': batchId,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost ?? calculatedTotalCost,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Summary of FIFO cost information for a sale or product.
class FifoCostSummary {
  final double totalCost;
  final double totalRevenue;
  final double totalProfit;
  final int totalQuantity;
  final double averageCost;

  const FifoCostSummary({
    this.totalCost = 0,
    this.totalRevenue = 0,
    this.totalProfit = 0,
    this.totalQuantity = 0,
    this.averageCost = 0,
  });

  /// Calculate profit margin percentage
  double get profitMarginPercentage {
    if (totalRevenue <= 0) return 0;
    return (totalProfit / totalRevenue) * 100;
  }

  factory FifoCostSummary.fromAllocations(
    List<SaleFifoAllocation> allocations,
    double revenue,
  ) {
    double totalCost = 0;
    int totalQuantity = 0;

    for (final a in allocations) {
      totalCost += a.calculatedTotalCost;
      totalQuantity += a.quantity;
    }

    return FifoCostSummary(
      totalCost: totalCost,
      totalRevenue: revenue,
      totalProfit: revenue - totalCost,
      totalQuantity: totalQuantity,
      averageCost: totalQuantity > 0 ? totalCost / totalQuantity : 0,
    );
  }
}
