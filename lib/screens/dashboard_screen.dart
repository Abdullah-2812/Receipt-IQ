import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  double _totalSpending = 0;
  int _receiptCount = 0;
  double _thisMonthSpending = 0;
  double _thisWeekSpending = 0;
  Map<String, double> _categorySpending = {};

  static String _formatRupee(double amount) => NumberFormat.currency(
        locale: 'en_PK',
        symbol: 'Rs ',
        decimalDigits: 2,
      ).format(amount);

  bool _isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 400;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _editName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ctrl = TextEditingController(text: user.displayName ?? '');
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a name';
              if (v.trim().length < 2) return 'Name must be at least 2 characters';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName == (user.displayName ?? '')) return;

    try {
      await user.updateDisplayName(newName);
      await user.reload(); // pull the fresh server-side user object
      if (mounted) setState(() {});
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update name: ${e.message ?? e.code}')),
      );
    }
  }

  Future<void> _loadData() async {
    await SyncService.instance.waitForFirstSync();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final weekDay = now.weekday;
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day - (weekDay - 1),
    );

    final results = await Future.wait([
      DatabaseService.instance.getTotalSpending(),
      DatabaseService.instance.getReceiptCount(),
      DatabaseService.instance.getSpendingInRange(monthStart, now),
      DatabaseService.instance.getSpendingInRange(weekStart, now),
      DatabaseService.instance.getSpendingByCategory(),
    ]);

    if (mounted) {
      setState(() {
        _totalSpending = results[0] as double;
        _receiptCount = results[1] as int;
        _thisMonthSpending = results[2] as double;
        _thisWeekSpending = results[3] as double;
        _categorySpending = results[4] as Map<String, double>;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isNarrow = _isNarrow(context);
    final padding = isNarrow ? 12.0 : 16.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(context, isNarrow),
          const SizedBox(height: 16),
          _buildTotalSpendingCard(context, isNarrow),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      context, 'This Month', _thisMonthSpending, isNarrow)),
              SizedBox(width: isNarrow ? 8 : 12),
              Expanded(
                  child: _buildStatCard(
                      context, 'This Week', _thisWeekSpending, isNarrow)),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Category Spending',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          _buildCategorySpendingList(context, isNarrow),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context, bool isNarrow) {
    final avatarRadius = isNarrow ? 24.0 : 28.0;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    final email = user?.email ?? '';
    final greetingName = displayName.isNotEmpty
        ? displayName.split(' ').first
        : (email.isNotEmpty ? email.split('@').first : 'there');
    final initials = displayName.isNotEmpty
        ? displayName
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0])
            .join()
            .toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : '?');

    return Card(
      child: Padding(
        padding: EdgeInsets.all(isNarrow ? 12 : 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _editName,
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: AppColors.primary,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: avatarRadius * 0.8,
                    fontWeight: FontWeight.w600,
                    color: AppColors.surface,
                  ),
                ),
              ),
            ),
            SizedBox(width: isNarrow ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  Text(
                    greetingName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSpendingCard(BuildContext context, bool isNarrow) {
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: EdgeInsets.all(isNarrow ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Spending',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.surface.withOpacity(0.9),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatRupee(_totalSpending),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.surface,
                    fontSize: isNarrow ? 22 : null,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_receiptCount receipts',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.surface.withOpacity(0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      BuildContext context, String label, double amount, bool isNarrow) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isNarrow ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatRupee(amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySpendingList(BuildContext context, bool isNarrow) {
    return Column(
      children: ExpenseCategories.categories.map((category) {
        final amount = _categorySpending[category] ?? 0.0;
        final percentage = _totalSpending > 0
            ? (amount / _totalSpending * 100).toStringAsFixed(1)
            : '0.0';
        final color =
            ExpenseCategories.categoryColors[category] ?? AppColors.textHint;
        final icon =
            ExpenseCategories.categoryIcons[category] ?? Icons.more_horiz;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Text(
              category,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatRupee(amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
