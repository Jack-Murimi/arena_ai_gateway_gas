import '../../../core/utils/num_parse.dart';

/// A supplier with their account summary (what we owe them).
class SupplierSummary {
  const SupplierSummary({
    required this.id,
    required this.name,
    this.phone,
    this.contactPerson,
    this.isActive = true,
    this.invoicedTotal = 0,
    this.paidTotal = 0,
    this.balance = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final String? contactPerson;
  final bool isActive;
  final double invoicedTotal;
  final double paidTotal;
  final double balance; // >0 = we owe the supplier

  bool get owes => balance > 0.001;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory SupplierSummary.fromMap(Map<String, dynamic> map) => SupplierSummary(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        phone: map['phone'] as String?,
        contactPerson: map['contact_person'] as String?,
        isActive: map['is_active'] as bool? ?? true,
        invoicedTotal: parseDouble(map['invoiced_total']) ?? 0,
        paidTotal: parseDouble(map['paid_total']) ?? 0,
        balance: parseDouble(map['balance']) ?? 0,
      );
}

/// A supplier invoice (from supplier_invoices_view).
class SupplierInvoice {
  const SupplierInvoice({
    required this.id,
    required this.invoiceNo,
    required this.supplierId,
    this.supplierName,
    this.branchId,
    this.branchName,
    this.invoiceDate,
    this.totalAmount = 0,
    this.status = 'unpaid',
    this.notes,
    this.itemCount = 0,
    this.itemsSummary,
    this.createdAt,
  });

  final String id;
  final String invoiceNo;
  final String supplierId;
  final String? supplierName;
  final String? branchId;
  final String? branchName;
  final DateTime? invoiceDate;
  final double totalAmount;
  final String status; // unpaid | partial | paid
  final String? notes;
  final int itemCount;
  final String? itemsSummary;
  final DateTime? createdAt;

  bool get isPaid => status == 'paid';
  bool get isUnpaid => status == 'unpaid';

  factory SupplierInvoice.fromMap(Map<String, dynamic> map) => SupplierInvoice(
        id: map['id'] as String,
        invoiceNo: (map['invoice_no'] as String?) ?? '',
        supplierId: (map['supplier_id'] as String?) ?? '',
        supplierName: map['supplier_name'] as String?,
        branchId: map['branch_id'] as String?,
        branchName: map['branch_name'] as String?,
        invoiceDate: map['invoice_date'] != null
            ? DateTime.tryParse(map['invoice_date'] as String)
            : null,
        totalAmount: parseDouble(map['total_amount']) ?? 0,
        status: (map['status'] as String?) ?? 'unpaid',
        notes: map['notes'] as String?,
        itemCount: parseInt(map['item_count']) ?? 0,
        itemsSummary: map['items_summary'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}

/// One line item of a supplier invoice.
class SupplierInvoiceItem {
  const SupplierInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    this.productName,
    this.quantity = 0,
    this.unitCost = 0,
    this.lineTotal = 0,
  });

  final String id;
  final String invoiceId;
  final String productId;
  final String? productName;
  final int quantity;
  final double unitCost;
  final double lineTotal;

  factory SupplierInvoiceItem.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>?;
    return SupplierInvoiceItem(
      id: map['id'] as String,
      invoiceId: (map['invoice_id'] as String?) ?? '',
      productId: (map['product_id'] as String?) ?? '',
      productName: (map['product_name'] as String?) ??
          (product?['name'] as String?),
      quantity: parseInt(map['quantity']) ?? 0,
      unitCost: parseDouble(map['unit_cost']) ?? 0,
      lineTotal: parseDouble(map['line_total']) ?? 0,
    );
  }
}

/// A payment made to a supplier (from supplier_payments_view).
class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.supplierId,
    this.supplierName,
    this.invoiceId,
    this.invoiceNo,
    this.amount = 0,
    this.paymentDate,
    this.method = 'cash',
    this.reference,
    this.createdAt,
  });

  final String id;
  final String supplierId;
  final String? supplierName;
  final String? invoiceId;
  final String? invoiceNo;
  final double amount;
  final DateTime? paymentDate;
  final String method;
  final String? reference;
  final DateTime? createdAt;

  factory SupplierPayment.fromMap(Map<String, dynamic> map) => SupplierPayment(
        id: map['id'] as String,
        supplierId: (map['supplier_id'] as String?) ?? '',
        supplierName: map['supplier_name'] as String?,
        invoiceId: map['invoice_id'] as String?,
        invoiceNo: map['invoice_no'] as String?,
        amount: parseDouble(map['amount']) ?? 0,
        paymentDate: map['payment_date'] != null
            ? DateTime.tryParse(map['payment_date'] as String)
            : null,
        method: (map['method'] as String?) ?? 'cash',
        reference: map['reference'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
