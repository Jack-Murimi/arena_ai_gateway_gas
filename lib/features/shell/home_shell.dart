import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../customers/customers_page.dart';
import '../dashboard/dashboard_page.dart';
import '../deliveries/deliveries_page.dart';
import '../inventory/products_page.dart';
import '../inventory/purchase_orders_page.dart';
import '../inventory/stock_page.dart';
import '../reports/reports_page.dart';
import '../riders/riders_page.dart';
import '../sales/sales_page.dart';
import '../settings/settings_page.dart';

/// Main authenticated shell: navigation rail on wide screens,
/// bottom navigation bar on phones, and a hamburger drawer that
/// holds Reports plus future screens (purchases, suppliers…).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Sales',
    'Stock',
    'Customers',
    'Settings',
  ];

  static const _pages = [
    DashboardPage(),
    SalesPage(),
    ProductsPage(),
    CustomersPage(),
    SettingsPage(),
  ];

  void _openDrawerScreen(Widget screen, String title) {
    Navigator.pop(context); // close the drawer
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: screen,
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
            final futureItems = <(IconData, String)>[
              (Icons.local_shipping_outlined, 'Suppliers'),
              (Icons.cyclone_outlined, 'Cylinder deposits'),
            ];

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Row(
                children: const [
                  Icon(
                    Icons.local_fire_department,
                    color: AppColors.accent,
                    size: 32,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Gateway Gas',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text(
                'Reports',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () => _openDrawerScreen(const ReportsPage(), 'Reports'),
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining_outlined),
              title: const Text(
                'Deliveries',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () => _openDrawerScreen(const DeliveriesPage(), 'Deliveries'),
            ),
            ListTile(
              leading: const Icon(Icons.two_wheeler_outlined),
              title: const Text(
                'Riders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () => _openDrawerScreen(const RidersPage(), 'Riders'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: const Text(
                'Stock levels',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () => _openDrawerScreen(const StockPage(), 'Stock levels'),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_basket_outlined),
              title: const Text(
                'Purchase orders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onTap: () =>
                  _openDrawerScreen(const PurchaseOrdersPage(), 'Purchase orders'),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Coming soon',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            for (final (icon, label) in futureItems)
              ListTile(
                leading: Icon(icon, color: AppColors.textSecondary),
                title: Text(
                  label,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                enabled: false,
              ),
            const Spacer(),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final content = IndexedStack(index: _index, children: _pages);

    final navBar = NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: 'Sales',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Stock',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Customers',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );

    final userMenu = PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        if (value == 'signout') {
          context.read<AuthController>().signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            context.read<AuthController>().user?.email ?? 'Signed in',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Sign out'),
            ],
          ),
        ),
      ],
    );

    if (!isWide) {
      return Scaffold(
        drawer: _buildDrawer(context),
        appBar: AppBar(title: Text(_titles[_index]), actions: [userMenu]),
        body: content,
        bottomNavigationBar: navBar,
      );
    }

    return Scaffold(
      drawer: _buildDrawer(context),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 210,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: AppColors.primaryDark,
            selectedIconTheme: const IconThemeData(color: AppColors.accent),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            unselectedIconTheme: const IconThemeData(color: Colors.white70),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white70),
            leading: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: AppColors.accent,
                    size: 32,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Gateway Gas',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale),
                label: Text('Sales'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: Text('Stock'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Customers'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: userMenu,
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _titles[_index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
