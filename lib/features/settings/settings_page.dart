import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Database status: waiting for Supabase connection.\n'
            'Run supabase/migrations/0001_initial_schema.sql in your project '
            'to create the tables.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
