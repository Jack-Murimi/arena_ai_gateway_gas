import 'package:flutter/material.dart';

import 'dart:async';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'customer_detail_page.dart';
import 'customer_form_page.dart';
import 'data/customer_repository.dart';
import 'models/customer.dart';

/// Customers list with search, quick overview and add button.
class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _repo = CustomerRepository();
  final _searchCtrl = TextEditingController();

  List<Customer> _customers = [];
  Map<String, CustomerContact?> _primaryContacts = {};
  Map<String, CustomerLocation?> _primaryLocations = {};
  bool _loading = true;
  String? _error;

  // Debounce timer for search
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final customers = await _repo.fetchCustomers(search: _searchCtrl.text);
      // Use optimized methods that only fetch primary contacts/locations
      final primaryContacts = await _repo.fetchPrimaryContactsByCustomer();
      final primaryLocations = await _repo.fetchPrimaryLocationsByCustomer();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _primaryContacts = primaryContacts;
        _primaryLocations = primaryLocations;
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

  Future<void> _openForm({Customer? customer}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CustomerFormPage(customer: customer)),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: customer)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) {
                  // Cancel previous timer
                  _searchTimer?.cancel();

                  // Start new debounce timer (500ms delay)
                  _searchTimer = Timer(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      _load();
                    }
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Search customers…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton.extended(
            heroTag: 'add-customer',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('New Customer'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorCard(message: _error!, onRetry: _load);
    }
    if (_customers.isEmpty) {
      return _EmptyState(onAdd: () => _openForm());
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: _customers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final customer = _customers[i];
        return _CustomerTile(
          customer: customer,
          primaryContact: _primaryContacts[customer.id],
          primaryLocation: _primaryLocations[customer.id],
          onTap: () => _openDetail(customer),
        );
      },
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.onTap,
    this.primaryContact,
    this.primaryLocation,
  });

  final Customer customer;
  final VoidCallback onTap;
  final CustomerContact? primaryContact;
  final CustomerLocation? primaryLocation;

  @override
  Widget build(BuildContext context) {
    final owes = customer.balance > 0.001;

    // One compact summary line: main contact and/or main location.
    final summary = <String>[
      if (primaryContact != null)
        '${primaryContact!.name} · ${primaryContact!.phone}',
      if (primaryLocation != null) primaryLocation!.name,
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                foregroundColor: AppColors.primary,
                child: Text(
                  customer.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (owes ? AppColors.danger : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  owes ? AppFormatters.kes(customer.balance) : 'No balance',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: owes ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'No customers yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first customer to start recording sales, '
                'credit and deliveries.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                const Text(
                  'Could not load customers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure the database migrations have been run in '
                  'Supabase (SQL Editor):\n\n'
                  '1. supabase/migrations/0001_initial_schema.sql\n'
                  '2. supabase/migrations/0002_customers_contacts_locations.sql',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
