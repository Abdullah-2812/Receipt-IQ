import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'classifier_accuracy_screen.dart';
import 'dashboard_screen.dart';
import 'receipts_list_screen.dart';
import 'upload_screen.dart';
import 'analytics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _dashboardVersion = 0;
  int _receiptsVersion = 0;

  bool get _isNarrowScreen =>
      MediaQuery.sizeOf(context).width < 400;

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    _NavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Receipts'),
    _NavItem(Icons.upload_file_outlined, Icons.upload_file, 'Upload'),
    _NavItem(Icons.analytics_outlined, Icons.analytics, 'Analytics'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_navItems[_selectedIndex].label),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardScreen(key: ValueKey(_dashboardVersion)),
            ReceiptsListScreen(key: ValueKey(_receiptsVersion)),
            const UploadScreen(),
            const AnalyticsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() {
              if (index == 0) _dashboardVersion++;
              if (index == 1) _receiptsVersion++;
              _selectedIndex = index;
            }),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: _navItems
            .map(
              (e) => BottomNavigationBarItem(
                icon: Icon(e.iconOutlined),
                activeIcon: Icon(e.icon),
                label: e.label,
              ),
            )
            .toList(),
      ),
      // Hide on Upload tab: same index (2) makes taps look like "nothing happens"
      // and the FAB would cover the gallery / camera buttons.
      floatingActionButton: _selectedIndex == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _selectedIndex = 2),
              icon: const Icon(Icons.document_scanner),
              label: Text(_isNarrowScreen ? 'Scan' : 'Scan Receipt'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long,
                    size: 48,
                    color: AppColors.surface,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.surface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...List.generate(_navItems.length, (index) {
                    final item = _navItems[index];
                    final selected = _selectedIndex == index;
                    return ListTile(
                      leading: Icon(
                        selected ? item.icon : item.iconOutlined,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        Navigator.of(context).pop();
                      },
                    );
                  }),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.science_outlined,
                      color: AppColors.textSecondary,
                    ),
                    title: const Text('Classifier Accuracy Test'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ClassifierAccuracyScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_outlined,
                      color: AppColors.textSecondary,
                    ),
                    title: Text(
                      'Logout',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await FirebaseAuth.instance.signOut();
                      // AuthWrapper automatically redirects to LoginScreen.
                      // SQLite is preserved — handleLogin on next login decides
                      // whether to wipe based on whether the UID changed.
                    },
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

class _NavItem {
  const _NavItem(this.iconOutlined, this.icon, this.label);
  final IconData iconOutlined;
  final IconData icon;
  final String label;
}
