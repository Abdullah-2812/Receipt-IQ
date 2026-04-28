import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sync_service.dart';
import '../utils/constants.dart';

// Picks a "nice" axis ceiling and label interval for a given data max.
// Targets ~5 evenly-spaced labels at round numbers (10/20/50 * 10^n) so
// the y-axis doesn't end with two near-identical labels stacked on top
// of each other (e.g. "60k" and "61k" when maxY is auto-computed).
({double max, double interval}) _niceAxis(double dataMax) {
  if (dataMax <= 0) return (max: 1, interval: 1);
  final rough = dataMax / 5;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final scaled = rough / mag;
  final double niceScaled = scaled <= 1
      ? 1
      : scaled <= 2
          ? 2
          : scaled <= 5
              ? 5
              : 10;
  final interval = niceScaled * mag;
  final niceMax =
      (dataMax * 1.1 / interval).ceilToDouble() * interval;
  return (max: niceMax, interval: interval);
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  double _totalSpending = 0;
  int _receiptCount = 0;
  // Ordered oldest -> newest, always 6 entries (zero-fill for missing months).
  List<MapEntry<String, double>> _monthly = [];
  Map<String, double> _categoryData = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchSummary();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSummary() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final summary = await SyncService.instance.fetchAnalyticsSummary();

      // Backend's by_month omits months with no receipts. Zero-fill so
      // the line chart always shows 6 contiguous month labels.
      final byMonthRaw =
          (summary['by_month'] as List? ?? []).cast<Map<String, dynamic>>();
      final byMonthLookup = {
        for (final entry in byMonthRaw)
          entry['month'] as String: (entry['total'] as num).toDouble(),
      };
      final now = DateTime.now();
      final monthly = <MapEntry<String, double>>[];
      for (int i = 5; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i);
        final fullKey = DateFormat('MMM yyyy').format(m);    // 'Apr 2026'
        final shortLabel = DateFormat('MMM').format(m);      // 'Apr'
        monthly.add(MapEntry(shortLabel, byMonthLookup[fullKey] ?? 0));
      }

      final byCatRaw =
          (summary['by_category'] as List? ?? []).cast<Map<String, dynamic>>();
      final categoryData = {
        for (final entry in byCatRaw)
          entry['category'] as String: (entry['total'] as num).toDouble(),
      };

      if (!mounted) return;
      setState(() {
        _totalSpending = (summary['total_spending'] as num? ?? 0).toDouble();
        _receiptCount = (summary['receipt_count'] as num? ?? 0).toInt();
        _monthly = monthly;
        _categoryData = categoryData;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load analytics. ${e.toString().split('\n').first}';
        _loading = false;
      });
    }
  }

  static String _formatRupee(double amount) =>
      NumberFormat.currency(locale: 'en_PK', symbol: 'Rs ', decimalDigits: 0)
          .format(amount);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState();
    }
    if (_receiptCount == 0) {
      return _buildEmptyState();
    }
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.trending_up), text: 'Trends'),
            Tab(icon: Icon(Icons.pie_chart_outline), text: 'By Category'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                onRefresh: _fetchSummary,
                child: _buildTrendsTab(),
              ),
              RefreshIndicator(
                onRefresh: _fetchSummary,
                child: _buildCategoryTab(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Loading / error / empty ───────────────────────────────────────────────

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchSummary,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text(
              'No receipts yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scan or add a receipt to see analytics here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Trends tab ────────────────────────────────────────────────────────────

  Widget _buildTrendsTab() {
    final values = _monthly.map((e) => e.value).toList();
    final monthLabels = _monthly.map((e) => e.key).toList();
    final current = values.last;
    final previous = values.length >= 2 ? values[values.length - 2] : 0.0;
    final delta = current - previous;
    final pct =
        previous == 0 ? null : ((delta / previous) * 100).toStringAsFixed(1);
    final isUp = delta >= 0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Monthly Spending – Last 6 Months',
            'Live from your synced receipts.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
              child: SizedBox(
                height: 220,
                child: _buildLineChart(monthLabels, values),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'Current Month',
                  _formatRupee(current),
                  AppColors.primary,
                  Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard(
                  'vs Last Month',
                  pct == null ? '—' : '${isUp ? '+' : ''}$pct%',
                  pct == null
                      ? AppColors.textSecondary
                      : (isUp ? AppColors.error : AppColors.accent),
                  pct == null
                      ? Icons.remove
                      : (isUp ? Icons.trending_up : Icons.trending_down),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryCard(
            'Total Spending (All Time)',
            '${_formatRupee(_totalSpending)}  ·  $_receiptCount receipts',
            AppColors.accent,
            Icons.payments_outlined,
          ),
          const SizedBox(height: 16),
          _buildMonthlyBreakdownTable(monthLabels, values),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<String> monthLabels, List<double> values) {
    final maxVal =
        values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final axis = _niceAxis(maxVal);
    final spots = List.generate(
      values.length,
      (i) => FlSpot(i.toDouble(), values[i]),
    );

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.textHint.withOpacity(0.4),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= monthLabels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    monthLabels[idx],
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: axis.interval,
              getTitlesWidget: (value, _) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  '${(value / 1000).toStringAsFixed(0)}k',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: axis.max,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withOpacity(0.1),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.primary,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyBreakdownTable(
      List<String> monthLabels, List<double> values) {
    final maxVal =
        values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Month-by-Month',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    )),
            const SizedBox(height: 8),
            ...List.generate(values.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(monthLabels[i],
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: maxVal > 0 ? values[i] / (maxVal * 1.1) : 0,
                        backgroundColor:
                            AppColors.primary.withOpacity(0.1),
                        color: AppColors.primary,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRupee(values[i]),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Category tab ──────────────────────────────────────────────────────────

  Widget _buildCategoryTab() {
    final total = _categoryData.values.fold(0.0, (a, b) => a + b);
    final categories = _categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Spending by Category',
            'Live from your synced receipts.',
          ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: SizedBox(
                  height: 220,
                  child: _buildBarChart(categories),
                ),
              ),
            ),
          const SizedBox(height: 16),
          ...categories.map((e) {
            final pct = total > 0
                ? (e.value / total * 100).toStringAsFixed(1)
                : '0.0';
            final color = ExpenseCategories.categoryColors[e.key] ??
                AppColors.textHint;
            final icon = ExpenseCategories.categoryIcons[e.key] ??
                Icons.more_horiz;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(e.key,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatRupee(e.value),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text('$pct%',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<MapEntry<String, double>> categories) {
    final maxVal =
        categories.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final axis = _niceAxis(maxVal);
    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) {
              final cat = categories[group.x.toInt()];
              return BarTooltipItem(
                '${cat.key}\n${_formatRupee(cat.value)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= categories.length) {
                  return const SizedBox.shrink();
                }
                final icon =
                    ExpenseCategories.categoryIcons[categories[idx].key] ??
                        Icons.more_horiz;
                final color =
                    ExpenseCategories.categoryColors[categories[idx].key] ??
                        AppColors.textHint;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(icon, size: 14, color: color),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: axis.interval,
              getTitlesWidget: (value, _) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  '${(value / 1000).toStringAsFixed(0)}k',
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textSecondary),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.textHint.withOpacity(0.3),
            strokeWidth: 1,
          ),
        ),
        maxY: axis.max,
        barGroups: List.generate(categories.length, (i) {
          final color =
              ExpenseCategories.categoryColors[categories[i].key] ??
                  AppColors.primary;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: categories[i].value,
                color: color,
                width: 16,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                )),
        const SizedBox(height: 4),
        Text(subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                )),
      ],
    );
  }

  Widget _summaryCard(
      String label, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
