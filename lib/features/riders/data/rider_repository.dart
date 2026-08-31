import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/num_parse.dart';
import '../../deliveries/models/delivery.dart';
import '../models/rider.dart';

/// Data access for riders, their stats and monthly targets.
class RiderRepository {
  final SupabaseClient _db = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Branches (for dropdowns)
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final rows = await _db.from('branches').select('id, name').order('name');
    return rows;
  }

  // -------------------------------------------------------------------------
  // Riders + stats + targets (combined summaries)
  // -------------------------------------------------------------------------

  Future<List<RiderSummary>> fetchRiderSummaries() async {
    // Read from the rider_delivery_stats view (owner-rights, RLS-free, so
    // riders can also see colleagues' performance) + rider_targets.
    List<Map<String, dynamic>> stats = [];
    List<Map<String, dynamic>> targets = [];
    try {
      stats = await _db.from('rider_delivery_stats').select();
      targets = await _db
          .from('rider_targets')
          .select()
          .eq('month', _currentMonth());
    } catch (_) {
      // view or targets may be missing — treat as empty
    }

    final statsByRider = {for (final s in stats) s['rider_id'] as String: s};
    final targetByRider = {for (final t in targets) t['rider_id'] as String: t};

    final summaries = <RiderSummary>[
      for (final entry in statsByRider.entries)
        RiderSummary(
          id: entry.key,
          fullName: (entry.value['full_name'] as String?) ?? '',
          phone: entry.value['phone'] as String?,
          branchId: entry.value['branch_id'] as String?,
          branchName: entry.value['branch_name'] as String?,
          deliveredCount: parseInt(entry.value['delivered_count']) ?? 0,
          deliveredAmount: parseDouble(entry.value['delivered_amount']) ?? 0,
          pendingCount: parseInt(entry.value['pending_count']) ?? 0,
          targetDeliveries:
              parseInt(targetByRider[entry.key]?['target_deliveries']) ?? 0,
          targetAmount:
              parseDouble(targetByRider[entry.key]?['target_amount']) ?? 0,
        ),
    ];
    summaries.sort((a, b) => a.fullName.compareTo(b.fullName));
    return summaries;
  }

  static String _currentMonth() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final iso = first.toIso8601String();
    return iso.substring(0, 10); // yyyy-MM-dd
  }

  // -------------------------------------------------------------------------
  // Admin actions (security-definer RPCs)
  // -------------------------------------------------------------------------

  Future<void> createRider({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? branchId,
  }) async {
    await _db.rpc(
      'admin_create_rider',
      params: {
        'p_email': email.trim(),
        'p_password': password,
        'p_full_name': fullName.trim(),
        'p_phone': phone?.trim(),
        'p_branch_id': branchId,
      },
    );
  }

  Future<void> updateRider({
    required String riderId,
    required String email,
    required String fullName,
    String? phone,
    String? branchId,
  }) async {
    await _db.rpc(
      'admin_update_rider',
      params: {
        'p_rider_id': riderId,
        'p_email': email.trim(),
        'p_full_name': fullName.trim(),
        'p_phone': phone?.trim(),
        'p_branch_id': branchId,
      },
    );
  }

  Future<String?> fetchRiderEmail(String riderId) async {
    final result = await _db.rpc(
      'admin_get_rider_email',
      params: {'p_rider_id': riderId},
    );
    return result as String?;
  }

  Future<String> assignTemporaryBranch({
    required String riderId,
    required String branchId,
    required DateTime startsOn,
    required DateTime endsOn,
    String? note,
  }) async {
    final result = await _db.rpc(
      'admin_assign_rider_branch',
      params: {
        'p_rider_id': riderId,
        'p_branch_id': branchId,
        'p_starts_on': startsOn.toIso8601String().substring(0, 10),
        'p_ends_on': endsOn.toIso8601String().substring(0, 10),
        'p_note': note,
      },
    );
    return result as String;
  }

  Future<List<Map<String, dynamic>>> fetchTemporaryAssignments(
    String riderId,
  ) async {
    final rows = await _db
        .from('rider_branch_assignments')
        .select('*, branches(name)')
        .eq('rider_id', riderId)
        .order('starts_on', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> setTarget({
    required String riderId,
    required String month, // yyyy-MM-dd
    required int targetDeliveries,
    required double targetAmount,
  }) async {
    await _db.rpc(
      'admin_set_rider_target',
      params: {
        'p_rider_id': riderId,
        'p_month': month,
        'p_target_deliveries': targetDeliveries,
        'p_target_amount': targetAmount,
      },
    );
  }

  // -------------------------------------------------------------------------
  // Rider-specific delivery queries
  // -------------------------------------------------------------------------

  Future<List<Delivery>> fetchMyPendingDeliveries() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('deliveries')
        .select('*, branches(name)')
        .eq('rider_id', uid)
        .inFilter('status', ['pending', 'assigned', 'picked_up'])
        .order('created_at', ascending: false);
    return rows.map(Delivery.fromMap).toList();
  }

  Future<List<Delivery>> fetchMyDeliveredDeliveries() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('deliveries')
        .select('*, branches(name)')
        .eq('rider_id', uid)
        .eq('status', 'delivered')
        .order('delivered_at', ascending: false);
    return rows.map(Delivery.fromMap).toList();
  }

  Future<void> markDelivered(String deliveryId) async {
    await _db
        .from('deliveries')
        .update({
          'status': 'delivered',
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', deliveryId);
  }
}
