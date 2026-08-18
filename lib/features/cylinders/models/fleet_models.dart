import '../../../core/utils/num_parse.dart';

/// One brand+size fleet row for a branch (cylinder_fleet_view).
class FleetRow {
  const FleetRow({
    this.branchId,
    this.branchName,
    this.brand,
    this.sizeKg,
    this.fullQty = 0,
    this.emptyQty = 0,
    this.outQty = 0,
    this.totalQty = 0,
  });

  final String? branchId;
  final String? branchName;
  final String? brand;
  final double? sizeKg;
  final int fullQty;
  final int emptyQty;
  final int outQty;
  final int totalQty;

  String get sizeLabel => sizeKg == null
      ? ''
      : (sizeKg == sizeKg!.roundToDouble()
          ? '${sizeKg!.toInt()}kg'
          : '${sizeKg}kg');

  String get title => '${brand ?? '?'} · $sizeLabel';

  factory FleetRow.fromMap(Map<String, dynamic> map) => FleetRow(
        branchId: map['branch_id'] as String?,
        branchName: map['branch_name'] as String?,
        brand: map['brand'] as String?,
        sizeKg: parseDouble(map['size_kg']),
        fullQty: parseInt(map['full_qty']) ?? 0,
        emptyQty: parseInt(map['empty_qty']) ?? 0,
        outQty: parseInt(map['out_qty']) ?? 0,
        totalQty: parseInt(map['total_qty']) ?? 0,
      );
}

/// One cylinder stock movement (cylinder_movement_log row).
class CylinderMovement {
  const CylinderMovement({
    this.id,
    this.branchName,
    this.productName,
    this.brand,
    this.sizeKg,
    this.productType,
    this.quantityChange = 0,
    this.movementType,
    this.note,
    this.createdAt,
  });

  final String? id;
  final String? branchName;
  final String? productName;
  final String? brand;
  final double? sizeKg;
  final String? productType;
  final int quantityChange;
  final String? movementType;
  final String? note;
  final DateTime? createdAt;

  bool get isPositive => quantityChange > 0;

  factory CylinderMovement.fromMap(Map<String, dynamic> map) =>
      CylinderMovement(
        id: map['id'] as String?,
        branchName: map['branch_name'] as String?,
        productName: map['product_name'] as String?,
        brand: map['brand'] as String?,
        sizeKg: parseDouble(map['size_kg']),
        productType: map['product_type'] as String?,
        quantityChange: parseInt(map['quantity_change']) ?? 0,
        movementType: map['movement_type'] as String?,
        note: map['note'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
