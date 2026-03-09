import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt_model.dart';
import '../utils/constants.dart';
import 'receipt_info_screen.dart';

/// Dummy receipts for demo. Replace with DB later.
List<Receipt> _dummyReceipts() {
  final now = DateTime.now();
  return [
    Receipt(
      id: '1',
      merchantName: 'Al-Madina Mart',
      date: now.subtract(const Duration(days: 2)),
      totalAmount: 2450.00,
      category: 'Groceries',
      imagePath: null,
      items: [
        ReceiptItem(name: 'Rice 5kg', quantity: 1, price: 1200, totalPrice: 1200),
        ReceiptItem(name: 'Oil 1L', quantity: 2, price: 625, totalPrice: 1250),
      ],
      notes: null,
      createdAt: now,
    ),
    Receipt(
      id: '2',
      merchantName: 'Pizza Hut',
      date: now.subtract(const Duration(days: 5)),
      totalAmount: 1890.00,
      category: 'Food & Dining',
      imagePath: null,
      items: [
        ReceiptItem(name: 'Medium Pizza', quantity: 1, price: 1200, totalPrice: 1200),
        ReceiptItem(name: 'Drinks', quantity: 2, price: 345, totalPrice: 690),
      ],
      notes: 'Family dinner',
      createdAt: now,
    ),
    Receipt(
      id: '3',
      merchantName: 'Shell Petrol Pump',
      date: now.subtract(const Duration(days: 7)),
      totalAmount: 5000.00,
      category: 'Transportation',
      imagePath: null,
      items: [],
      notes: null,
      createdAt: now,
    ),
  ];
}

class ReceiptsListScreen extends StatelessWidget {
  const ReceiptsListScreen({super.key});

  static String _formatRupee(double amount) {
    return NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs ',
      decimalDigits: 2,
    ).format(amount);
  }

  static String _formatDate(DateTime d) {
    return DateFormat('MMM dd, yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final receipts = _dummyReceipts();
    if (receipts.isEmpty) {
      return _buildEmptyState(context);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: receipts.length,
      itemBuilder: (context, index) {
        final receipt = receipts[index];
        final color = ExpenseCategories.categoryColors[receipt.category] ??
            AppColors.textHint;
        final icon = ExpenseCategories.categoryIcons[receipt.category] ??
            Icons.receipt_long;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Text(
              receipt.merchantName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${_formatDate(receipt.date)} · ${receipt.category}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatRupee(receipt.totalAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textHint),
              ],
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ReceiptInfoScreen(receipt: receipt),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 80,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 24),
            Text(
              'No receipts yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Use "Scan Receipt" to add your first receipt',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
