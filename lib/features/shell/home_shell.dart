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
import '../inventory/stock_transfers_page.dart';
import '../reports/reports_page.dart';
import '../riders/riders_page.dart';
import '../sales/sales_page.dart';
import '../settings/settings_page.dart';
import '../suppliers/supplier_prices_page.dart';
import '../suppliers/suppliers_page.dart';
import '../cylinders/cylinder_fleet_page.dart';
import '../cylinders/cylinder_tracking_page.dart';
import '../cylinders/exchange_alerts_page.dart';

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
    StockPage(),
    CustomersPage(),
    SettingsPage(),
  ];

  void _openDrawerScreen(Widget screen, String title) {
    Navigator.pop(context); // close the drawer
    _openSecondaryScreen(screen, title);
  }

  void _openSecondaryScreen(Widget screen, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => MediaQuery.sizeOf(routeContext).width >= 750
            ? _buildDesktopSecondaryScreen(routeContext, screen, title)
            : Scaffold(
                appBar: AppBar(title: Text(title)),
                body: screen,
              ),
      ),
    );
  }

  Widget _buildDesktopSecondaryScreen(
    BuildContext routeContext,
    Widget screen,
    String title,
  ) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 270, child: _buildDesktopSidebar()),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(routeContext).pop(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: screen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      color: AppColors.primaryDark,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 22),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: AppColors.accent,
                      size: 30,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Gateway Gas',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
              _desktopSectionHeader('Workspace'),
              _desktopPrimaryTile(0, Icons.dashboard_outlined, 'Dashboard'),
              _desktopPrimaryTile(1, Icons.point_of_sale_outlined, 'Sales'),
              _desktopPrimaryTile(2, Icons.inventory_2_outlined, 'Stock'),
              _desktopPrimaryTile(3, Icons.people_outline, 'Customers'),
              _desktopPrimaryTile(4, Icons.settings_outlined, 'Settings'),
              _desktopSectionHeader('Analytics'),
              _desktopSecondaryTile(
                Icons.bar_chart_outlined,
                'Reports',
                const ReportsPage(),
              ),
              _desktopSecondaryTile(
                Icons.category_outlined,
                'Product catalogue',
                const ProductsPage(),
              ),
              _desktopSectionHeader('Stock & suppliers'),
              _desktopSecondaryTile(
                Icons.swap_horiz_outlined,
                'Stock transfers',
                const StockTransfersPage(),
              ),
              _desktopSecondaryTile(
                Icons.shopping_basket_outlined,
                'Purchase orders',
                const PurchaseOrdersPage(),
              ),
              _desktopSecondaryTile(
                Icons.local_shipping_outlined,
                'Suppliers',
                const SuppliersPage(),
              ),
              _desktopSecondaryTile(
                Icons.price_check_outlined,
                'Supplier prices',
                const SupplierPricesPage(),
              ),
              _desktopSectionHeader('Operations'),
              _desktopSecondaryTile(
                Icons.delivery_dining_outlined,
                'Deliveries',
                const DeliveriesPage(),
              ),
              _desktopSecondaryTile(
                Icons.two_wheeler_outlined,
                'Riders',
                const RidersPage(),
              ),
              _desktopSecondaryTile(
                Icons.cyclone_outlined,
                'Cylinder fleet',
                const CylinderFleetPage(),
              ),
              _desktopSecondaryTile(
                Icons.cyclone_outlined,
                'Cylinder tracking',
                const CylinderTrackingPage(),
              ),
              _desktopSecondaryTile(
                Icons.flag_outlined,
                'Cylinder follow-ups',
                const ExchangeAlertsPage(),
              ),
              const SizedBox(height: 18),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => context.read<AuthController>().signOut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _desktopPrimaryTile(int index, IconData icon, String label) {
    final selected = _index == index;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          icon,
          color: selected ? AppColors.accent : Colors.white70,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        onTap: () {
          setState(() => _index = index);
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _desktopSecondaryTile(IconData icon, String label, Widget screen) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const SizedBox(width: 20),
        title: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _openSecondaryScreen(screen, label),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
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
            _sectionHeader('Analytics'),
            _drawerTile(
              Icons.bar_chart_outlined,
              'Reports',
              () => _openDrawerScreen(const ReportsPage(), 'Reports'),
            ),
            _sectionHeader('Stock & suppliers'),
            _drawerTile(
              Icons.inventory_outlined,
              'Stock levels',
              () => _openDrawerScreen(const StockPage(), 'Stock levels'),
            ),
            _drawerTile(
              Icons.category_outlined,
              'Product catalogue',
              () =>
                  _openDrawerScreen(const ProductsPage(), 'Product catalogue'),
            ),
            _drawerTile(
              Icons.swap_horiz_outlined,
              'Stock transfers',
              () => _openDrawerScreen(
                const StockTransfersPage(),
                'Stock transfers',
              ),
            ),
            _drawerTile(
              Icons.shopping_basket_outlined,
              'Purchase orders',
              () => _openDrawerScreen(
                const PurchaseOrdersPage(),
                'Purchase orders',
              ),
            ),
            _drawerTile(
              Icons.local_shipping_outlined,
              'Suppliers',
              () => _openDrawerScreen(const SuppliersPage(), 'Suppliers'),
            ),
            _drawerTile(
              Icons.price_check_outlined,
              'Supplier prices',
              () => _openDrawerScreen(
                const SupplierPricesPage(),
                'Supplier prices',
              ),
            ),
            _sectionHeader('Operations'),
            _drawerTile(
              Icons.delivery_dining_outlined,
              'Deliveries',
              () => _openDrawerScreen(const DeliveriesPage(), 'Deliveries'),
            ),
            _drawerTile(
              Icons.two_wheeler_outlined,
              'Riders',
              () => _openDrawerScreen(const RidersPage(), 'Riders'),
            ),
            _drawerTile(
              Icons.cyclone_outlined,
              'Cylinder fleet',
              () => _openDrawerScreen(
                const CylinderFleetPage(),
                'Cylinder fleet',
              ),
            ),
            _drawerTile(
              Icons.cyclone_outlined,
              'Cylinder tracking',
              () => _openDrawerScreen(
                const CylinderTrackingPage(),
                'Cylinder tracking',
              ),
            ),
            _drawerTile(
              Icons.flag_outlined,
              'Cylinder follow-ups',
              () => _openDrawerScreen(
                const ExchangeAlertsPage(),
                'Cylinder follow-ups',
              ),
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 750;

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
      body: Row(
        children: [
          SizedBox(width: 270, child: _buildDesktopSidebar()),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
                    child: Row(
                      children: [
                        Text(
                          _titles[_index],
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        userMenu,
                      ],
                    ),
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
