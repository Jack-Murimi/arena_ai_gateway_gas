import 'package:flutter/material.dart';

import '../../../core/utils/num_parse.dart';

/// Product categories used across the business.
enum ProductType {
  refill,
  cylinder,
  accessory,
  service;

  String get label => switch (this) {
        ProductType.refill => 'Refill',
        ProductType.cylinder => 'Cylinder',
        ProductType.accessory => 'Accessory',
        ProductType.service => 'Service',
      };

  IconData get icon => switch (this) {
        ProductType.refill => Icons.local_fire_department,
        ProductType.cylinder => Icons.propane_tank_outlined,
        ProductType.accessory => Icons.extension_outlined,
        ProductType.service => Icons.handyman_outlined,
      };

  static ProductType fromString(String? value) => switch (value) {
        'cylinder' => ProductType.cylinder,
        'accessory' => ProductType.accessory,
        'service' => ProductType.service,
        _ => ProductType.refill,
      };
}

/// A product: refill, cylinder, accessory or service.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.productType = ProductType.refill,
    this.sizeKg,
    this.brand,
    this.salePrice = 0,
    this.costPrice = 0,
    this.lowStockThreshold = 5,
    this.isActive = true,
  });

  final String id;
  final String name;
  final ProductType productType;
  final double? sizeKg;
  final String? brand;
  final double salePrice;
  final double costPrice;
  final int lowStockThreshold;
  final bool isActive;

  /// The standard refill sizes available at Gateway Gas.
  static const List<double> refillSizes = [3, 6, 13, 22.5, 35, 45, 50];

  /// Human-friendly size, e.g. 13kg / 22.5kg (no trailing ".0").
  static String formatSizeKg(double? sizeKg) {
    if (sizeKg == null) return '';
    final rounded = sizeKg.roundToDouble();
    return rounded == sizeKg ? '${rounded.toInt()}kg' : '${sizeKg}kg';
  }

  /// e.g. "Afrigas 13kg" (name already carries brand & size for catalogue items).
  String get displayName => name;

  bool _containsInName(String value) =>
      name.toLowerCase().contains(value.toLowerCase());

  /// Short type+size line for list rows.
  /// Skips size/brand/type words already present in the name
  /// (e.g. "13kg Afrigas refill" -> subtitle is empty).
  String get subtitle {
    final parts = <String>[];
    final typeLabel = productType.label;
    if (!_containsInName(typeLabel)) parts.add(typeLabel);
    if (sizeKg != null && !_containsInName(Product.formatSizeKg(sizeKg))) {
      parts.add(Product.formatSizeKg(sizeKg));
    }
    if (brand != null && brand!.isNotEmpty && !_containsInName(brand!)) {
      parts.add(brand!);
    }
    return parts.join(' · ');
  }

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        productType: ProductType.fromString(map['product_type'] as String?),
        sizeKg: parseDouble(map['size_kg']),
        brand: map['brand'] as String?,
        salePrice: parseDouble(map['sale_price']) ?? 0,
        costPrice: parseDouble(map['cost_price']) ?? 0,
        lowStockThreshold: parseInt(map['low_stock_threshold']) ?? 5,
        isActive: map['is_active'] as bool? ?? true,
      );
}
