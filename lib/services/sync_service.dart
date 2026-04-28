import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt_model.dart';
import '../utils/constants.dart';
import 'database_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  static const String _lastSyncKey = 'last_synced_at';
  static const String _lastUidKey = 'last_user_uid';

  // Gate that opens once the first handleLogin's fullSync has finished.
  // _loadReceipts awaits this so seedIfEmpty doesn't race with pullDelta.
  Completer<void>? _firstSyncCompleter;

  Future<void> waitForFirstSync() =>
      _firstSyncCompleter?.future ?? Future.value();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // ── Auth header ───────────────────────────────────────────────────────────

  Future<Options> _authHeader() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return Options();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ── Last sync timestamp ───────────────────────────────────────────────────

  Future<String?> _getLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  Future<void> _saveLastSyncedAt(String serverTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, serverTime);
  }

  Future<void> clearLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
  }

  // ── UID-aware login ───────────────────────────────────────────────────────
  // If the same user logs back in: keep SQLite, do delta pull. Fast.
  // If a different user logs in (or first ever login): wipe SQLite, clear
  // last_synced_at, do full pull. Safe.

  Future<void> handleLogin(String uid) async {
    _firstSyncCompleter = Completer<void>();
    final completer = _firstSyncCompleter!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUid = prefs.getString(_lastUidKey);
      if (lastUid != uid) {
        await DatabaseService.instance.wipeAllReceipts();
        await prefs.remove(_lastSyncKey);
        await prefs.setString(_lastUidKey, uid);
      }
      await fullSync();
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  // ── Push pending local receipts to server ─────────────────────────────────

  Future<void> pushPending() async {
    final all = await DatabaseService.instance.getAllReceipts(includeDeleted: true);

    // Send pending deletes first
    final pendingDeletes = all.where((r) => r.syncStatus == 'pending_delete');
    for (final r in pendingDeletes) {
      try {
        await _dio.delete('/receipts/${r.id}', options: await _authHeader());
        await DatabaseService.instance.deleteReceipt(r.id);
      } on DioException catch (e) {
        print('[SYNC] pending delete failed for ${r.id}: ${e.message}');
      }
    }

    final pending = all
        .where((r) =>
            r.syncStatus == 'local_only' || r.syncStatus == 'pending_update')
        .toList();

    if (pending.isEmpty) return;

    try {
      final response = await _dio.post(
        '/receipts/sync',
        data: {'receipts': pending.map(_receiptToMap).toList()},
        options: await _authHeader(),
      );

      final serverTime = response.data['server_time'] as String?;

      for (final r in pending) {
        await DatabaseService.instance.updateReceipt(
          _withSyncStatus(r, 'synced'),
        );
      }

      if (serverTime != null) await _saveLastSyncedAt(serverTime);
    } on DioException catch (e) {
      print('[SYNC] pushPending failed: ${e.message}');
    }
  }

  // ── Delta pull: only fetch what changed since last sync ───────────────────

  Future<void> pullDelta() async {
    final lastSync = await _getLastSyncedAt();

    try {
      final response = await _dio.get(
        '/receipts',
        queryParameters: lastSync != null ? {'since': lastSync} : null,
        options: await _authHeader(),
      );

      final List<dynamic> serverReceipts = response.data;
      final db = DatabaseService.instance;

      for (final r in serverReceipts) {
        final map = r as Map<String, dynamic>;

        // Soft-deleted on server → remove locally
        if (map['deleted_at'] != null) {
          await db.deleteReceipt(map['id'] as String);
          continue;
        }

        await db.insertReceipt(_mapToReceipt(map));
      }

      // Save current time as last synced
      await _saveLastSyncedAt(DateTime.now().toUtc().toIso8601String());
    } on DioException catch (e) {
      print('[SYNC] pullDelta failed: ${e.message}');
    }
  }

  // ── Full sync: push first, then delta pull ────────────────────────────────

  Future<void> fullSync() async {
    await pushPending();
    await pullDelta();
  }

  // ── Analytics ─────────────────────────────────────────────────────────────
  // GET /analytics/summary returns total_spending, receipt_count,
  // by_category (sorted DESC by total), by_month (last 6 months,
  // months with no receipts are omitted — caller should zero-fill).

  Future<Map<String, dynamic>> fetchAnalyticsSummary() async {
    final response = await _dio.get(
      '/analytics/summary',
      options: await _authHeader(),
    );
    return response.data as Map<String, dynamic>;
  }

  // ── Soft delete on server ─────────────────────────────────────────────────
  // Marks pending_delete in SQLite first so it survives app close,
  // then immediately attempts the server call.

  Future<void> deleteFromServer(String receiptId) async {
    final all = await DatabaseService.instance.getAllReceipts(includeDeleted: true);
    final receipt = all.where((r) => r.id == receiptId).firstOrNull;

    // Mark pending_delete so next sync retries if this call fails
    if (receipt != null) {
      await DatabaseService.instance.updateReceipt(
        _withSyncStatus(receipt, 'pending_delete'),
      );
    }

    try {
      await _dio.delete(
        '/receipts/$receiptId',
        options: await _authHeader(),
      );
      // Server confirmed — remove from local DB completely
      await DatabaseService.instance.deleteReceipt(receiptId);
    } on DioException catch (e) {
      print('[SYNC] delete failed, will retry on next sync: ${e.message}');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Receipt _withSyncStatus(Receipt r, String status) => Receipt(
        id: r.id,
        merchantName: r.merchantName,
        date: r.date,
        totalAmount: r.totalAmount,
        category: r.category,
        imagePath: r.imagePath,
        items: r.items,
        notes: r.notes,
        createdAt: r.createdAt,
        rawOcrText: r.rawOcrText,
        vendorAddress: r.vendorAddress,
        receiptTime: r.receiptTime,
        subtotal: r.subtotal,
        tax: r.tax,
        fbrPosFee: r.fbrPosFee,
        discount: r.discount,
        cashPaid: r.cashPaid,
        changeDue: r.changeDue,
        paymentMethod: r.paymentMethod,
        fbrInvoiceId: r.fbrInvoiceId,
        ntn: r.ntn,
        invoiceNumber: r.invoiceNumber,
        syncStatus: status,
        categorySpecificData: r.categorySpecificData,
      );

  Map<String, dynamic> _receiptToMap(Receipt r) => {
        'id': r.id,
        'merchant_name': r.merchantName,
        'date': r.date.toIso8601String(),
        'total_amount': r.totalAmount,
        'category': r.category,
        'image_path': r.imagePath,
        'notes': r.notes,
        'created_at': r.createdAt.toIso8601String(),
        'raw_ocr_text': r.rawOcrText,
        'vendor_address': r.vendorAddress,
        'receipt_time': r.receiptTime,
        'subtotal': r.subtotal,
        'tax': r.tax,
        'fbr_pos_fee': r.fbrPosFee,
        'discount': r.discount,
        'cash_paid': r.cashPaid,
        'change_due': r.changeDue,
        'payment_method': r.paymentMethod,
        'fbr_invoice_id': r.fbrInvoiceId,
        'ntn': r.ntn,
        'invoice_number': r.invoiceNumber,
        'category_data': r.categorySpecificData?.toString(),
        'items': r.items
            .map((i) => {
                  'name': i.name,
                  'quantity': i.quantity,
                  'price': i.price,
                  'totalPrice': i.totalPrice,
                })
            .toList(),
      };

  Receipt _mapToReceipt(Map<String, dynamic> m) => Receipt(
        id: m['id'] as String,
        merchantName: m['merchant_name'] as String,
        date: DateTime.parse(m['date'] as String),
        totalAmount: (m['total_amount'] as num).toDouble(),
        category: m['category'] as String,
        imagePath: m['image_path'] as String?,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        rawOcrText: m['raw_ocr_text'] as String?,
        vendorAddress: m['vendor_address'] as String?,
        receiptTime: m['receipt_time'] as String?,
        subtotal: (m['subtotal'] as num?)?.toDouble(),
        tax: (m['tax'] as num?)?.toDouble(),
        fbrPosFee: (m['fbr_pos_fee'] as num?)?.toDouble(),
        discount: (m['discount'] as num?)?.toDouble(),
        cashPaid: (m['cash_paid'] as num?)?.toDouble(),
        changeDue: (m['change_due'] as num?)?.toDouble(),
        paymentMethod: m['payment_method'] as String?,
        fbrInvoiceId: m['fbr_invoice_id'] as String?,
        ntn: m['ntn'] as String?,
        invoiceNumber: m['invoice_number'] as String?,
        syncStatus: 'synced',
        items: (m['items'] as List? ?? [])
            .map((i) => ReceiptItem(
                  name: i['name'] as String,
                  quantity: (i['quantity'] as num).toDouble(),
                  price: (i['price'] as num).toDouble(),
                  totalPrice: (i['total_price'] as num).toDouble(),
                ))
            .toList(),
      );
}
