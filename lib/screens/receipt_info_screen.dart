import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';

class ReceiptInfoScreen extends StatefulWidget {
  const ReceiptInfoScreen({super.key, required this.receipt});

  final Receipt receipt;

  static String buildShareText(Receipt r) {
    String fmt(double v) => NumberFormat.currency(
          locale: 'en_PK', symbol: 'Rs ', decimalDigits: 2)
        .format(v);
    String fmtDate(DateTime d) => DateFormat('MMM dd, yyyy').format(d);

    final buf = StringBuffer();
    buf.writeln('Receipt — ${r.merchantName}');
    buf.writeln(
        'Date: ${fmtDate(r.date)}${r.receiptTime != null ? '  ${r.receiptTime}' : ''}');
    if (r.vendorAddress != null) buf.writeln('Address: ${r.vendorAddress}');
    buf.writeln('Category: ${r.category}');
    if (r.invoiceNumber != null) buf.writeln('Invoice #: ${r.invoiceNumber}');
    if (r.items.isNotEmpty) {
      buf.writeln('\nItems:');
      for (final item in r.items) {
        final qty = item.quantity == item.quantity.truncateToDouble()
            ? item.quantity.toInt().toString()
            : item.quantity.toStringAsFixed(2);
        buf.writeln('  ${item.name}  ×$qty  ${fmt(item.totalPrice)}');
      }
    }
    buf.writeln();
    if (r.subtotal != null) buf.writeln('Subtotal:   ${fmt(r.subtotal!)}');
    if (r.discount != null && r.discount! > 0) {
      buf.writeln('Discount:  -${fmt(r.discount!)}');
    }
    if (r.tax != null) buf.writeln('Tax (GST):  ${fmt(r.tax!)}');
    if (r.fbrPosFee != null) buf.writeln('FBR Fee:    ${fmt(r.fbrPosFee!)}');
    buf.writeln('Total:      ${fmt(r.totalAmount)}');
    if (r.paymentMethod != null) buf.writeln('Payment:    ${r.paymentMethod}');
    if (r.cashPaid != null) buf.writeln('Cash Paid:  ${fmt(r.cashPaid!)}');
    if (r.changeDue != null) buf.writeln('Change:     ${fmt(r.changeDue!)}');
    if (r.notes != null && r.notes!.isNotEmpty) buf.writeln('\nNotes: ${r.notes}');
    buf.write('\nShared via ReceiptIQ');
    return buf.toString();
  }

  @override
  State<ReceiptInfoScreen> createState() => _ReceiptInfoScreenState();
}

class _ReceiptInfoScreenState extends State<ReceiptInfoScreen> {
  late Receipt _receipt;

  static String _formatRupee(double amount) => NumberFormat.currency(
        locale: 'en_PK',
        symbol: 'Rs ',
        decimalDigits: 2,
      ).format(amount);

  static String _formatDate(DateTime d) =>
      DateFormat('MMM dd, yyyy').format(d);

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Receipt'),
        content: Text(
          'Delete the receipt from "${_receipt.merchantName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      SyncService.instance.deleteFromServer(_receipt.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Edit ──────────────────────────────────────────────────────────────────

  void _onEdit() {
    final merchantCtrl =
        TextEditingController(text: _receipt.merchantName);
    final totalCtrl = TextEditingController(
        text: _receipt.totalAmount.toStringAsFixed(2));
    final notesCtrl =
        TextEditingController(text: _receipt.notes ?? '');
    String selectedCategory = _receipt.category;
    DateTime selectedDate = _receipt.date;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Edit Receipt',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                )),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: merchantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merchant Name',
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: totalCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Total Amount (Rs)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: ExpenseCategories.categories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSheet(() => selectedCategory = v);
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setSheet(() => selectedDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_formatDate(selectedDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.note_outlined),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final updated = Receipt(
                      id: _receipt.id,
                      merchantName: merchantCtrl.text.trim(),
                      date: selectedDate,
                      totalAmount:
                          double.parse(totalCtrl.text.trim()),
                      category: selectedCategory,
                      imagePath: _receipt.imagePath,
                      items: _receipt.items,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                      createdAt: _receipt.createdAt,
                      rawOcrText: _receipt.rawOcrText,
                      vendorAddress: _receipt.vendorAddress,
                      receiptTime: _receipt.receiptTime,
                      subtotal: _receipt.subtotal,
                      tax: _receipt.tax,
                      fbrPosFee: _receipt.fbrPosFee,
                      discount: _receipt.discount,
                      cashPaid: _receipt.cashPaid,
                      changeDue: _receipt.changeDue,
                      paymentMethod: _receipt.paymentMethod,
                      fbrInvoiceId: _receipt.fbrInvoiceId,
                      ntn: _receipt.ntn,
                      invoiceNumber: _receipt.invoiceNumber,
                      syncStatus: 'pending_update',
                    );
                    await DatabaseService.instance.updateReceipt(updated);
                    SyncService.instance.pushPending();
                    setState(() => _receipt = updated);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Share ────────────────────────────────────────────────────────────────

  Future<void> _onShare() async {
    final text = ReceiptInfoScreen.buildShareText(_receipt);
    final hasImage = _receipt.imagePath != null &&
        _receipt.imagePath!.isNotEmpty &&
        File(_receipt.imagePath!).existsSync();
    if (hasImage) {
      await Share.shareXFiles(
        [XFile(_receipt.imagePath!)],
        text: text,
        subject: 'Receipt — ${_receipt.merchantName}',
      );
    } else {
      await Share.share(text, subject: 'Receipt — ${_receipt.merchantName}');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: _onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            tooltip: 'Delete',
            onPressed: _onDelete,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _onShare,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(context),
            const SizedBox(height: 20),
            _buildField(context, 'Merchant', _receipt.merchantName,
                Icons.store_outlined),
            _buildField(context, 'Date', _formatDate(_receipt.date),
                Icons.calendar_today_outlined),
            _buildField(
              context,
              'Total',
              _formatRupee(_receipt.totalAmount),
              Icons.payments_outlined,
            ),
            _buildField(context, 'Category', _receipt.category,
                Icons.category_outlined),
            if (_receipt.notes != null && _receipt.notes!.isNotEmpty)
              _buildField(
                  context, 'Notes', _receipt.notes!, Icons.note_outlined),
            if (_receipt.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Items',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              ..._receipt.items.map((item) => _buildItemRow(context, item)),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context) {
    if (_receipt.imagePath != null && _receipt.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_receipt.imagePath!),
          height: 220,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(context),
        ),
      );
    }
    return _buildImagePlaceholder(context);
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text('Receipt image',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildField(
      BuildContext context, String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          )),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(item.name,
            style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
        subtitle: Text(
          'Qty: ${item.quantity} × ${_formatRupee(item.price)}',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Text(_formatRupee(item.totalPrice),
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ),
    );
  }
}
