import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'customer_form_page.dart';
import 'data/customer_repository.dart';
import 'models/customer.dart';

/// Full view of one customer: contact people, locations (with default
/// cylinders) and credit account.
class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  final _repo = CustomerRepository();

  List<CustomerContact> _contacts = [];
  List<CustomerLocation> _locations = [];
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
      final contacts = await _repo.fetchContactsByCustomer();
      final locations = await _repo.fetchLocationsByCustomer();
      if (!mounted) return;
      setState(() {
        _contacts = contacts[widget.customer.id] ?? [];
        _locations = locations[widget.customer.id] ?? [];
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

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(
          customer: widget.customer,
          contacts: _contacts,
          locations: _locations,
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            tooltip: 'Edit customer',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _headerCard(customer),
                    const SizedBox(height: 16),
                    _creditCard(customer),
                    const SizedBox(height: 16),
                    _contactsCard(),
                    const SizedBox(height: 16),
                    _locationsCard(),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _headerCard(Customer customer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              foregroundColor: AppColors.primary,
              child: Text(
                customer.initials,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (customer.email != null && customer.email!.isNotEmpty)
                    Text(
                      customer.email!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip(
                        customer.isActive ? 'Active' : 'Inactive',
                        customer.isActive
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      if (customer.balance > 0.001)
                        _chip(
                          'Owes ${AppFormatters.kes(customer.balance)}',
                          AppColors.danger,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _creditCard(Customer customer) {
    final limit = customer.creditLimit;
    final balance = customer.balance;
    final ratio = limit > 0 ? (balance / limit).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Credit account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _creditStat(
                    'Outstanding',
                    AppFormatters.kes(balance),
                    balance > 0.001 ? AppColors.danger : AppColors.success,
                  ),
                ),
                Expanded(
                  child: _creditStat(
                    'Credit limit',
                    limit > 0 ? AppFormatters.kes(limit) : 'No limit',
                    AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (limit > 0) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio.toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: ratio > 0.8 ? AppColors.danger : AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}% of credit limit used',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Payments will be available with the Sales module.',
                  ),
                ),
              ),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _creditStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _contactsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'People who order gas (${_contacts.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No contacts yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final contact in _contacts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    contact.isPrimary ? Icons.star : Icons.person_outline,
                    color: contact.isPrimary
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _chip('Main', AppColors.accent),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(contact.phone),
                  trailing: const Icon(
                    Icons.phone_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _locationsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Locations (${_locations.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_locations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No locations yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final location in _locations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    location.isPrimary
                        ? Icons.star
                        : Icons.place_outlined,
                    color: location.isPrimary
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          location.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (location.isPrimary) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _chip('Main', AppColors.accent),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (location.address != null &&
                          location.address!.isNotEmpty)
                        Text(location.address!),
                      if (location.defaultProductName != null)
                        Text(
                          'Default: ${location.defaultProductName}',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                  'Could not load customer details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure migrations 0001 and 0002 have been run in '
                  'the Supabase SQL Editor.',
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
