import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/delivery.dart';

/// Admin data access for deliveries.
class DeliveryRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<Delivery>> fetchDeliveries() async {
    final rows = await _db
        .from('deliveries')
        .select('*, branches(name), profiles(full_name)')
        .order('created_at', ascending: false);
    return rows.map(Delivery.fromMap).toList();
  }

  Future<void> createDelivery({
    required String customerName,
    String? location,
    String? branchId,
    String? riderId,
    double amount = 0,
    String? note,
  }) async {
    await _db.from('deliveries').insert({
      'customer_name': customerName,
      'location': location,
      'branch_id': branchId,
      'rider_id': riderId,
      'amount': amount,
      'note': note,
      'status': 'pending',
    });
  }

  Future<void> markDelivered(String deliveryId) async {
    await _db.from('deliveries').update({
      'status': 'delivered',
      'delivered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', deliveryId);
  }
}
