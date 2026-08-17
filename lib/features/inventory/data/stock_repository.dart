import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stock_item.dart';

/// Data access for stock levels, initialization and purchase orders.
class StockRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }

  Future<List<StockItem>> fetchBranchStock(String branchId) async {
    final rows = await _db
        .from('branch_stock_summary')
        .select()
        .eq('branch_id', branchId)
        .order('product_name');
    return rows.map(StockItem.fromMap).toList();
  }

  /// Totals per product type for a branch: {refill: qty, cylinder: qty, ...}
  Future<Map<String, int>> fetchBranchTypeTotals(String branchId) async {
    final rows = await _db
        .from('branch_type_totals')
        .select()
        .eq('branch_id', branchId);
    return {
      for (final r in rows)
        (r['product_type'] as String?) ?? '': ((r['total_quantity'] as num?) ?? 0).toInt(),
    };
  }

  Future<void> initStock({
    required String branchId,
    required List<Map<String, dynamic>> items,
  }) async {
    await _db.rpc('admin_init_stock', params: {
      'p_branch_id': branchId,
      'p_items': items,
    });
  }

  Future<Map<String, dynamic>> placeOrder({
    required String branchId,
    String? supplierId,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _db.rpc('admin_place_order', params: {
      'p_branch_id': branchId,
      'p_supplier_id': supplierId,
      'p_notes': notes,
      'p_items': items,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> receiveOrder(String orderId) async {
    await _db.rpc('admin_receive_order', params: {'p_order_id': orderId});
  }

  Future<List<PurchaseOrder>> fetchOrders() async {
    final rows = await _db
        .from('purchase_orders_view')
        .select()
        .order('created_at', ascending: false);
    return rows.map(PurchaseOrder.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> fetchSuppliers() async {
    return _db.from('suppliers').select('id, name').order('name');
  }
}
