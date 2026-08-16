import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/price_change_request.dart';
import '../models/product.dart';

/// Data access for products and price-change approvals.
class ProductRepository {
  final SupabaseClient _db = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Products
  // -------------------------------------------------------------------------

  Future<List<Product>> fetchProducts({String? search, ProductType? type}) async {
    var query = _db.from('products').select();
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      query = query.ilike('name', '%$term%');
    }
    if (type != null) {
      query = query.eq('product_type', type.name);
    }
    final rows = await query.order('name');
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
    }
  }

  // -------------------------------------------------------------------------
  // Price change approvals
  // -------------------------------------------------------------------------

  Future<List<PriceChangeRequest>> fetchPriceChangeRequests({String? status}) async {
    var query = _db.from('price_change_requests').select(
          '*, products(name), '
          'profiles!price_change_requests_changed_by_fkey(full_name, role)',
        );
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

    await _db.from('price_change_requests').update({
      'status': confirm ? 'confirmed' : 'rejected',
      'confirmed_by': profile?['id'],
      'confirmed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
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
