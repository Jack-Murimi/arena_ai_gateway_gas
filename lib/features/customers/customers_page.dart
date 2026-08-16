import 'package:flutter/material.dart';

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
  Map<String, List<CustomerContact>> _contacts = {};
  Map<String, List<CustomerLocation>> _locations = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
      final contacts = await _repo.fetchContactsByCustomer();
      final locations = await _repo.fetchLocationsByCustomer();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _contacts = contacts;
        _locations = locations;
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
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(customer: customer),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailPage(customer: customer),
      ),
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
                onChanged: (_) => _load(),
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final customer = _customers[i];
        return _CustomerTile(
          customer: customer,
          primaryContact: _contacts[customer.id]?.firstOrNull,
          primaryLocation: _locations[customer.id]?.firstOrNull,
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

    final subtitleLines = <String>[
      if (primaryContact != null)
        '${primaryContact!.name} · ${primaryContact!.phone}',
      if (primaryLocation != null)
        '📍 ${primaryLocation!.name}'
            '${primaryLocation!.address != null && primaryLocation!.address!.isNotEmpty ? ' — ${primaryLocation!.address}' : ''}',
    ];

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          foregroundColor: AppColors.primary,
          child: Text(
            customer.initials,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitleLines.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in subtitleLines)
                    Text(line, style: const TextStyle(fontSize: 12.5)),
                ],
              ),
        isThreeLine: subtitleLines.length > 1,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (owes ? AppColors.danger : AppColors.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                owes ? AppFormatters.kes(customer.balance) : 'No balance',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: owes ? AppColors.danger : AppColors.success,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
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
              const Icon(Icons.people_outline, size: 56, color: AppColors.primary),
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
