import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../inventory/models/product.dart';
import 'data/customer_repository.dart';
import 'models/customer.dart';

/// Add / edit a customer: household details, the people who order gas
/// (name + phone), and delivery locations (each with an optional default
/// cylinder picked from products).
class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({
    super.key,
    this.customer,
    this.contacts,
    this.locations,
  });

  final Customer? customer;
  final List<CustomerContact>? contacts;
  final List<CustomerLocation>? locations;

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _ContactInput {
  _ContactInput({
    required this.name,
    required this.phone,
    this.isPrimary = false,
  });

  final TextEditingController name;
  final TextEditingController phone;
  bool isPrimary;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _LocationInput {
  _LocationInput({
    required this.name,
    required this.address,
    this.isPrimary = false,
    this.defaultProductId,
  });

  final TextEditingController name;
  final TextEditingController address;
  bool isPrimary;
  String? defaultProductId;

  void dispose() {
    name.dispose();
    address.dispose();
  }
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _repo = CustomerRepository();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();
  final List<_ContactInput> _contacts = [];
  final List<_LocationInput> _locations = [];

  List<Product> _products = [];
  bool _productsFailed = false;
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    if (c != null) {
      _nameCtrl.text = c.name;
      _emailCtrl.text = c.email ?? '';
      _creditLimitCtrl.text =
          c.creditLimit == 0 ? '' : c.creditLimit.toStringAsFixed(0);
    }

    final contacts = widget.contacts;
    if (contacts != null && contacts.isNotEmpty) {
      for (final ct in contacts) {
        _contacts.add(_ContactInput(
          name: TextEditingController(text: ct.name),
          phone: TextEditingController(text: ct.phone),
          isPrimary: ct.isPrimary,
        ));
      }
    } else {
      _contacts.add(_ContactInput(
        name: TextEditingController(),
        phone: TextEditingController(),
        isPrimary: true,
      ));
    }

    final locations = widget.locations;
    if (locations != null && locations.isNotEmpty) {
      for (final l in locations) {
        _locations.add(_LocationInput(
          name: TextEditingController(text: l.name),
          address: TextEditingController(text: l.address ?? ''),
          isPrimary: l.isPrimary,
          defaultProductId: l.defaultProductId,
        ));
      }
    } else {
      _locations.add(_LocationInput(
        name: TextEditingController(),
        address: TextEditingController(),
        isPrimary: true,
      ));
    }

    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _repo.fetchProducts();
      if (!mounted) return;
      setState(() => _products = products);
    } catch (_) {
      if (!mounted) return;
      setState(() => _productsFailed = true);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _creditLimitCtrl.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    for (final l in _locations) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_contacts.every((c) =>
        c.name.text.trim().isEmpty || c.phone.text.trim().isEmpty)) {
      setState(() => _saveError =
          'Add at least one contact with a name and phone number.');
      return;
    }
    if (_locations.every((l) => l.name.text.trim().isEmpty)) {
      setState(() =>
          _saveError = 'Add at least one location with a name.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await _repo.saveCustomer(
        customerId: widget.customer?.id,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        creditLimit: double.tryParse(_creditLimitCtrl.text.trim()) ?? 0,
        contacts: [
          for (final c in _contacts)
            if (c.name.text.trim().isNotEmpty && c.phone.text.trim().isNotEmpty)
              CustomerContact(
                name: c.name.text.trim(),
                phone: c.phone.text.trim(),
                isPrimary: c.isPrimary,
              ),
        ],
        locations: [
          for (final l in _locations)
            if (l.name.text.trim().isNotEmpty)
              CustomerLocation(
                name: l.name.text.trim(),
                address:
                    l.address.text.trim().isEmpty ? null : l.address.text.trim(),
                isPrimary: l.isPrimary,
                defaultProductId: l.defaultProductId,
              ),
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit customer' : 'New customer'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _sectionTitle(context, 'Customer'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Customer name *',
                        hintText: 'e.g. Mama Njeri / Riverside Apartments',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the customer name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _creditLimitCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Credit limit KSh (optional)',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(
              context,
              'People who order gas (${_contacts.length})',
            ),
            Text(
              'A customer can have several people ordering — house keeper, '
              'security, children. Mark the main one with ⭐.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _contacts.length; i++) ...[
              _contactRow(i),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _contacts.add(_ContactInput(
                    name: TextEditingController(),
                    phone: TextEditingController(),
                  ));
                }),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add contact'),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(
              context,
              'Locations (${_locations.length})',
            ),
            Text(
              'Delivery points for this customer. Each can have its own '
              'default cylinder size & brand.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _locations.length; i++) ...[
              _locationCard(i),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _locations.add(_LocationInput(
                    name: TextEditingController(),
                    address: TextEditingController(),
                  ));
                }),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add location'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _saveError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isEditing ? 'Save changes' : 'Save customer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _contactRow(int index) {
    final c = _contacts[index];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: c.name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. House keeper',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: c.phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '07XX XXX XXX',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: c.isPrimary ? 'Main contact' : 'Set as main contact',
              icon: Icon(
                c.isPrimary ? Icons.star : Icons.star_border,
                color: c.isPrimary ? AppColors.accent : AppColors.textSecondary,
              ),
              onPressed: () => setState(() {
                for (var i = 0; i < _contacts.length; i++) {
                  _contacts[i].isPrimary = i == index;
                }
              }),
            ),
            IconButton(
              tooltip: 'Remove contact',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _contacts.length > 1
                  ? () => setState(() => _contacts.removeAt(index))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationCard(int index) {
    final l = _locations[index];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: l.name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Location name *',
                      hintText: 'e.g. Home, Shop, Riverside Apts',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip:
                      l.isPrimary ? 'Main location' : 'Set as main location',
                  icon: Icon(
                    l.isPrimary ? Icons.star : Icons.star_border,
                    color:
                        l.isPrimary ? AppColors.accent : AppColors.textSecondary,
                  ),
                  onPressed: () => setState(() {
                    for (var i = 0; i < _locations.length; i++) {
                      _locations[i].isPrimary = i == index;
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Remove location',
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: _locations.length > 1
                      ? () => setState(() => _locations.removeAt(index))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: l.address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Address / landmark (optional)',
                hintText: 'e.g. House 12, River Road, near KPLC',
                isDense: true,
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (_productsFailed)
              const Text(
                'Products not available yet — they appear here once the '
                'Inventory module is set up.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )
            else
              DropdownButtonFormField<String?>(
                initialValue: l.defaultProductId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Default cylinder (optional)',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None'),
                  ),
                  for (final p in _products)
                    DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.displayName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => l.defaultProductId = v),
              ),
          ],
        ),
      ),
    );
  }
}
