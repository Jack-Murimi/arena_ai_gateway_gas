import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/price_change_request.dart';
import '../models/product.dart';

/// Data access for products and price-change approvals.
class ProductRepository {
  final SupabaseClient _db = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Products
  // -------------------------------------------------------------------------

  Future<List<Product>> fetchProducts({
    String? search,
    ProductType? type,
  }) async {
    var query = _db.from('products').select();
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      query = query.ilike('name', '%$term%');
    }
    if (type != null) {
      query = query.eq('product_type', type.name);
    }
    final rows = await query
        .order('product_type')
        .order('size_kg', nullsFirst: false)
        .order('name');
    return rows.map(Product.fromMap).toList();
  }

  Future<void> saveProduct({
    String? productId,
    required String name,
    required ProductType productType,
    double? sizeKg,
    String? brand,
    required double salePrice,
    required double costPrice,
    int lowStockThreshold = 5,
    bool syncLinkedPair = false,
    String? originalBrand,
    double? originalSizeKg,
    String? linkedPairName,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'product_type': productType.name,
      'size_kg': sizeKg,
      'brand': brand,
      'sale_price': salePrice,
      'cost_price': costPrice,
      'low_stock_threshold': lowStockThreshold,
    };
    if (productId == null) {
      await _db.from('products').insert(data);
    } else {
      await _db.from('products').update(data).eq('id', productId);

      if (syncLinkedPair &&
          linkedPairName != null &&
          linkedPairName.trim().isNotEmpty) {
        final targetType = productType == ProductType.refill
            ? 'cylinder'
            : (productType == ProductType.cylinder ? 'refill' : null);

        if (targetType != null) {
          final searchBrand = originalBrand ?? brand;
          final searchSize = originalSizeKg ?? sizeKg;

          final updateData = <String, dynamic>{
            'name': linkedPairName.trim(),
            'brand': ?brand,
            'size_kg': ?sizeKg,
          };

          var query = _db
              .from('products')
              .update(updateData)
              .eq('product_type', targetType);
          if (searchSize != null) {
            query = query.eq('size_kg', searchSize);
          }
          if (searchBrand != null && searchBrand.isNotEmpty) {
            query = query.ilike('brand', searchBrand);
          }
          await query;
        }
      }
    }
  }

  Future<void> createRefillWithCylinder({
    required String refillName,
    required String brand,
    required double sizeKg,
    required double refillSalePrice,
    required double refillCostPrice,
    required String cylinderName,
    required double cylinderSalePrice,
    required double cylinderCostPrice,
    required int lowStockThreshold,
  }) async {
    await _db.rpc(
      'create_refill_with_cylinder',
      params: {
        'p_refill_name': refillName,
        'p_brand': brand,
        'p_size_kg': sizeKg,
        'p_refill_sale_price': refillSalePrice,
        'p_refill_cost_price': refillCostPrice,
        'p_cylinder_name': cylinderName,
        'p_cylinder_sale_price': cylinderSalePrice,
        'p_cylinder_cost_price': cylinderCostPrice,
        'p_low_stock_threshold': lowStockThreshold,
      },
    );
  }

  // -------------------------------------------------------------------------
  // Price change approvals
  // -------------------------------------------------------------------------

  Future<List<PriceChangeRequest>> fetchPriceChangeRequests({
    String? status,
  }) async {
    // Read from price_change_requests_view so names of the people involved
    // are visible to all authenticated users (profiles RLS would hide them).
    var query = _db.from('price_change_requests_view').select();
    if (status != null) {
      query = query.eq('status', status);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map(PriceChangeRequest.fromMap).toList();
  }

  /// Confirm (makes new_price the official product price) or reject.
  Future<void> reviewPriceChange({
    required String requestId,
    required bool confirm,
  }) async {
    final profile = await _currentProfile();
    final request = await _db
        .from('price_change_requests')
        .select('product_id, new_price')
        .eq('id', requestId)
        .single();

    if (confirm) {
      await _db
          .from('products')
          .update({'sale_price': request['new_price']})
          .eq('id', request['product_id']);
    }

    await _db
        .from('price_change_requests')
        .update({
          'status': confirm ? 'confirmed' : 'rejected',
          'confirmed_by': profile?['id'],
          'confirmed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId);
  }

  // -------------------------------------------------------------------------
  // Role helpers
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _currentProfile() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    return _db.from('profiles').select().eq('id', uid).maybeSingle();
  }

  /// Only admin/director can confirm price changes.
  Future<bool> isAdminOrDirector() async {
    try {
      final profile = await _currentProfile();
      final role = profile?['role'] as String?;
      return role == 'admin' || role == 'director';
    } catch (_) {
      return false;
    }
  }
}
