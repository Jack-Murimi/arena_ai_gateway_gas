import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/rider_shell.dart';

/// Root widget of the Gateway Gas Enterprises app.
class GatewayGasApp extends StatelessWidget {
  const GatewayGasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthController(),
      child: MaterialApp(
        title: 'Gateway Gas Enterprises',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Consumer<AuthController>(
          builder: (context, auth, _) {
            if (auth.status == AuthStatus.loading ||
                (auth.status == AuthStatus.authenticated &&
                    auth.profileLoading)) {
              return const _SplashScreen();
            }
            return switch (auth.status) {
              AuthStatus.loading => const _SplashScreen(),
              AuthStatus.authenticated => auth.isRider
                  ? const RiderShell()
                  : const HomeShell(),
              AuthStatus.unauthenticated => const LoginScreen(),
            };
          },
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 72, color: AppColors.accent),
            SizedBox(height: 16),
            Text(
              'Gateway Gas Enterprises',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
