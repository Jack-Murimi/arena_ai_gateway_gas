import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/num_parse.dart';
import '../models/stock_item.dart';

/// Data access for stock levels, initialization and purchase orders.
class StockRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }

  Future<List<StockItem>> fetchStock({String? branchId}) async {
    var query = _db.from('branch_stock_summary').select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query.order('product_name');
    return rows.map(StockItem.fromMap).toList();
  }

  /// Totals per product type for a branch: {refill: qty, cylinder: qty, ...}
  Future<Map<String, int>> fetchBranchTypeTotals({String? branchId}) async {
    var query = _db.from('branch_type_totals').select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query;
    return {
      for (final r in rows)
        (r['product_type'] as String?) ?? '': parseInt(r['total_quantity']) ?? 0,
    };
  }

  /// Totals by size per type: key 'refill|13' -> qty ('' size = none).
  Future<Map<String, int>> fetchSizeTotals({String? branchId}) async {
    var query = _db.from('branch_size_totals').select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query;
    final map = <String, int>{};
    for (final r in rows) {
      final type = (r['product_type'] as String?) ?? '';
      final size = (r['size_kg'] as num?)?.toDouble();
      final sizeKey = size == null ? '' : size.toString();
      map['$type|$sizeKey'] = parseInt(r['total_quantity']) ?? 0;
    }
    return map;
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
