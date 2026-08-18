import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fleet_models.dart';

/// Data access for the cylinder fleet view + movement history.
class FleetRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<FleetRow>> fetchFleet({String? branchId}) async {
    var query = _db.from('cylinder_fleet_view').select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query
        .order('brand')
        .order('size_kg', nullsFirst: false);
    return rows.map(FleetRow.fromMap).toList();
  }

  Future<List<CylinderMovement>> fetchMovements({
    String? branchId,
    String? movementType,
  }) async {
    var query = _db.from('cylinder_movement_log').select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (movementType != null) {
      query = query.eq('movement_type', movementType);
    }
    final rows = await query.limit(300);
    return rows.map(CylinderMovement.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }
}
