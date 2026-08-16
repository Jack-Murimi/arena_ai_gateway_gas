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
  /// locations (contacts/locations are replaced wholesale on update).
  Future<void> saveCustomer({
    String? customerId,
    required String name,
    String? email,
    double creditLimit = 0,
    required List<CustomerContact> contacts,
    required List<CustomerLocation> locations,
  }) async {
    final contactRows = [
      for (final c in contacts)
        {
          'name': c.name,
          'phone': c.phone,
          'is_primary': c.isPrimary,
        },
    ];
    final locationRows = [
      for (final l in locations)
        {
          'name': l.name,
          'address': l.address,
          'is_primary': l.isPrimary,
          'default_product_id': l.defaultProductId,
        },
    ];

    if (customerId == null) {
      final res = await _db
          .from('customers')
          .insert({
            'name': name,
            'email': email,
            'credit_limit': creditLimit,
          })
          .select('id')
          .single();
      final newId = res['id'] as String;
      await _insertContacts(newId, contactRows);
      await _insertLocations(newId, locationRows);
    } else {
      await _db.from('customers').update({
        'name': name,
        'email': email,
        'credit_limit': creditLimit,
      }).eq('id', customerId);
      await _db.from('customer_contacts').delete().eq('customer_id', customerId);
      await _db
          .from('customer_locations')
          .delete()
          .eq('customer_id', customerId);
      await _insertContacts(customerId, contactRows);
      await _insertLocations(customerId, locationRows);
    }
  }

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
    try {
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
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, List<CustomerLocation>>> fetchLocationsByCustomer() async {
    try {
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
    } catch (_) {
      // products join may fail if products table is missing — fall back.
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
}
