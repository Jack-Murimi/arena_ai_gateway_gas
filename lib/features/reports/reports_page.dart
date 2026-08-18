import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/report_repository.dart';
import 'models/report_models.dart';

/// Reports: daily sales (with date + branch filters), best sellers,
/// payment methods, debtors, stock valuation and CSV export.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _repo = ReportRepository();

  List<Map<String, dynamic>> _branches = [];
  String? _branchId; // null = all

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  List<DailySalesRow> _daily = [];
  List<BestSellerRow> _bestSellers = [];
  List<PaymentMethodRow> _paymentMethods = [];
  List<DebtorRow> _debtors = [];
  List<ValuationRow> _valuation = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await _repo.fetchBranches();
      final daily = await _repo.fetchDailySales(
          from: _from, to: _to, branchId: _branchId);
      final best = await _repo.fetchBestSellers(from: _from, to: _to);
      final methods = await _repo.fetchPaymentMethods(from: _from, to: _to);
      final debtors = await _repo.fetchDebtors();
      final valuation = await _repo.fetchStockValuation();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _daily = daily;
        _bestSellers = best;
        _paymentMethods = methods;
        _debtors = debtors;
        _valuation = valuation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _from = picked);
      _load();
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _to = picked);
      _load();
    }
  }

  double get _totalSales =>
      _daily.fold<double>(0, (s, r) => s + r.totalSales);
  int get _totalCount => _daily.fold<int>(0, (s, r) => s + r.salesCount);
  double get _totalUnpaid =>
      _daily.fold<double>(0, (s, r) => s + r.unpaidTotal + r.partialTotal);
  double get _debtorTotal =>
      _debtors.fold<double>(0, (s, d) => s + d.balance);

  // -------------------------------------------------------------------------
  // CSV export
  // -------------------------------------------------------------------------

  String _buildCsv() {
    final buf = StringBuffer();
    buf.writeln('GATEWAY GAS ENTERPRISES - REPORT');
    buf.writeln('Period: ${AppFormatters.date(_from)} to ${AppFormatters.date(_to)}');
    buf.writeln('Branch: ${_branches.where((b) => b['id'] == _branchId).map((b) => b['name']).firstOrNull ?? 'All'}');
    buf.writeln();
    buf.writeln('DAILY SALES');
    buf.writeln('Date,Branch,Sales Count,Total (KSh),Paid (KSh),Credit (KSh)');
    for (final r in _daily) {
      buf.writeln('${r.saleDate == null ? '' : AppFormatters.date(r.saleDate!)},'
          '${r.branchName ?? ''},${r.salesCount},${r.totalSales.toStringAsFixed(2)},'
          '${r.paidTotal.toStringAsFixed(2)},${(r.unpaidTotal + r.partialTotal).toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('BEST SELLERS');
    buf.writeln('Product,Type,Qty Sold,Revenue (KSh)');
    for (final r in _bestSellers) {
      buf.writeln('${r.productName ?? ''},${r.productType ?? ''},${r.quantitySold},${r.revenue.toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('PAYMENT METHODS');
    buf.writeln('Method,Count,Amount (KSh)');
    final byMethod = <String, (int, double)>{};
    for (final r in _paymentMethods) {
      final m = r.method ?? 'unknown';
      final cur = byMethod[m] ?? (0, 0.0);
      byMethod[m] = (cur.$1 + r.paymentCount, cur.$2 + r.amount);
    }
    byMethod.forEach((m, v) => buf.writeln('$m,${v.$1},${v.$2.toStringAsFixed(2)}'));
    buf.writeln();
    buf.writeln('DEBTORS');
    buf.writeln('Name,Phone,Balance (KSh)');
    for (final r in _debtors) {
      buf.writeln('${r.name ?? ''},${r.phone ?? ''},${r.balance.toStringAsFixed(2)}');
    }
    buf.writeln();
    buf.writeln('STOCK VALUATION');
    buf.writeln('Branch,Products,Cost Value (KSh),Retail Value (KSh)');
    for (final r in _valuation) {
      buf.writeln('${r.branchName ?? ''},${r.productCount},${r.costValue.toStringAsFixed(2)},${r.retailValue.toStringAsFixed(2)}');
    }
    return buf.toString();
  }

  Future<void> _exportCsv() async {
    final csv = _buildCsv();
    final bytes = utf8.encode(csv);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(bytes),
            mimeType: 'text/csv',
            name: 'gateway-gas-report.csv',
          ),
        ],
        subject: 'Gateway Gas report',
        text: 'Report ${AppFormatters.date(_from)} - ${AppFormatters.date(_to)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          color: AppColors.danger, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _filtersCard(),
                    const SizedBox(height: 12),
                    _summaryCard(),
                      const SizedBox(height: 16),
                      _sectionCard(
                        'Daily sales',
                        _daily.isEmpty
                            ? const Text(
                                'No sales in this period.',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              )
                            : Column(
                                children: [
                                  for (final r in _daily)
                                    _row(
                                      '${AppFormatters.date(r.saleDate!)}'
                                      '${r.branchName != null ? ' · ${r.branchName}' : ''}',
                                      '${r.salesCount} sale(s)',
                                      AppFormatters.kes(r.totalSales),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        'Best sellers',
                        _bestSellers.isEmpty
                            ? const Text(
                                'No sales in this period.',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              )
                            : Column(
                                children: [
                                  for (final r in _bestSellers.take(10))
                                    _row(
                                      '${r.productName ?? ''}'
                                      '${r.productType != null ? ' (${r.productType})' : ''}',
                                      '${r.quantitySold} sold',
                                      AppFormatters.kes(r.revenue),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        'Payment methods',
                        _paymentMethods.isEmpty
                            ? const Text(
                                'No payments in this period.',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              )
                            : Column(
                                children: [
                                  for (final r in _paymentMethods)
                                    _row(
                                      '${r.method ?? ''}'
                                      '${r.saleDate != null ? ' · ${AppFormatters.date(r.saleDate!)}' : ''}',
                                      '${r.paymentCount} payment(s)',
                                      AppFormatters.kes(r.amount),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        'Debtors (${_debtors.length})',
                        _debtors.isEmpty
                            ? const Text(
                                'No outstanding balances. 🎉',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              )
                            : Column(
                                children: [
                                  for (final d in _debtors)
                                    _row(
                                      d.name ?? '',
                                      d.phone ?? '',
                                      AppFormatters.kes(d.balance),
                                      valueColor: AppColors.warning,
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        'Stock valuation',
                        _valuation.isEmpty
                            ? const Text(
                                'No stock initialized yet.',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              )
                            : Column(
                                children: [
                                  for (final v in _valuation)
                                    _row(
                                      v.branchName ?? '',
                                      '${v.productCount} products',
                                      'Cost ${AppFormatters.kes(v.costValue)}'
                                      ' / Retail ${AppFormatters.kes(v.retailValue)}',
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
  }

  Widget _filtersCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFrom,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  AppFormatters.date(_from),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('—'),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTo,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  AppFormatters.date(_to),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Branch',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All'),
                  ),
                  for (final b in _branches)
                    DropdownMenuItem<String?>(
                      value: b['id'] as String,
                      child: Text(b['name'] as String),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _branchId = v);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _loading ? null : _exportCsv,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _stat('Sales (KSh)', AppFormatters.kes(_totalSales),
                  AppColors.primary),
            ),
            Expanded(
              child: _stat('Transactions', '$_totalCount',
                  AppColors.textPrimary),
            ),
            Expanded(
              child: _stat('Credit (KSh)', AppFormatters.kes(_totalUnpaid),
                  AppColors.warning),
            ),
            Expanded(
              child: _stat('Debtors (KSh)', AppFormatters.kes(_debtorTotal),
                  AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 10.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _row(String left, String middle, String right,
      {Color valueColor = AppColors.primary}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              middle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Text(
            right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
