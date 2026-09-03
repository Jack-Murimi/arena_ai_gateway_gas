import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/colors.dart' as PdfColors;
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'data/sale_repository.dart';
import 'models/receipt.dart';

/// View / print / share a sale receipt (80mm thermal-friendly layout).
class ReceiptPage extends StatefulWidget {
  const ReceiptPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final _repo = SaleRepository();

  ReceiptData? _receipt;
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
      final receipt = await _repo.fetchReceiptData(widget.saleId);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
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

  Future<void> _print() async {
    final receipt = _receipt;
    if (receipt == null) return;
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _buildPdf(receipt),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not print: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    }
  }

  Future<void> _share() async {
    final receipt = _receipt;
    if (receipt == null) return;
    try {
      await Printing.sharePdf(
        bytes: await _buildPdf(receipt),
        filename: '${receipt.invoiceNo}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not share: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    }
  }

  Future<Uint8List> _buildPdf(ReceiptData r) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'GATEWAY GAS ENTERPRISES',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'POS & ERP - Gas Cylinders',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Invoice: ${r.invoiceNo}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text(
                  r.saleDate == null
                      ? ''
                      : AppFormatters.date(r.saleDate!),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text('Branch: ${r.branchName ?? '-'}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Customer: ${r.customerName ?? '-'}',
                style: const pw.TextStyle(fontSize: 9)),
            if (r.locationName != null && r.locationName!.isNotEmpty)
              pw.Text('Location: ${r.locationName}',
                  style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Cashier: ${r.cashierName ?? '-'}',
                style: const pw.TextStyle(fontSize: 9)),
            if (r.riders != null && r.riders!.isNotEmpty)
              pw.Text('Rider(s): ${r.riders}',
                  style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            for (final item in r.items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.productName,
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '  ${item.quantity} x ${AppFormatters.kes(item.unitPrice)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(AppFormatters.kes(item.lineTotal),
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Divider(),
            _pdfRow('Total', AppFormatters.kes(r.total), bold: true, size: 11),
            _pdfRow('Paid', AppFormatters.kes(r.amountPaid)),
            if (r.balanceDue > 0.001)
              _pdfRow('Balance due', AppFormatters.kes(r.balanceDue),
                  bold: true),
            if (r.hasFifoData) ...[
              pw.SizedBox(height: 4),
              pw.Divider(),
              _pdfRow('Cost of Goods', AppFormatters.kes(r.totalCost)),
              _pdfRow('Profit', AppFormatters.kes(r.totalProfit),
                  color: r.totalProfit >= 0 ? PdfColors.green700 : PdfColors.red700),
              _pdfRow('Margin', '${r.profitMarginPercentage.toStringAsFixed(1)}%',
                  color: r.profitMarginPercentage >= 0 ? PdfColors.green700 : PdfColors.red700),
            ],
            if (r.paymentMethod != null)
              _pdfRow('Method', r.paymentMethod!.toUpperCase()),
            if (r.mpesaCode != null && r.mpesaCode!.isNotEmpty)
              _pdfRow('M-Pesa', r.mpesaCode!),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                r.paymentStatus == 'paid'
                    ? 'THANK YOU FOR YOUR BUSINESS!'
                    : 'BALANCE BILLED TO ACCOUNT',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfRow(String label, String value,
      {bool bold = false, double size = 9, pw.Color? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: size, fontWeight: pw.FontWeight.bold)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: pw.FontWeight.bold,
                  color: color
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_receipt?.invoiceNo ?? 'Receipt'),
        actions: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _receipt == null ? null : _print,
          ),
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share_outlined),
            onPressed: _receipt == null ? null : _share,
          ),
        ],
      ),
      body: _loading
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
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _ReceiptPaper(receipt: _receipt!),
                    ),
                  ),
                ),
    );
  }
}

/// On-screen receipt styled like an 80mm paper roll.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({required this.receipt});

  final ReceiptData receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'GATEWAY GAS ENTERPRISES',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const Text(
              'POS & ERP — Gas Cylinders',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
            ),
            const Divider(height: 16),
            _row('Invoice', r.invoiceNo, bold: true),
            if (r.saleDate != null) _row('Date', AppFormatters.date(r.saleDate!)),
            if (r.branchName != null) _row('Branch', r.branchName!),
            if (r.customerName != null) _row('Customer', r.customerName!),
            if (r.locationName != null && r.locationName!.isNotEmpty)
              _row('Location', r.locationName!),
            if (r.cashierName != null) _row('Cashier', r.cashierName!),
            if (r.riders != null && r.riders!.isNotEmpty)
              _row('Rider(s)', r.riders!),
            const Divider(height: 16),
            for (final item in r.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '  ${item.quantity} x ${AppFormatters.kes(item.unitPrice)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          AppFormatters.kes(item.lineTotal),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            _row('Total', AppFormatters.kes(r.total), bold: true, size: 15),
            _row('Paid', AppFormatters.kes(r.amountPaid)),
            if (r.balanceDue > 0.001)
              _row('Balance due', AppFormatters.kes(r.balanceDue),
                  bold: true, color: AppColors.warning),
            if (r.hasFifoData) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              _row('Cost of Goods', AppFormatters.kes(r.totalCost),
                  color: AppColors.textSecondary),
              _row('Profit', AppFormatters.kes(r.totalProfit),
                  color: r.totalProfit >= 0 ? AppColors.success : AppColors.danger),
              _row('Margin', '${r.profitMarginPercentage.toStringAsFixed(1)}%',
                  color: r.profitMarginPercentage >= 0 ? AppColors.success : AppColors.danger),
            ],
            if (r.paymentMethod != null)
              _row('Method', r.paymentMethod!.toUpperCase()),
            if (r.mpesaCode != null && r.mpesaCode!.isNotEmpty)
              _row('M-Pesa', r.mpesaCode!),
            if (r.note != null && r.note!.isNotEmpty) _row('Note', r.note!),
            const SizedBox(height: 12),
            Text(
              r.paymentStatus == 'paid'
                  ? 'THANK YOU FOR YOUR BUSINESS!'
                  : 'BALANCE BILLED TO ACCOUNT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: r.paymentStatus == 'paid'
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, double size = 11, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size,
              color: AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: size,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
