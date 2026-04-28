import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import 'receipt_info_screen.dart';

class ReceiptsListScreen extends StatefulWidget {
  const ReceiptsListScreen({super.key});

  @override
  State<ReceiptsListScreen> createState() => _ReceiptsListScreenState();
}

class _ReceiptsListScreenState extends State<ReceiptsListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  List<Receipt> _receipts = [];
  bool _loading = true;

  static const String _allCategory = 'All';
  static final List<String> _filterCategories = [
    _allCategory,
    ...ExpenseCategories.categories,
  ];

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
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    await SyncService.instance.waitForFirstSync();
    await DatabaseService.instance.seedIfEmpty();
    final receipts = await DatabaseService.instance.getAllReceipts();
    if (mounted) setState(() { _receipts = receipts; _loading = false; });
  }

  Future<void> _deleteReceipt(Receipt receipt) async {
    final index = _receipts.indexWhere((r) => r.id == receipt.id);

    setState(() => _receipts.removeWhere((r) => r.id == receipt.id));
    SyncService.instance.deleteFromServer(receipt.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${receipt.merchantName} deleted'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed,
          persist: false,
          action: SnackBarAction(
            label: 'Restore',
            onPressed: () async {
              // Re-insert locally with local_only so pushPending picks it up
              final restored = Receipt(
                id: receipt.id,
                merchantName: receipt.merchantName,
                date: receipt.date,
                totalAmount: receipt.totalAmount,
                category: receipt.category,
                imagePath: receipt.imagePath,
                items: receipt.items,
                notes: receipt.notes,
                createdAt: receipt.createdAt,
                rawOcrText: receipt.rawOcrText,
                vendorAddress: receipt.vendorAddress,
                receiptTime: receipt.receiptTime,
                subtotal: receipt.subtotal,
                tax: receipt.tax,
                fbrPosFee: receipt.fbrPosFee,
                discount: receipt.discount,
                cashPaid: receipt.cashPaid,
                changeDue: receipt.changeDue,
                paymentMethod: receipt.paymentMethod,
                fbrInvoiceId: receipt.fbrInvoiceId,
                ntn: receipt.ntn,
                invoiceNumber: receipt.invoiceNumber,
                syncStatus: 'local_only',
                categorySpecificData: receipt.categorySpecificData,
              );
              await DatabaseService.instance.insertReceipt(restored);
              SyncService.instance.pushPending();
              if (mounted) {
                setState(() {
                  final insertAt = index.clamp(0, _receipts.length);
                  _receipts.insert(insertAt, restored);
                });
              }
            },
          ),
        ),
      );
  }

  Future<void> _shareReceipt(Receipt receipt) async {
    final text = ReceiptInfoScreen.buildShareText(receipt);
    final hasImage = receipt.imagePath != null &&
        receipt.imagePath!.isNotEmpty &&
        File(receipt.imagePath!).existsSync();
    if (hasImage) {
      await Share.shareXFiles(
        [XFile(receipt.imagePath!)],
        text: text,
        subject: 'Receipt — ${receipt.merchantName}',
      );
    } else {
      await Share.share(text, subject: 'Receipt — ${receipt.merchantName}');
    }
  }

  List<Receipt> get _filtered => _receipts.where((r) {
        final matchCategory = _selectedCategory == _allCategory ||
            r.category == _selectedCategory;
        final matchSearch = _searchQuery.isEmpty ||
            r.merchantName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            r.category.toLowerCase().contains(_searchQuery.toLowerCase());
        return matchCategory && matchSearch;
      }).toList();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final receipts = _filtered;
    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryFilterChips(),
        Expanded(
          child: receipts.isEmpty
              ? _buildEmptyState(context)
              : RefreshIndicator(
                  onRefresh: _loadReceipts,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: receipts.length,
                    itemBuilder: (context, index) =>
                        _buildReceiptCard(context, receipts[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by merchant or category…',
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.textHint),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.textHint),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildCategoryFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _filterCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _filterCategories[i];
          final selected = _selectedCategory == cat;
          return FilterChip(
            label: Text(cat, style: const TextStyle(fontSize: 12)),
            selected: selected,
            onSelected: (_) => setState(() => _selectedCategory = cat),
            selectedColor: AppColors.primary.withOpacity(0.15),
            checkmarkColor: AppColors.primary,
            labelStyle: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          );
        },
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Receipt receipt) {
    final color = ExpenseCategories.categoryColors[receipt.category] ??
        AppColors.textHint;
    final icon = ExpenseCategories.categoryIcons[receipt.category] ??
        Icons.receipt_long;

    return Dismissible(
      key: ValueKey(receipt.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      onDismissed: (_) => _deleteReceipt(receipt),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            receipt.merchantName,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          subtitle: Text(
            '${_formatDate(receipt.date)} · ${receipt.category}',
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatRupee(receipt.totalAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              GestureDetector(
                onTap: () => _shareReceipt(receipt),
                child: const Icon(Icons.share_outlined,
                    size: 18, color: AppColors.textHint),
              ),
            ],
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReceiptInfoScreen(receipt: receipt),
              ),
            );
            // Reload in case the user edited or deleted from the detail screen
            _loadReceipts();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasFilter =
        _searchQuery.isNotEmpty || _selectedCategory != _allCategory;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilter ? Icons.filter_list_off : Icons.receipt_long,
              size: 80,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 24),
            Text(
              hasFilter ? 'No receipts match your filter' : 'No receipts yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try a different search term or category'
                  : 'Use "Scan Receipt" to add your first receipt',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedCategory = _allCategory;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
