import '../../../core/utils/num_parse.dart';

/// One row of the daily sales summary.
class DailySalesRow {
  const DailySalesRow({
    this.saleDate,
    this.branchName,
    this.salesCount = 0,
    this.totalSales = 0,
    this.paidTotal = 0,
    this.unpaidTotal = 0,
    this.partialTotal = 0,
  });

  final DateTime? saleDate;
  final String? branchName;
  final int salesCount;
  final double totalSales;
  final double paidTotal;
  final double unpaidTotal;
  final double partialTotal;

  factory DailySalesRow.fromMap(Map<String, dynamic> map) => DailySalesRow(
        saleDate: map['sale_date'] != null
            ? DateTime.tryParse(map['sale_date'] as String)
            : null,
        branchName: map['branch_name'] as String?,
        salesCount: parseInt(map['sales_count']) ?? 0,
        totalSales: parseDouble(map['total_sales']) ?? 0,
        paidTotal: parseDouble(map['paid_total']) ?? 0,
        unpaidTotal: parseDouble(map['unpaid_total']) ?? 0,
        partialTotal: parseDouble(map['partial_total']) ?? 0,
      );
}

/// Best-seller row from report_best_sellers.
class BestSellerRow {
  const BestSellerRow({
    this.productName,
    this.productType,
    this.quantitySold = 0,
    this.revenue = 0,
  });

  final String? productName;
  final String? productType;
  final int quantitySold;
  final double revenue;

  factory BestSellerRow.fromMap(Map<String, dynamic> map) => BestSellerRow(
        productName: map['product_name'] as String?,
        productType: map['product_type'] as String?,
        quantitySold: parseInt(map['quantity_sold']) ?? 0,
        revenue: parseDouble(map['revenue']) ?? 0,
      );
}

/// Payment method row.
class PaymentMethodRow {
  const PaymentMethodRow({
    this.saleDate,
    this.method,
    this.paymentCount = 0,
    this.amount = 0,
  });

  final DateTime? saleDate;
  final String? method;
  final int paymentCount;
  final double amount;

  factory PaymentMethodRow.fromMap(Map<String, dynamic> map) =>
      PaymentMethodRow(
        saleDate: map['sale_date'] != null
            ? DateTime.tryParse(map['sale_date'] as String)
            : null,
        method: map['method'] as String?,
        paymentCount: parseInt(map['payment_count']) ?? 0,
        amount: parseDouble(map['amount']) ?? 0,
      );
}

/// Debtor row.
class DebtorRow {
  const DebtorRow({
    this.id,
    this.name,
    this.phone,
    this.balance = 0,
    this.creditLimit = 0,
  });

  final String? id;
  final String? name;
  final String? phone;
  final double balance;
  final double creditLimit;

  factory DebtorRow.fromMap(Map<String, dynamic> map) => DebtorRow(
        id: map['id'] as String?,
        name: map['name'] as String?,
        phone: map['phone'] as String?,
        balance: parseDouble(map['balance']) ?? 0,
        creditLimit: parseDouble(map['credit_limit']) ?? 0,
      );
}

/// Stock valuation row.
class ValuationRow {
  const ValuationRow({
    this.branchName,
    this.productCount = 0,
    this.costValue = 0,
    this.retailValue = 0,
  });

  final String? branchName;
  final int productCount;
  final double costValue;
  final double retailValue;

  factory ValuationRow.fromMap(Map<String, dynamic> map) => ValuationRow(
        branchName: map['branch_name'] as String?,
        productCount: parseInt(map['product_count']) ?? 0,
        costValue: parseDouble(map['cost_value']) ?? 0,
        retailValue: parseDouble(map['retail_value']) ?? 0,
      );
}
