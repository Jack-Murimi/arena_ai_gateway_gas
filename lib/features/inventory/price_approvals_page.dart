import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/product_repository.dart';
import 'models/price_change_request.dart';

/// Price-change approvals: flagged selling-price overrides from the POS.
/// Admin/director confirm (new price becomes official) or reject.
class PriceApprovalsPage extends StatefulWidget {
  const PriceApprovalsPage({super.key});

  @override
  State<PriceApprovalsPage> createState() => _PriceApprovalsPageState();
}

class _PriceApprovalsPageState extends State<PriceApprovalsPage> {
  final _repo = ProductRepository();

  List<PriceChangeRequest> _requests = [];
  String _status = 'pending'; // pending | confirmed | rejected
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
      final requests = await _repo.fetchPriceChangeRequests(status: _status);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _review(PriceChangeRequest request, bool confirm) async {
    try {
      await _repo.reviewPriceChange(
        requestId: request.id,
        confirm: confirm,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirm
                ? 'Confirmed — ${request.productName ?? 'product'} now sells '
                    'at ${AppFormatters.kes(request.newPrice)}'
                : 'Price change rejected',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Price approvals')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                for (final (value, label) in [
                  ('pending', 'Pending'),
                  ('confirmed', 'Confirmed'),
                  ('rejected', 'Rejected'),
                ]) ...[
                  if (value != 'pending') const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) {
                      setState(() => _status = value);
                      _load();
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _status == value
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Text(
          'Nothing here yet.\nPrice overrides made at the POS appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _requestCard(_requests[i]),
    );
  }

  Widget _requestCard(PriceChangeRequest request) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  request.isPending
                      ? Icons.flag_outlined
                      : request.status == 'confirmed'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                  color: request.isPending
                      ? AppColors.warning
                      : request.status == 'confirmed'
                          ? AppColors.success
                          : AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.productName ?? 'Product',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (request.status != 'pending')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (request.status == 'confirmed'
                              ? AppColors.success
                              : AppColors.danger)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      request.status == 'confirmed' ? 'Confirmed' : 'Rejected',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: request.status == 'confirmed'
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${AppFormatters.kes(request.oldPrice)}  →  '
              '${AppFormatters.kes(request.newPrice)}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (request.changedByName != null)
                  'by ${request.changedByName}'
                      '${request.changedByRole != null ? ' (${request.changedByRole})' : ''}',
                if (request.createdAt != null)
                  AppFormatters.dateTime(request.createdAt!),
                if (request.saleId != null)
                  'sale ${request.saleId!.substring(0, 8)}…',
              ].join(' · '),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (request.note != null && request.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                request.note!,
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
            if (request.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _review(request, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _review(request, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm price'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
