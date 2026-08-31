import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'data/rider_repository.dart';
import 'models/rider.dart';

/// Admin: create or edit a rider (auth account + profile).
class RiderFormPage extends StatefulWidget {
  const RiderFormPage({super.key, this.rider});

  final RiderSummary? rider;

  @override
  State<RiderFormPage> createState() => _RiderFormPageState();
}

class _RiderFormPageState extends State<RiderFormPage> {
  final _repo = RiderRepository();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  List<Map<String, dynamic>> _branches = [];
  String? _branchId;
  bool _loadingBranches = true;
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.rider != null;

  @override
  void initState() {
    super.initState();
    final rider = widget.rider;
    if (rider != null) {
      _nameCtrl.text = rider.fullName;
      _phoneCtrl.text = rider.phone ?? '';
      _branchId = rider.branchId;
      _loadEmail(rider.id);
    }
    _loadBranches();
  }

  Future<void> _loadEmail(String riderId) async {
    try {
      final email = await _repo.fetchRiderEmail(riderId);
      if (!mounted || email == null) return;
      setState(() => _emailCtrl.text = email);
    } catch (_) {}
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _repo.fetchBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBranches = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      if (_isEditing) {
        await _repo.updateRider(
          riderId: widget.rider!.id,
          email: _emailCtrl.text.trim(),
          fullName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          branchId: _branchId,
        );
      } else {
        await _repo.createRider(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          fullName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          branchId: _branchId,
        );
      }
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
      appBar: AppBar(title: Text(_isEditing ? 'Edit rider' : 'New rider')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name *',
                        hintText: 'e.g. Romano Sifuna',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the rider name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        hintText: '07XX XXX XXX',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Home branch *',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      hint: _loadingBranches
                          ? const Text('Loading…')
                          : const Text('Select branch'),
                      items: [
                        for (final b in _branches)
                          DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          ),
                      ],
                      onChanged: (v) => setState(() => _branchId = v),
                      validator: (v) => v == null ? 'Select a branch' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Login email *',
                        hintText: 'rider@gatewaygas.co.ke',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Enter the login email';
                        if (!value.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    if (!_isEditing) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Login password *',
                          hintText: 'Min 6 characters',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Password must be at least 6 characters'
                            : null,
                      ),
                    ],
                  ],
                ),
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
                  : Icon(
                      _isEditing ? Icons.save_outlined : Icons.person_add_alt_1,
                    ),
              label: Text(_isEditing ? 'Save rider' : 'Create rider'),
            ),
          ],
        ),
      ),
    );
  }
}
