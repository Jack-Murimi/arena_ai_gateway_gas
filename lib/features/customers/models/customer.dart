import '../../../core/utils/num_parse.dart';
import '../../inventory/models/product.dart';

/// One row of the customer account ledger.
class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.id,
    required this.customerId,
    this.entryType = 'sale',
    this.debit = 0,
    this.credit = 0,
    this.balanceAfter = 0,
    this.createdAt,
    this.invoiceNo,
    this.paymentMethod,
    this.mpesaCode,
  });

  final String id;
  final String customerId;
  final String entryType; // sale | payment | adjustment | refund | opening
  final double debit;
  final double credit;
  final double balanceAfter;
  final DateTime? createdAt;
  final String? invoiceNo;
  final String? paymentMethod;
  final String? mpesaCode;

  bool get isSale => entryType == 'sale';
  bool get isPayment => entryType == 'payment';

  String get description {
    if (isSale) return 'Sale${invoiceNo != null ? ' $invoiceNo' : ''}';
    if (isPayment) {
      final m = paymentMethod?.toUpperCase() ?? '';
      return 'Payment${m.isNotEmpty ? ' ($m)' : ''}';
    }
    return entryType[0].toUpperCase() + entryType.substring(1);
  }

  factory CustomerLedgerEntry.fromMap(Map<String, dynamic> map) =>
      CustomerLedgerEntry(
        id: (map['id'] as String?) ?? '',
        customerId: (map['customer_id'] as String?) ?? '',
        entryType: (map['entry_type'] as String?) ?? 'sale',
        debit: parseDouble(map['debit']) ?? 0,
        credit: parseDouble(map['credit']) ?? 0,
        balanceAfter: parseDouble(map['balance_after']) ?? 0,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
        invoiceNo: map['invoice_no'] as String?,
        paymentMethod: map['payment_method'] as String?,
        mpesaCode: map['mpesa_code'] as String?,
      );
}

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
