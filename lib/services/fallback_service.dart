import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '_secrets.dart';
import 'receipt_parser_service.dart';

class GeminiFallbackService {
  static const _apiKey = Secrets.groqApiKey;
  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';

  static const _systemPrompt = '''
You are a Pakistani receipt data extractor. The text you receive is OCR output from a receipt photo and may contain character recognition errors (e.g. "AlJTH" = "AUTH", "AMOUNI" = "AMOUNT", "Deba 4nterrard" = "Debit Mastercard"). Use fuzzy matching and context to interpret garbled words.

Pakistani receipt rules:
- Numbers use commas: 1,720.00 — return as plain numbers without commas
- Currency appears as PKR, RS, Rs — strip before returning numbers
- Dates may appear as DD/MM/YYYY, MM/DD/YYYY, YYYY/MM/DD, DD-MM-YYYY, DD MMM YYYY — normalize to YYYY-MM-DD
- FBR POS Service Fee (Rs 1) is a government fee — store in fbr_pos_fee, do NOT add to total
- Balance shown as **** on ATM receipts means unavailable — return null

Return ONLY this JSON (no markdown, no explanation):
{
  "category": "one of atm/food/grocery/pos_fuel/pos_store/store",
  "vendor_name": "string or null",
  "vendor_address": "string or null",
  "receipt_date": "YYYY-MM-DD or null",
  "receipt_time": "HH:MM:SS or null",
  "total": "number or null",
  "subtotal": "number or null",
  "tax": "number or null",
  "fbr_pos_fee": "number or null",
  "discount": "number or null",
  "cash_paid": "number or null",
  "change_due": "number or null",
  "payment_method": "string or null",
  "fbr_invoice_id": "string or null",
  "ntn": "string or null",
  "invoice_number": "string or null",
  "items": [{"name": "string", "quantity": "number", "unit_price": "number", "item_total": "number"}],
  "category_data": {}
}

For category_data:
- atm: bank_name, transaction_type, masked_card, amount, balance_after, stan, atm_location
- pos_store/pos_fuel: service_provider, merchant_name, card_type, masked_card, amount, mid, tid, auth_number, rrn, batch_number
- food: order_number, order_type
- grocery: strn, cashier, total_savings
- store: sub_category (pharmacy/clothing/shoes/books/general), strn, cashier
''';

  // Used when the full prompt returns nothing useful — asks only for essentials.
  static const _minimalPrompt = '''
The text below is OCR output from a Pakistani receipt and may have heavy character recognition errors. Do your best to interpret garbled text using context.

Extract ONLY these fields and return a JSON object (no markdown, no explanation):
{
  "category": "one of atm/food/grocery/pos_fuel/pos_store/store",
  "vendor_name": "the merchant or business name, or null",
  "total": "the final amount paid as a plain number, or null",
  "receipt_date": "YYYY-MM-DD or null",
  "payment_method": "cash/debit/credit/card or null",
  "items": [],
  "category_data": {"amount": "same as total if no separate amount field, else null"}
}

Rules: strip PKR/RS/Rs from numbers, strip commas from numbers (1,500 → 1500).
''';

  Future<ParsedReceipt> parse(String ocrText, String category) async {
    // Tier 1: full extraction
    final full = await _callWithRetry(ocrText, category,
        systemPrompt: _systemPrompt, attempt: 1);
    if (!full.extractionFailed) return full;

    // Tier 2: minimal prompt — only fires if tier 1 got nothing useful
    debugPrint('LlmFallback: full prompt got nothing — trying minimal prompt');
    return _callWithRetry(ocrText, category,
        systemPrompt: _minimalPrompt, attempt: 1);
  }

