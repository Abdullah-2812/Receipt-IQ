import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/constants.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const double _totalSpending = 45230.50;
  static const int _receiptCount = 23;
  static const double _thisMonthSpending = 28450.00;
  static const double _thisWeekSpending = 8750.00;
  static const Map<String, double> _categorySpending = {
    'Food & Dining': 12500.00,
    'Groceries': 9800.50,
    'Transportation': 4500.00,
    'Shopping': 7200.00,
    'Bills & Utilities': 6500.00,
    'Medicines': 2300.00,
    'Entertainment': 1430.00,
    'Other': 2000.00,
  };

  static String _formatRupee(double amount) {
    return NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs ',
      decimalDigits: 2,
    ).format(amount);
  }

  bool _isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 400;

  @override
  Widget build(BuildContext context) {
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
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isNarrow ? 12 : 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: AppColors.primaryLight,
              child: Icon(
                Icons.person,
                size: avatarRadius * 1.1,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: isNarrow ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  Text(
                    'Track your expenses',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
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
