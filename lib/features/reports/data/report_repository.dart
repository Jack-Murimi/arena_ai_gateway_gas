import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/report_models.dart';

/// Data access for the Reports module.
class ReportRepository {
  final SupabaseClient _db = Supabase.instance.client;

  String _dateParam(DateTime d) =>
      d.toIso8601String().substring(0, 10);

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }

  Future<List<DailySalesRow>> fetchDailySales({
    required DateTime from,
    required DateTime to,
    String? branchId,
  }) async {
    var query = _db
        .from('daily_sales_summary')
        .select()
        .gte('sale_date', _dateParam(from))
        .lte('sale_date', _dateParam(to));
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query.order('sale_date', ascending: false);
    return rows.map(DailySalesRow.fromMap).toList();
  }

  Future<List<BestSellerRow>> fetchBestSellers({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rpc('report_best_sellers', params: {
      'p_from': _dateParam(from),
      'p_to': _dateParam(to),
    });
    return (rows as List)
        .map((r) => BestSellerRow.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<PaymentMethodRow>> fetchPaymentMethods({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db
        .from('payment_methods_summary')
        .select()
        .gte('sale_date', _dateParam(from))
        .lte('sale_date', _dateParam(to));
    return rows.map(PaymentMethodRow.fromMap).toList();
  }

  Future<List<DebtorRow>> fetchDebtors() async {
    final rows = await _db.from('debtors_view').select().order('balance', ascending: false);
    return rows.map(DebtorRow.fromMap).toList();
  }

  Future<List<ValuationRow>> fetchStockValuation() async {
    final rows = await _db.from('stock_valuation_view').select().order('branch_name');
    return rows.map(ValuationRow.fromMap).toList();
  }
}
