import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cylinder_models.dart';

/// Data access for cylinder tracking + exchange alerts.
class CylinderRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<CylinderTracking>> fetchTracking({String? status}) async {
    var query = _db.from('cylinder_tracking_view').select();
    if (status != null) {
      query = query.eq('status', status);
    }
    final rows = await query.order('left_at', ascending: false);
    return rows.map(CylinderTracking.fromMap).toList();
  }

  Future<void> markReturned(String trackingId) async {
    await _db.rpc('mark_cylinder_returned', params: {
      'p_tracking_id': trackingId,
    });
  }

  Future<void> logCylinderLeft({
    required String customerId,
    String? locationId,
    required String productId,
    required int quantity,
    DateTime? followUpDate,
    String? note,
    String? branchId,
  }) async {
    await _db.rpc('log_cylinder_left', params: {
      'p_customer_id': customerId,
      'p_location_id': locationId,
      'p_product_id': productId,
      'p_quantity': quantity,
      'p_follow_up_date': followUpDate
          ?.toIso8601String()
          .substring(0, 10),
      'p_note': note,
      'p_branch_id': branchId,
    });
  }

  Future<List<ExchangeAlert>> fetchAlerts({String? status}) async {
    var query = _db.from('cylinder_exchange_alerts_view').select();
    if (status != null) {
      query = query.eq('status', status);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map(ExchangeAlert.fromMap).toList();
  }

  Future<void> resolveAlert(String alertId) async {
    await _db.rpc('resolve_exchange_alert', params: {
      'p_alert_id': alertId,
    });
  }
}
