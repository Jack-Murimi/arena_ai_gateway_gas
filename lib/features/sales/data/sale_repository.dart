import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/num_parse.dart';
import '../../customers/models/customer.dart';
import '../../inventory/models/product.dart';
import '../../riders/data/rider_repository.dart';
import '../../riders/models/rider.dart';
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
}
