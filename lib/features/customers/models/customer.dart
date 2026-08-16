import '../../../core/utils/num_parse.dart';
import '../../inventory/models/product.dart';

/// A customer = a household/business that buys gas from us.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.creditLimit = 0,
    this.balance = 0,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final double creditLimit;
  final double balance;
  final bool isActive;
  final DateTime? createdAt;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        creditLimit: parseDouble(map['credit_limit']) ?? 0,
        balance: parseDouble(map['balance']) ?? 0,
        isActive: map['is_active'] as bool? ?? true,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}

/// A person who orders gas for a customer (house keeper, security, children…).
class CustomerContact {
  const CustomerContact({
    this.id,
    this.customerId = '',
    required this.name,
    required this.phone,
    this.isPrimary = false,
  });

  final String? id;
  final String customerId;
  final String name;
  final String phone;
  final bool isPrimary;

  factory CustomerContact.fromMap(Map<String, dynamic> map) => CustomerContact(
        id: map['id'] as String?,
        customerId: (map['customer_id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        phone: (map['phone'] as String?) ?? '',
        isPrimary: map['is_primary'] as bool? ?? false,
      );
}

/// A delivery point for a customer, optionally with a default cylinder.
class CustomerLocation {
  const CustomerLocation({
    this.id,
    this.customerId = '',
    required this.name,
    this.address,
    this.isPrimary = false,
    this.defaultProductId,
    this.defaultProductName,
  });

  final String? id;
  final String customerId;
  final String name;
  final String? address;
  final bool isPrimary;
  final String? defaultProductId;
  final String? defaultProductName;

  factory CustomerLocation.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? productMap,
  }) {
    String? productName;
    if (productMap != null && productMap['name'] != null) {
      final name = productMap['name'] as String;
      final size = (productMap['size_kg'] as num?)?.toDouble();
      final brand = productMap['brand'] as String?;
      final parts = <String>[name];
      if (size != null) parts.add(Product.formatSizeKg(size));
      if (brand != null && brand.isNotEmpty) parts.add(brand);
      productName = parts.join(' · ');
    }
    return CustomerLocation(
      id: map['id'] as String?,
      customerId: (map['customer_id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      address: map['address'] as String?,
      isPrimary: map['is_primary'] as bool? ?? false,
      defaultProductId: map['default_product_id'] as String?,
      defaultProductName: productName,
    );
  }
}
