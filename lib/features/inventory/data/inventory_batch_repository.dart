import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_batch.dart';

/// Repository for managing inventory batches and FIFO cost tracking.
class InventoryBatchRepository {
  final SupabaseClient _db = Supabase.instance.client;

  /// Fetch all current inventory batches (with remaining quantity > 0)
  Future<List<InventoryBatch>> fetchCurrentBatches({
    String? branchId,
    String? productId,
  }) async {
    var query = _db.from('current_inventory_batches').select();

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (productId != null) {
      query = query.eq('product_id', productId);
    }

    final rows = await query
        .order('purchase_date', ascending: true)
        .order('created_at', ascending: true);
    return rows.map(InventoryBatch.fromMap).toList();
  }

  /// Fetch inventory batches for a specific product at a branch
  Future<List<InventoryBatch>> fetchBatchesForProduct(
    String branchId,
    String productId,
  ) async {
    final rows = await _db
        .from('current_inventory_batches')
        .select()
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('purchase_date', ascending: true)
        .order('created_at', ascending: true);
    return rows.map(InventoryBatch.fromMap).toList();
  }

  /// Fetch the oldest available batch for a product (FIFO)
  Future<InventoryBatch?> fetchOldestBatch(
    String branchId,
    String productId,
  ) async {
    final rows = await _db
        .from('current_inventory_batches')
        .select()
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .order('purchase_date', ascending: true)
        .order('created_at', ascending: true)
        .limit(1);

    if (rows.isEmpty) return null;
    return InventoryBatch.fromMap(rows.first);
  }

  /// Fetch FIFO allocations for a sale
  Future<List<SaleFifoAllocation>> fetchSaleAllocations(String saleId) async {
    final rows = await _db
        .from('sale_fifo_allocations')
        .select()
        .eq('sale_id', saleId)
        .order('created_at', ascending: true);
    return rows.map(SaleFifoAllocation.fromMap).toList();
  }

  /// Fetch FIFO cost summary for a sale
  Future<FifoCostSummary> fetchSaleFifoSummary(String saleId) async {
    final allocations = await fetchSaleAllocations(saleId);
    
    // Get sale total from sales table
    final saleRow = await _db
        .from('sales')
        .select('total')
        .eq('id', saleId)
        .single();
    final revenue = (saleRow['total'] as num?)?.toDouble() ?? 0;

    return FifoCostSummary.fromAllocations(allocations, revenue);
  }

  /// Get current selling price for a product
  Future<double> fetchProductSellingPrice(String productId) async {
    final row = await _db
        .from('products')
        .select('sale_price')
        .eq('id', productId)
        .single();
    return (row['sale_price'] as num?)?.toDouble() ?? 0;
  }

  /// Fetch selling prices for multiple products in a batch
  Future<Map<String, double>> fetchProductSellingPricesBatch(List<String> productIds) async {
    final rows = await _db
        .from('products')
        .select('id, sale_price')
        .inFilter('id', productIds);
    
    return {
      for (final row in rows)
        row['id'] as String: (row['sale_price'] as num?)?.toDouble() ?? 0,
    };
  }

  /// Get total quantity available for a product at a branch
  Future<int> fetchTotalQuantity(String branchId, String productId) async {
    final rows = await _db
        .from('current_inventory_batches')
        .select('quantity_remaining')
        .eq('branch_id', branchId)
        .eq('product_id', productId);

    return rows.fold<int>(0, (sum, row) => sum + (row['quantity_remaining'] as int? ?? 0));
  }

  /// Get weighted average cost for a product at a branch
  Future<double> fetchAverageCost(String branchId, String productId) async {
    final rows = await _db
        .from('current_inventory_batches')
        .select('quantity_remaining, unit_cost')
        .eq('branch_id', branchId)
        .eq('product_id', productId);

    if (rows.isEmpty) return 0;

    double totalValue = 0;
    int totalQuantity = 0;
    for (final row in rows) {
      final qty = row['quantity_remaining'] as int? ?? 0;
      final cost = (row['unit_cost'] as num?)?.toDouble() ?? 0;
      totalValue += qty * cost;
      totalQuantity += qty;
    }

    return totalQuantity > 0 ? totalValue / totalQuantity : 0;
  }
}
