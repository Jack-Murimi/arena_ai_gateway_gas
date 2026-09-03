import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../inventory/data/inventory_batch_repository.dart';
import '../inventory/models/inventory_batch.dart';

/// Page showing detailed FIFO allocations for a specific sale.
/// Shows which inventory batches were consumed and at what cost.
class FifoDetailPage extends StatefulWidget {
  const FifoDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<FifoDetailPage> createState() => _FifoDetailPageState();
}

class _FifoDetailPageState extends State<FifoDetailPage> {
  final _batchRepo = InventoryBatchRepository();

  List<SaleFifoAllocation> _allocations = [];
  Map<String, InventoryBatch> _batches = {};
  bool _loading = true;
  String? _error;

  // Summary data
  double _totalCost = 0;
  double _totalQuantity = 0;
  int _batchCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch FIFO allocations for this sale
      final allocations = await _batchRepo.fetchSaleAllocations(widget.saleId);

      // Fetch batch details for each allocation
      final batchIds = allocations
          .map((a) => a.batchId)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      final batches = <String, InventoryBatch>{};
      if (batchIds.isNotEmpty) {
        final batchList = await _batchRepo.fetchCurrentBatches();
        for (final batch in batchList) {
          if (batchIds.contains(batch.id)) {
            batches[batch.id] = batch;
          }
        }
      }

      // Calculate summary
      double totalCost = 0;
      double totalQuantity = 0;
      for (final a in allocations) {
        totalCost += a.calculatedTotalCost;
        totalQuantity += a.quantity.toDouble();
      }

      if (!mounted) return;
      setState(() {
        _allocations = allocations;
        _batches = batches;
        _totalCost = totalCost;
        _totalQuantity = totalQuantity;
        _batchCount = allocations.length;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FIFO Allocation Details'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 16),
        _buildAllocationsList(),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FIFO Allocation Summary',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _summaryItem('Batches Used', '$_batchCount'),
                ),
                Expanded(
                  child: _summaryItem('Total Quantity', '${_totalQuantity.toInt()}'),
                ),
                Expanded(
                  child: _summaryItem('Total Cost', AppFormatters.kes(_totalCost)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAllocationsList() {
    if (_allocations.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No FIFO allocations found for this sale.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This may be a service product or an old sale.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Inventory Batches Consumed',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        for (int i = 0; i < _allocations.length; i++)
          _buildAllocationCard(_allocations[i], i),
      ],
    );
  }

  Widget _buildAllocationCard(SaleFifoAllocation allocation, int index) {
    final batchId = allocation.batchId;
    final batch = batchId != null ? _batches[batchId] : null;
    final productId = allocation.productId;
    final quantity = allocation.quantity;
    final unitCost = allocation.unitCost;
    final totalCost = allocation.calculatedTotalCost;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product name
                      if (batch != null) ...[
                        Text(
                          batch.productName ?? 'Unknown Product',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Batch info
                        Row(
                          children: [
                            if (batch.brand != null) ...[
                              Text(
                                batch.brand!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (batch.sizeKg != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${batch.sizeKg}kg',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                            if (batch.purchaseDate != null) ...[
                              if (batch.brand != null || batch.sizeKg != null)
                                const SizedBox(width: 8),
                              Text(
                                'Purchased: ${AppFormatters.date(batch.purchaseDate!)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ] else ...[
                        // Fallback if batch not found
                        Text(
                          'Product: ${productId ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Batch: $batchId',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Allocation details
            Row(
              children: [
                Expanded(
                  child: _detailItem('Quantity', '$quantity'),
                ),
                Expanded(
                  child: _detailItem('Unit Cost', AppFormatters.kes(unitCost)),
                ),
                Expanded(
                  child: _detailItem('Total Cost', AppFormatters.kes(totalCost)),
                ),
              ],
            ),
            // Reference info
            if (batch != null && batch.referenceType != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${batch.referenceType}: ${batch.referenceId ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