  Future<ParsedReceipt> _callWithRetry(
    String ocrText,
    String category, {
    required String systemPrompt,
    required int attempt,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': ocrText},
              ],
              'temperature': 0,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 429 && attempt == 1) {
        final retrySeconds = _parseRetryDelay(response);
        debugPrint('LlmFallback: rate limited — retrying in ${retrySeconds}s');
        await Future.delayed(Duration(seconds: retrySeconds));
        return _callWithRetry(ocrText, category,
            systemPrompt: systemPrompt, attempt: 2);
      }

      if (response.statusCode != 200) {
        debugPrint('LlmFallback: HTTP ${response.statusCode} — ${response.body}');
        return _failed(category);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (body['choices'] as List?)
          ?.firstOrNull
          ?['message']?['content'] as String?;

      if (text == null || text.trim().isEmpty) {
        debugPrint('LlmFallback: empty response');
        return _failed(category);
      }

      final parsed = _parseJson(text, category);
      _debugLog(parsed);
      return parsed;
    } catch (e) {
      debugPrint('LlmFallback: error — $e');
      return _failed(category);
    }
  }

  // Groq returns retry-after in the header (seconds as string) or in the body.
  static int _parseRetryDelay(http.Response response) {
    final header = response.headers['retry-after'];
    if (header != null) {
      return int.tryParse(header) ?? 10;
    }
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = body['error']?['message'] as String? ?? '';
      final m = RegExp(r'try again in ([\d.]+)s').firstMatch(msg);
      if (m != null) return (double.tryParse(m.group(1)!) ?? 10).ceil();
    } catch (_) {}
    return 10;
  }

  // ─── Debug ────────────────────────────────────────────────────────────────

  static void _debugLog(ParsedReceipt r) {
    debugPrint('─── LlmFallback DEBUG ───');
    debugPrint('Category      : ${r.category}');
    debugPrint('extractionFailed: ${r.extractionFailed}');
    if (r.vendorName != null)    debugPrint('Vendor        : ${r.vendorName}');
    if (r.vendorAddress != null) debugPrint('Address       : ${r.vendorAddress}');
    if (r.receiptDate != null)   debugPrint('Date          : ${r.receiptDate}');
    if (r.receiptTime != null)   debugPrint('Time          : ${r.receiptTime}');
    if (r.invoiceNumber != null) debugPrint('Invoice #     : ${r.invoiceNumber}');
    if (r.paymentMethod != null) debugPrint('Payment       : ${r.paymentMethod}');
    if (r.subtotal != null)      debugPrint('Subtotal      : ${r.subtotal}');
    if (r.tax != null)           debugPrint('Tax           : ${r.tax}');
    if (r.fbrPosFee != null)     debugPrint('FBR POS Fee   : ${r.fbrPosFee}');
    if (r.discount != null)      debugPrint('Discount      : ${r.discount}');
    if (r.total != null)         debugPrint('Total         : ${r.total}');
    if (r.cashPaid != null)      debugPrint('Cash Paid     : ${r.cashPaid}');
    if (r.changeDue != null)     debugPrint('Change Due    : ${r.changeDue}');
    if (r.ntn != null)           debugPrint('NTN           : ${r.ntn}');
    if (r.fbrInvoiceId != null)  debugPrint('FBR Invoice   : ${r.fbrInvoiceId}');
    if (r.items.isNotEmpty) {
      debugPrint('Items (${r.items.length}):');
      for (final item in r.items) {
        debugPrint('  ${item.quantity}x ${item.name} — Rs. ${item.itemTotal}');
      }
    }
    if (r.categoryData.isNotEmpty) {
      debugPrint('Category Data :');
      r.categoryData.forEach((k, v) {
        if (v != null) debugPrint('  $k: $v');
      });
    }
    debugPrint('─────────────────────────');
  }

  // ─── JSON → ParsedReceipt ──────────────────────────────────────────────────

  ParsedReceipt _parseJson(String raw, String fallbackCategory) {
    try {
      final cleaned = raw
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .trim();

      final j = jsonDecode(cleaned) as Map<String, dynamic>;

      final category = (j['category'] as String?)?.trim() ?? fallbackCategory;
      final total = _num(j['total']);
      final amount = _num(j['category_data']?['amount']);

      final items = <ParsedItem>[];
      final rawItems = j['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map<String, dynamic>) {
            final name = item['name'] as String? ?? '';
            final qty = _num(item['quantity']) ?? 1.0;
            final unitPrice = _num(item['unit_price']) ?? 0.0;
            final itemTotal = _num(item['item_total']) ?? 0.0;
            if (name.isNotEmpty && itemTotal > 0) {
              items.add(ParsedItem(
                name: name,
                quantity: qty,
                unitPrice: unitPrice,
                itemTotal: itemTotal,
              ));
            }
          }
        }
      }

      final categoryData = _buildCategoryData(category, j, amount);

      return ParsedReceipt(
        category: category,
        vendorName: j['vendor_name'] as String?,
        vendorAddress: j['vendor_address'] as String?,
        receiptDate: _date(j['receipt_date'] as String?),
        receiptTime: j['receipt_time'] as String?,
        total: total,
        subtotal: _num(j['subtotal']),
        tax: _num(j['tax']),
        fbrPosFee: _num(j['fbr_pos_fee']),
        discount: _num(j['discount']),
        cashPaid: _num(j['cash_paid']),
        changeDue: _num(j['change_due']),
        paymentMethod: j['payment_method'] as String?,
        fbrInvoiceId: j['fbr_invoice_id'] as String?,
        ntn: j['ntn'] as String?,
        invoiceNumber: j['invoice_number'] as String?,
        items: items,
        extractionFailed: (total == null && amount == null && items.isEmpty),
        categoryData: categoryData,
      );
    } catch (e) {
      debugPrint('LlmFallback: JSON parse error — $e');
      return _failed(fallbackCategory);
    }
  }

  Map<String, dynamic> _buildCategoryData(
    String category,
    Map<String, dynamic> j,
    double? amount,
  ) {
    final cd = j['category_data'];
    if (cd is! Map<String, dynamic>) return {};

    switch (category) {
      case 'atm':
        return {
          'bank_name': cd['bank_name'],
          'atm_location': cd['atm_location'],
          'transaction_type': cd['transaction_type'],
          'masked_card': cd['masked_card'],
          'amount': amount ?? _num(cd['amount']),
          'balance_after': _num(cd['balance_after']),
          'stan': cd['stan'],
        };
      case 'pos_store':
      case 'pos_fuel':
        return {
          'service_provider': cd['service_provider'],
          'merchant_name': cd['merchant_name'],
          'card_type': cd['card_type'],
          'masked_card': cd['masked_card'],
          'amount': amount ?? _num(cd['amount']),
          'mid': cd['mid'],
          'tid': cd['tid'],
          'auth_number': cd['auth_number'],
          'rrn': cd['rrn'],
          'batch_number': cd['batch_number'],
          if (category == 'pos_fuel') ...{
            'fuel_product': cd['fuel_product'],
            'fuel_litres': _num(cd['fuel_litres']),
            'fuel_price_per_litre': _num(cd['fuel_price_per_litre']),
          },
        };
      case 'food':
        return {
          'order_number': cd['order_number'],
          'order_type': cd['order_type'],
        };
      case 'grocery':
        return {
          'strn': cd['strn'],
          'cashier': cd['cashier'],
          'total_savings': _num(cd['total_savings']),
        };
      case 'store':
        return {
          'sub_category': cd['sub_category'] ?? 'general',
          'strn': cd['strn'],
          'cashier': cd['cashier'],
        };
      default:
        return Map<String, dynamic>.from(cd);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static ParsedReceipt _failed(String category) => ParsedReceipt(
        category: category,
        extractionFailed: true,
      );

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[PKRpkrRs,\s]'), '');
      return double.tryParse(cleaned);
    }
    return null;
  }

  static DateTime? _date(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
