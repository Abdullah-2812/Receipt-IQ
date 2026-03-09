import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Analytics page – structure will be shaped based on model in future.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Spending insights and trends (model-driven in future)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 64,
                    color: AppColors.primary.withOpacity(0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Charts & insights placeholder',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This section will be shaped based on the analytics model in future releases.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: const Icon(Icons.pie_chart_outline, color: AppColors.primary),
              ),
              title: const Text('Spending by category'),
              subtitle: const Text('Coming soon'),
            ),
          ),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accentLight.withOpacity(0.5),
                child: const Icon(Icons.trending_up, color: AppColors.accent),
              ),
              title: const Text('Monthly trends'),
              subtitle: const Text('Coming soon'),
            ),
          ),
        ],
      ),
    );
  }
}
