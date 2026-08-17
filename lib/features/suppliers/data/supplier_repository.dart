import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/supplier.dart';

/// Data access for suppliers, their invoices, items and payments.
class SupplierRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<SupplierSummary>> fetchSuppliers() async {
    final rows =
        await _db.from('supplier_summary').select().order('name');
    return rows.map(SupplierSummary.fromMap).toList();
  }

  Future<void> saveSupplier({
    String? supplierId,
    required String name,
    String? phone,
    String? contactPerson,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'contact_person': contactPerson,
    };
    if (supplierId == null) {
      await _db.from('suppliers').insert(data);
    } else {
      await _db.from('suppliers').update(data).eq('id', supplierId);
    }
  }

  /// Soft-delete: hides the supplier but keeps their invoices/payments.
  Future<void> archiveSupplier(String supplierId) async {
    await _db.rpc('admin_archive_supplier', params: {
      'p_supplier_id': supplierId,
    });
  }

  /// Hard-deletes an invoice + its items, reversing posted stock.
  Future<void> deleteInvoice(String invoiceId) async {
    await _db.rpc('admin_delete_supplier_invoice', params: {
      'p_invoice_id': invoiceId,
    });
  }

  Future<List<SupplierInvoice>> fetchInvoices(String supplierId) async {
    final rows = await _db
        .from('supplier_invoices_view')
        .select()
        .eq('supplier_id', supplierId)
        .order('invoice_date', ascending: false);
    return rows.map(SupplierInvoice.fromMap).toList();
  }

  Future<List<SupplierInvoiceItem>> fetchInvoiceItems(String invoiceId) async {
    final rows = await _db
        .from('supplier_invoice_items')
        .select('*, products(name)')
        .eq('invoice_id', invoiceId)
        .order('line_total', ascending: false);
    return rows.map(SupplierInvoiceItem.fromMap).toList();
  }

  Future<List<SupplierPayment>> fetchPayments(String supplierId) async {
    final rows = await _db
        .from('supplier_payments_view')
        .select()
        .eq('supplier_id', supplierId)
        .order('payment_date', ascending: false);
    return rows.map(SupplierPayment.fromMap).toList();
  }

  Future<Map<String, dynamic>> createInvoice({
    required String supplierId,
    required String invoiceNo,
    String? branchId,
    required DateTime invoiceDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _db.rpc('admin_save_supplier_invoice', params: {
      'p_supplier_id': supplierId,
      'p_invoice_no': invoiceNo,
      'p_branch_id': branchId,
      'p_invoice_date': invoiceDate.toIso8601String().substring(0, 10),
      'p_notes': notes,
      'p_items': items,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> recordPayment({
    required String supplierId,
    String? invoiceId,
    required double amount,
    required DateTime paymentDate,
    required String method,
    String? reference,
  }) async {
    await _db.rpc('admin_record_supplier_payment', params: {
      'p_supplier_id': supplierId,
      'p_invoice_id': invoiceId,
      'p_amount': amount,
      'p_payment_date': paymentDate.toIso8601String().substring(0, 10),
      'p_method': method,
      'p_reference': reference,
    });
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return _db.from('branches').select('id, name').order('name');
  }

  Future<List<Map<String, dynamic>>> fetchProducts() async {
    return _db
        .from('products')
        .select('id, name, product_type, cost_price')
        .eq('is_active', true)
        .order('name');
  }
}
