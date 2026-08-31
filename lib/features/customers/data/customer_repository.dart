import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/models/product.dart';
import '../models/customer.dart';

/// Data access for customers, their contacts and locations.
class CustomerRepository {
  final SupabaseClient _db = Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Customers
  // -------------------------------------------------------------------------

  Future<List<Customer>> fetchCustomers({String? search}) async {
    var query = _db.from('customers').select();
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      query = query.ilike('name', '%$term%');
    }
    final rows = await query.order('name');
    return rows.map(Customer.fromMap).toList();
  }

  /// Saves a customer (insert or update) together with all contacts and
  /// locations in a single atomic transaction.
  /// Uses the save_customer_atomic RPC to ensure all operations succeed or fail together.
  Future<Map<String, dynamic>> saveCustomer({
    String? customerId,
    required String name,
    String? email,
    double creditLimit = 0,
    required List<CustomerContact> contacts,
    required List<CustomerLocation> locations,
  }) async {
    // Convert contacts to RPC format
    final contactInputs = [
      for (final c in contacts)
        {'name': c.name, 'phone': c.phone, 'is_primary': c.isPrimary},
    ];

    // Convert locations to RPC format
    final locationInputs = [
      for (final l in locations)
        {
          'name': l.name,
          'address': l.address,
          'is_primary': l.isPrimary,
          'default_product_id': l.defaultProductId,
        },
    ];

    // Call the atomic RPC
    final data = await _db.rpc(
      'save_customer_atomic',
      params: {
        'p_input': {
          'customer_id': customerId,
          'name': name,
          'email': email,
          'credit_limit': creditLimit,
          'contacts': contactInputs,
          'locations': locationInputs,
        },
      },
    );

    return Map<String, dynamic>.from(data as Map);
  }

  /// Legacy helper methods - kept for reference but no longer used in saveCustomer
  Future<void> _insertContacts(
    String customerId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    await _db.from('customer_contacts').insert([
      for (final r in rows) {...r, 'customer_id': customerId},
    ]);
  }

  Future<void> _insertLocations(
    String customerId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    await _db.from('customer_locations').insert([
      for (final r in rows) {...r, 'customer_id': customerId},
    ]);
  }

  // -------------------------------------------------------------------------
  // Contacts & locations (grouped by customer for list screens)
  // -------------------------------------------------------------------------

  Future<Map<String, List<CustomerContact>>> fetchContactsByCustomer() async {
    final rows = await _db
        .from('customer_contacts')
        .select()
        .order('is_primary', ascending: false);
    final map = <String, List<CustomerContact>>{};
    for (final r in rows) {
      final contact = CustomerContact.fromMap(r);
      map.putIfAbsent(contact.customerId, () => []).add(contact);
    }
    return map;
  }

  Future<Map<String, List<CustomerLocation>>> fetchLocationsByCustomer() async {
    try {
      // Try with products join first
      final rows = await _db
          .from('customer_locations')
          .select('*, products(name, size_kg, brand)')
          .order('is_primary', ascending: false);
      final map = <String, List<CustomerLocation>>{};
      for (final r in rows) {
        final location = CustomerLocation.fromMap(
          r,
          productMap: r['products'] as Map<String, dynamic>?,
        );
        map.putIfAbsent(location.customerId, () => []).add(location);
      }
      return map;
    } catch (e) {
      // If join fails (e.g., products table missing), fall back to simple query
      // but re-throw if this also fails so callers know something is wrong
      final rows = await _db
          .from('customer_locations')
          .select()
          .order('is_primary', ascending: false);
      final map = <String, List<CustomerLocation>>{};
      for (final r in rows) {
        final location = CustomerLocation.fromMap(r);
        map.putIfAbsent(location.customerId, () => []).add(location);
      }
      return map;
    }
  }

  /// Fetches only the primary contact for each customer (optimized for list views)
  /// Returns a map of customer_id -> primary contact (or null if none)
  Future<Map<String, CustomerContact?>> fetchPrimaryContactsByCustomer() async {
    final rows = await _db
        .from('customer_contacts')
        .select()
        .eq('is_primary', true)
        .order('created_at', ascending: true);
    final map = <String, CustomerContact?>{};
    for (final r in rows) {
      final contact = CustomerContact.fromMap(r);
      // Only keep the first primary contact per customer
      if (!map.containsKey(contact.customerId)) {
        map[contact.customerId] = contact;
      }
    }
    return map;
  }

  /// Fetches only the primary location for each customer (optimized for list views)
  /// Returns a map of customer_id -> primary location (or null if none)
  Future<Map<String, CustomerLocation?>>
  fetchPrimaryLocationsByCustomer() async {
    try {
      final rows = await _db
          .from('customer_locations')
          .select('*, products(name, size_kg, brand)')
          .eq('is_primary', true)
          .order('created_at', ascending: true);
      final map = <String, CustomerLocation?>{};
      for (final r in rows) {
        final location = CustomerLocation.fromMap(
          r,
          productMap: r['products'] as Map<String, dynamic>?,
        );
        // Only keep the first primary location per customer
        if (!map.containsKey(location.customerId)) {
          map[location.customerId] = location;
        }
      }
      return map;
    } catch (e) {
      // If join fails, fall back to simple query
      final rows = await _db
          .from('customer_locations')
          .select()
          .eq('is_primary', true)
          .order('created_at', ascending: true);
      final map = <String, CustomerLocation?>{};
      for (final r in rows) {
        final location = CustomerLocation.fromMap(r);
        if (!map.containsKey(location.customerId)) {
          map[location.customerId] = location;
        }
      }
      return map;
    }
  }

  // -------------------------------------------------------------------------
  // Products (for the "default cylinder" picker)
  // -------------------------------------------------------------------------

  Future<List<Product>> fetchProducts() async {
    final rows = await _db
        .from('products')
        .select()
        .eq('is_active', true)
        .order('name');
    return rows.map(Product.fromMap).toList();
  }

  // -------------------------------------------------------------------------
  // Account ledger & payments
  // -------------------------------------------------------------------------

  Future<Customer> fetchCustomer(String customerId) async {
    final row = await _db
        .from('customers')
        .select()
        .eq('id', customerId)
        .single();
    return Customer.fromMap(row);
  }

  Future<List<CustomerLedgerEntry>> fetchLedger(String customerId) async {
    final rows = await _db
        .from('customer_ledger_view')
        .select()
        .eq('customer_id', customerId);
    return rows.map(CustomerLedgerEntry.fromMap).toList();
  }

  Future<Map<String, dynamic>> recordPayment({
    required String customerId,
    required double amount,
    required String method,
    String? mpesaCode,
    required DateTime paymentDate,
    String? note,
  }) async {
    final data = await _db.rpc(
      'record_customer_payment',
      params: {
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_method': method,
        'p_mpesa_code': mpesaCode,
        'p_payment_date': paymentDate.toIso8601String().substring(0, 10),
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  // -------------------------------------------------------------------------
  // Cylinder tracking for this customer
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchCylindersLeft(
    String customerId,
  ) async {
    final rows = await _db
        .from('cylinder_tracking_view')
        .select()
        .eq('customer_id', customerId)
        .eq('status', 'out')
        .order('left_at', ascending: false);
    return rows;
  }
}
