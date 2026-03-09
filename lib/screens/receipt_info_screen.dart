import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt_model.dart';
import '../utils/constants.dart';

class ReceiptInfoScreen extends StatelessWidget {
  const ReceiptInfoScreen({super.key, required this.receipt});

  final Receipt receipt;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Details'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImageSection(context),
            const SizedBox(height: 20),
            _buildField(context, 'Merchant', receipt.merchantName,
                Icons.store_outlined),
            _buildField(context, 'Date', _formatDate(receipt.date),
                Icons.calendar_today_outlined),
            _buildField(
              context,
              'Total',
              _formatRupee(receipt.totalAmount),
              Icons.attach_money,
            ),
            _buildField(context, 'Category', receipt.category,
                Icons.category_outlined),
            if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
              _buildField(
                  context, 'Notes', receipt.notes!, Icons.note_outlined),
            ],
            if (receipt.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Items',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              ...receipt.items.map((item) => _buildItemRow(context, item)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: receipt.imagePath != null && receipt.imagePath!.isNotEmpty
          ? Image.asset(
              receipt.imagePath!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildImagePlaceholder(context),
            )
          : _buildImagePlaceholder(context),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      color: AppColors.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 64,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 8),
          Text(
            'Receipt image',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
      BuildContext context, String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
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

  Widget _buildItemRow(BuildContext context, ReceiptItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          item.name,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          'Qty: ${item.quantity} × ${_formatRupee(item.price)}',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Text(
          _formatRupee(item.totalPrice),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
