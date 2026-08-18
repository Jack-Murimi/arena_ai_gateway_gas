import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _branches = [];
  String? _branchId;
  bool _loadingBranches = true;
  bool _savingBranch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    try {
      final branches =
          await _supabase.from('branches').select('id, name').order('name');
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = auth.branchId;
        _loadingBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _saveDefaultBranch(String? branchId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || branchId == null) return;
    setState(() {
      _savingBranch = true;
      _branchId = branchId;
    });
    try {
      await _supabase
          .from('profiles')
          .update({'branch_id': branchId}).eq('id', uid);
      await context.read<AuthController>().refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default branch saved — new sales will use it.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not save: ${e.toString().replaceAll('Exception: ', '')}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingBranch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle,
                    color: AppColors.primary),
                title: const Text(
                  'Signed in as',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                subtitle: Text(
                  user?.email ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: const Icon(Icons.verified_user_outlined,
                    color: AppColors.success),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.storefront_outlined,
                            color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Default branch',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Select your branch',
                      ),
                      items: [
                        for (final b in _branches)
                          DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          ),
                      ],
                      onChanged:
                          _savingBranch ? null : (v) => _saveDefaultBranch(v),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'New sales will default to this branch. You can '
                      'still change it per sale.',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_outlined,
                    color: AppColors.primary),
                title: const Text(
                  'Supabase',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                subtitle: Text(
                  AppConfig.hasSupabaseConfigured
                      ? AppConfig.supabaseUrl
                      : 'Not configured — pass SUPABASE_URL & SUPABASE_ANON_KEY '
                          'via --dart-define',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppConfig.hasSupabaseConfigured
                        ? AppColors.textPrimary
                        : AppColors.danger,
                  ),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.info_outline, color: AppColors.primary),
                title: Text(
                  'Version',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                subtitle: Text(
                  '${AppConfig.appName} v${AppConfig.appVersion}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.business_outlined, color: AppColors.primary),
                title: Text('Gateway Gas Enterprises'),
                subtitle: Text('POS & ERP system'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => context.read<AuthController>().signOut(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
