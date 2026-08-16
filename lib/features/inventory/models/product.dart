/// A gas product (cylinder size × brand) — from the `products` table.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.sizeKg,
    this.brand,
    this.salePrice = 0,
    this.costPrice = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final double? sizeKg;
  final String? brand;
  final double salePrice;
  final double costPrice;
  final bool isActive;

  /// Human-friendly size, e.g. 13kg (no trailing ".0").
  static String formatSizeKg(double? sizeKg) {
    if (sizeKg == null) return '';
    final rounded = sizeKg.roundToDouble();
    return rounded == sizeKg ? '${rounded.toInt()}kg' : '${sizeKg}kg';
  }

  /// e.g. "Refill · 13kg · Gateway"
  String get displayName {
    final parts = <String>[name];
    if (sizeKg != null) parts.add(formatSizeKg(sizeKg));
    if (brand != null && brand!.isNotEmpty) parts.add(brand!);
    return parts.join(' · ');
  }

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        sizeKg: (map['size_kg'] as num?)?.toDouble(),
        brand: map['brand'] as String?,
        salePrice: ((map['sale_price'] as num?) ?? 0).toDouble(),
        costPrice: ((map['cost_price'] as num?) ?? 0).toDouble(),
        isActive: map['is_active'] as bool? ?? true,
      );
}
