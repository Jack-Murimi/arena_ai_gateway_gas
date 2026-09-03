import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/num_parse.dart';
import '../../customers/models/customer.dart';
import '../../inventory/models/product.dart';
import '../../riders/data/rider_repository.dart';
import '../../riders/models/rider.dart';
import '../models/receipt.dart';
import '../models/sale.dart';

/// Data access for the Sales (POS) recording flow.
class SaleRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<Product>> fetchProducts() async {
    final rows = await _db
        .from('products')
        .select()
        .eq('is_active', true)
        .order('product_type')
        .order('size_kg', nullsFirst: false)
        .order('name');
    return rows.map(Product.fromMap).toList();
  }

  /// Current stock quantities per product for a branch.
  Future<Map<String, int>> fetchStockMap(String branchId) async {
    final rows = await _db
        .from('branch_stock_summary')
        .select('product_id, quantity')
        .eq('branch_id', branchId);
    return {
      for (final r in rows)
        (r['product_id'] as String?) ?? '': parseInt(r['quantity']) ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }

  Future<List<Customer>> fetchCustomers() async {
    final rows = await _db.from('customers').select().order('name');
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<CustomerLocation>> fetchLocations(String customerId) async {
    final rows = await _db
        .from('customer_locations')
        .select()
        .eq('customer_id', customerId)
        .order('is_primary', ascending: false);
    return rows.map(CustomerLocation.fromMap).toList();
  }

  Future<List<RiderSummary>> fetchRiders() =>
      RiderRepository().fetchRiderSummaries();

  /// Records a complete sale through the atomic record_sale RPC.
  Future<Map<String, dynamic>> recordSale({
    required DateTime saleDate,
    required String branchId,
    required String customerId,
    String? locationId,
    required List<Map<String, dynamic>> items,
    required List<String> riderIds,
    required String paymentMethod,
    required double amountPaid,
    String? mpesaCode,
    String? note,
    List<Map<String, dynamic>> cylindersLeft = const [],
  }) async {
    final data = await _db.rpc('record_sale', params: {
      'p_sale_date': saleDate.toIso8601String().substring(0, 10),
      'p_branch_id': branchId,
      'p_customer_id': customerId,
      'p_customer_location_id': locationId,
      'p_items': items,
      'p_riders': [for (final id in riderIds) {'rider_id': id}],
      'p_payment_method': paymentMethod,
      'p_amount_paid': amountPaid,
      'p_mpesa_code': mpesaCode,
      'p_note': note,
      'p_cylinders_left': cylindersLeft,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<SaleRecord>> fetchRecentSales({int limit = 50}) async {
    final rows = await _db
        .from('sales_view')
        .select()
        .order('sale_date', ascending: false)
        .limit(limit);
    return rows.map(SaleRecord.fromMap).toList();
  }

  /// Full data for printing/viewing one receipt.
  Future<ReceiptData> fetchReceiptData(String saleId) async {
    final sale = await _db
        .from('sales_view')
        .select()
        .eq('id', saleId)
        .single();
    final items = await _db
        .from('sale_items')
        .select('*, products(name)')
        .eq('sale_id', saleId)
        .order('id');
    final payments = await _db
        .from('payments')
        .select()
        .eq('sale_id', saleId);

    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + (parseDouble(p['amount']) ?? 0),
    );
    final method = payments.isEmpty
        ? null
        : ((payments.first['method'] as String?) ?? '');
    final mpesa = payments.isEmpty
        ? null
        : (payments.first['mpesa_code'] as String?);
    final riders = sale['riders_summary'] as String?;
    final total = parseDouble(sale['total']) ?? 0;

    // Fetch FIFO data from sales_fifo_view
    final fifoData = await _db
        .from('sales_fifo_view')
        .select('total_cost, total_profit')
        .eq('id', saleId)
        .single();

    final totalCost = parseDouble(fifoData?['total_cost']) ?? 0.0;
    final totalProfit = parseDouble(fifoData?['total_profit']) ?? 0.0;
    final profitMarginPercentage = total > 0 ? (totalProfit / total) * 100.0 : 0.0;

    return ReceiptData(
      saleId: saleId,
      invoiceNo: (sale['invoice_no'] as String?) ?? '',
      saleDate: sale['sale_date'] != null
          ? DateTime.tryParse(sale['sale_date'] as String)
          : null,
      branchName: sale['branch_name'] as String?,
      customerName: sale['customer_name'] as String?,
      locationName: sale['location_name'] as String?,
      cashierName: sale['cashier_name'] as String?,
      items: items.map(ReceiptLine.fromMap).toList(),
      total: total,
      amountPaid: paid,
      balanceDue: total - paid,
      paymentStatus: (sale['payment_status'] as String?) ?? 'paid',
      paymentMethod: method,
      mpesaCode: mpesa,
      riders: riders,
      note: sale['note'] as String?,
      totalCost: totalCost,
      totalProfit: totalProfit,
      profitMarginPercentage: profitMarginPercentage,
    );
  }

  /// Fetch FIFO allocations for a specific sale
  Future<List<Map<String, dynamic>>> fetchSaleFifoAllocations(String saleId) async {
    final rows = await _db
        .from('sale_fifo_allocations')
        .select('*, inventory_batches(purchase_date, reference_type, reference_id)')
        .eq('sale_id', saleId)
        .order('created_at');
    return rows;
  }

  /// Fetch FIFO cost summary for a specific sale
  Future<Map<String, dynamic>> fetchSaleFifoSummary(String saleId) async {
    final fifoData = await _db
        .from('sales_fifo_view')
        .select('total_cost, total_profit')
        .eq('id', saleId)
        .single();
    return fifoData ?? {};
  }
}
