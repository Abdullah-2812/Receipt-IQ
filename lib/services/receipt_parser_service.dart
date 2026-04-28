import 'package:flutter/foundation.dart';

// ─── Data classes ──────────────────────────────────────────────────────────────

class ParsedItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final double itemTotal;

  const ParsedItem({
    required this.name,
    this.quantity = 1.0,
    required this.unitPrice,
    required this.itemTotal,
  });
}

class ParsedReceipt {
  final String category;
  final String? vendorName;
  final String? vendorAddress;
  final DateTime? receiptDate;
  final String? receiptTime;
  final double? subtotal;
  final double? tax;
  final double? fbrPosFee;
  final double? discount;
  final double? total;
  final double? cashPaid;
  final double? changeDue;
  final String? paymentMethod;
  final String? fbrInvoiceId;
  final String? ntn;
  final String? invoiceNumber;
  final bool extractionFailed;
  final List<ParsedItem> items;
  // Category-specific fields (bank_name, atm_location, service_provider, etc.)
  final Map<String, dynamic> categoryData;

  const ParsedReceipt({
    required this.category,
    this.vendorName,
    this.vendorAddress,
    this.receiptDate,
    this.receiptTime,
    this.subtotal,
    this.tax,
    this.fbrPosFee,
    this.discount,
    this.total,
    this.cashPaid,
    this.changeDue,
    this.paymentMethod,
    this.fbrInvoiceId,
    this.ntn,
    this.invoiceNumber,
    required this.extractionFailed,
    this.items = const [],
    this.categoryData = const {},
  });
}

// ─── Service ───────────────────────────────────────────────────────────────────

class ReceiptParserService {
  static bool debugMode = true;

  static void _debugLog(String category, ParsedReceipt r) {
    if (!debugMode) return;
    final extracted = <String>[];
    final failed = <String>[];
    void chk(String name, Object? val) {
      if (val != null) { extracted.add(name); } else { failed.add(name); }
    }
    chk('vendorName', r.vendorName);
    chk('vendorAddress', r.vendorAddress);
    chk('receiptDate', r.receiptDate);
    chk('receiptTime', r.receiptTime);
    chk('subtotal', r.subtotal);
    chk('tax', r.tax);
    chk('fbrPosFee', r.fbrPosFee);
    chk('discount', r.discount);
    chk('total', r.total);
    chk('cashPaid', r.cashPaid);
    chk('changeDue', r.changeDue);
    chk('paymentMethod', r.paymentMethod);
    chk('fbrInvoiceId', r.fbrInvoiceId);
    chk('ntn', r.ntn);
    chk('invoiceNumber', r.invoiceNumber);
    debugPrint('─── ReceiptParserService DEBUG ───');
    debugPrint('Category       : $category');
    debugPrint('Items parsed   : ${r.items.length}');
    debugPrint('Extracted      : ${extracted.isEmpty ? "(none)" : extracted.join(', ')}');
    debugPrint('Failed (null)  : ${failed.isEmpty ? "(none)" : failed.join(', ')}');
    debugPrint('extractionFailed: ${r.extractionFailed}');
    if (r.categoryData.isNotEmpty) {
      debugPrint('categoryData   : ${r.categoryData}');
    }
    debugPrint('──────────────────────────────────');
  }

  ParsedReceipt parse(String ocrText, String category) {
    try {
      final lines = _splitLines(ocrText);
      final result = switch (category) {
        'atm' => _parseAtm(lines),
        'pos_store' || 'pos_fuel' => _parsePosStore(lines),
        'food' => _parseFood(lines),
        'grocery' => _parseGrocery(lines),
        'store' => _parseStore(lines),
        _ => _parseFood(lines),
      };
      _debugLog(category, result);
      return result;
    } catch (e, st) {
      debugPrint('ReceiptParserService[$category] error: $e\n$st');
      final failed = ParsedReceipt(category: category, extractionFailed: true);
      _debugLog(category, failed);
      return failed;
    }
  }

  // ─── ATM ─────────────────────────────────────────────────────────────────────

  ParsedReceipt _parseAtm(List<String> lines) {
    String? bankName;
    String? atmLocation;
    String? transactionType;
    String? maskedCard;
    double? amount;
    double? balanceAfter;
    String? stan;
    DateTime? receiptDate;
    String? receiptTime;

    final bankRe = RegExp(
      r'bankislami|askari\s*bank|allied\s*bank|united\s*bank|ubl|bank\s*al\s*habib|mcb|'
      r'habib\s*bank|faysal|meezan|hbl|national\s*bank|standard\s*chartered|'
      r'js\s*bank|summit\s*bank|silk\s*bank',
      caseSensitive: false,
    );
    final txnRe = RegExp(
      r'cash\s*withdrawal|withdrawal|funds?\s*transfer|balance\s*inquiry|cash\s*deposit',
      caseSensitive: false,
    );
    final skipNextRe = RegExp(
      r'CARD|AMOUNT|STAN|REF|BALANCE|TRANS|DATE|TIME',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Bank name
      if (bankName == null) {
        if (bankRe.hasMatch(line)) {
          bankName = line.trim();
          if (i + 1 < lines.length) {
            final next = lines[i + 1];
            if (!txnRe.hasMatch(next) &&
                !skipNextRe.hasMatch(next) &&
                _extractDateString(next) == null &&
                next.length > 3) {
              atmLocation = next.trim();
            }
          }
        }
        // "Thank you for using X ATM"
        final tyM = RegExp(
          r'thank\s*you\s*for\s*using\s+(.+?)\s+atm',
          caseSensitive: false,
        ).firstMatch(line);
        if (tyM != null) bankName ??= tyM.group(1)!.trim();
      }

      // Transaction type
      if (transactionType == null) {
        final txM = txnRe.firstMatch(line);
        if (txM != null) {
          transactionType =
              txM.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
        }
        // MCB: "TRANSACTION : Cash Withdrawal"
        final mcbM = RegExp(
          r'TRANSACTION\s*[:\-]\s*(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (mcbM != null) transactionType ??= mcbM.group(1)!.trim().toUpperCase();
      }

      // Date / time — prefer explicit DATE: label, else any date string
      if (receiptDate == null) {
        final ds = _extractDateString(line);
        if (ds != null) receiptDate = _parseDate(ds);
      }
      receiptTime ??= _extractTimeString(line);

      // Card number — line must mention CARD
      if (maskedCard == null &&
          RegExp(r'\bCARD\b', caseSensitive: false).hasMatch(line)) {
        // Partially masked: digits/stars/X with possible spaces
        final m = RegExp(
          r'[\dX*]{4,6}[\s\-*X]{2,8}[\dX*]{2,6}[\s\-*X]{0,4}[\d]{4}',
        ).firstMatch(line);
        if (m != null) {
          maskedCard = _maskCard(m.group(0)!);
        } else {
          // Bank Islami: full unmasked 13-19 digits
          final full = RegExp(r'\b(\d{13,19})\b').firstMatch(line);
          if (full != null) maskedCard = _maskCard(full.group(1)!);
        }
      }

      // Amount — exclude lines that mention BALANCE or AVAILABLE
      if (RegExp(r'\bAMO?UNT\b', caseSensitive: false).hasMatch(line) &&
          !RegExp(r'BALANCE|AVAILABLE', caseSensitive: false).hasMatch(line)) {
        final a = _extractAmountFromLine(line);
        if (a != null) amount = a;
      }

      // Balance — null if value contains asterisks
      if (balanceAfter == null &&
          RegExp(r'BALANCE', caseSensitive: false).hasMatch(line) &&
          !line.contains('*')) {
        balanceAfter = _extractAmountFromLine(line);
      }

      // STAN / Reference / Trace
      stan ??= RegExp(
        r'(?:STAN|TRACE)\s*[:\s]+(\d{4,12})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      stan ??= RegExp(
        r'REF\s*(?:NO)?\s*[:\s]+(\d{6,12})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
    }

    return ParsedReceipt(
      category: 'atm',
      vendorName: bankName,
      receiptDate: receiptDate,
      receiptTime: receiptTime,
      total: amount,
      extractionFailed: amount == null,
      categoryData: {
        'bank_name': bankName,
        'atm_location': atmLocation,
        'transaction_type': transactionType,
        'masked_card': maskedCard,
        'amount': amount,
        'balance_after': balanceAfter,
        'stan': stan,
      },
    );
  }

  // ─── POS STORE / POS FUEL ──────────────────────────────────────────────────

  ParsedReceipt _parsePosStore(List<String> lines) {
    String? serviceProvider;
    String? merchantName;
    String? maskedCard;
    String? cardType;
    double? amount;
    String? mid;
    String? tid;
    String? authNumber;
    String? rrn;
    String? batchNumber;
    String? invoiceNumber;
    DateTime? receiptDate;
    String? receiptTime;
    String? fbrInvoiceId;
    String? ntn;
    // Fuel extras
    String? fuelProduct;
    double? fuelLitres;
    double? fuelPricePerLitre;

    final providerPatterns = <RegExp, String>{
      RegExp(r'paysa', caseSensitive: false): 'Paysa',
      RegExp(r'integrated\s*payment', caseSensitive: false): 'Paysa',
      RegExp(r'meezan\s*bank', caseSensitive: false): 'Meezan Bank',
      RegExp(r'\bHBL\b'): 'HBL',
      RegExp(r'allied\s*bank', caseSensitive: false): 'Allied Bank',
      RegExp(r'bank\s*alfalah|altpay', caseSensitive: false): 'Bank Alfalah',
      RegExp(r'keenu|bank\s*al\s*habib', caseSensitive: false): 'Keenu',
      RegExp(r'opay|faysal\s*bank', caseSensitive: false): 'OPay',
      RegExp(r'\bMCB\b'): 'MCB',
    };

    final noiseRe = RegExp(
      r'powered\s*by|limited|ltd\b|www\.|pvt',
      caseSensitive: false,
    );
    final fuelRe = RegExp(
      r'petroleum|petrol|filling\s*station|PSO|shell|caltex|attock|hascol|total\s*parco',
      caseSensitive: false,
    );

    // Detect service provider from first 5 lines, merchant from lines after
    for (int i = 0; i < lines.length && i < 5 && serviceProvider == null; i++) {
      for (final entry in providerPatterns.entries) {
        if (entry.key.hasMatch(lines[i])) {
          serviceProvider = entry.value;
          for (int j = i + 1; j < lines.length && j <= i + 5; j++) {
            final next = lines[j];
            if (!entry.key.hasMatch(next) &&
                !noiseRe.hasMatch(next) &&
                next.length > 3) {
              // Strip parenthetical suffixes like "(PAYSA)"
              merchantName =
                  next.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
              break;
            }
          }
          break;
        }
      }
    }

    bool isFuel = merchantName != null && fuelRe.hasMatch(merchantName);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (receiptDate == null) {
        final ds = _extractDateString(line);
        if (ds != null) receiptDate = _parseDate(ds);
      }
      receiptTime ??= _extractTimeString(line);

      // Amount — take last occurrence (override each time)
      if (RegExp(
        r'\b(?:TXN|TRANSACTION|TOTAL)?\s*AMOUNT\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line);
        if (a != null) amount = a;
      }

      // Card scheme / type
      if (cardType == null) {
        final m = RegExp(
          r'(visa|mastercard|unionpay|paypak)[\s\w()]*sale',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) cardType = m.group(0)!.trim();
      }

      // Masked card number
      if (maskedCard == null) {
        final m = RegExp(
          r'[\dX*]{4,6}[\s\-*X]{2,10}[\d]{3,4}(?:\s*\([A-Z]{1,2}\)|\s*[TC])?',
        ).firstMatch(line);
        if (m != null) maskedCard = _maskCard(m.group(0)!);
      }

      // Technical fields
      mid ??= RegExp(
        r'\bMID\s*[:\s]+(\w+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      tid ??= RegExp(
        r'\bTID\s*[:\s]+(\w+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      authNumber ??= RegExp(
        r'\bAUTH(?:\s*(?:NO|ID|NUMBER))?\s*[:\s]+(\d{4,8})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      rrn ??= RegExp(
        r'\bRRN\s*[:\s]+(\d{10,14})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      batchNumber ??= RegExp(
        r'\bBATCH\s*(?:NO)?\s*[:\s]+(\d{4,8})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      invoiceNumber ??= RegExp(
        r'\bINVOICE\s*(?:NO)?\s*[:\s]+(\w+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      // FBR
      fbrInvoiceId ??= RegExp(
        r'FBR\s*(?:Invoice|Inv)\s*(?:No|#)?\s*[:\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      // Fuel detection and specifics (AltPay/Shell)
      if (!isFuel && fuelRe.hasMatch(line)) isFuel = true;

      fuelProduct ??= RegExp(
        r'Product\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1)?.trim();

      if (fuelLitres == null) {
        final m = RegExp(
          r'Qty\s*:\s*([\d.]+)\s*Ltr',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) fuelLitres = double.tryParse(m.group(1)!);
      }

      if (fuelPricePerLitre == null) {
        final m = RegExp(
          r'Price\s*:\s*([\d,.]+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) fuelPricePerLitre = _parseAmount(m.group(1));
      }
    }

    return ParsedReceipt(
      category: isFuel ? 'pos_fuel' : 'pos_store',
      vendorName: merchantName,
      receiptDate: receiptDate,
      receiptTime: receiptTime,
      total: amount,
      invoiceNumber: invoiceNumber,
      fbrInvoiceId: fbrInvoiceId,
      ntn: ntn,
      extractionFailed: amount == null,
      categoryData: {
        'service_provider': serviceProvider,
        'merchant_name': merchantName,
        'card_type': cardType,
        'masked_card': maskedCard,
        'amount': amount,
        'mid': mid,
        'tid': tid,
        'auth_number': authNumber,
        'rrn': rrn,
        'batch_number': batchNumber,
        'invoice_number': invoiceNumber,
        if (isFuel) ...{
          'fuel_product': fuelProduct,
          'fuel_litres': fuelLitres,
          'fuel_price_per_litre': fuelPricePerLitre,
        },
      },
    );
  }

  // ─── FOOD / RESTAURANT ───────────────────────────────────────────────────────

  ParsedReceipt _parseFood(List<String> lines) {
    String? vendorName;
    String? vendorAddress;
    DateTime? receiptDate;
    String? receiptTime;
    String? orderNumber;
    String? orderType;
    double? subtotal;
    double? tax;
    double? fbrPosFee;
    double? discount;
    double? total;
    double? cashPaid;
    double? changeDue;
    String? paymentMethod;
    String? fbrInvoiceId;
    String? ntn;
    String? invoiceNumber;
    final items = <ParsedItem>[];

    final noiseRe = RegExp(
      r'welcome|software\s*by|powered\s*by|computer\s*software|www\.|version\s*\d',
      caseSensitive: false,
    );
    final phoneRe = RegExp(r'^[\d\s\-+().]{7,}$');
    final orderDetailRe = RegExp(
      r'invoice|order|receipt|bill|date|time|chq|token|s\.no',
      caseSensitive: false,
    );

    // Vendor name: first meaningful line in first 8 lines
    for (int i = 0; i < lines.length && i < 8; i++) {
      final line = lines[i];
      if (noiseRe.hasMatch(line) || phoneRe.hasMatch(line)) continue;
      vendorName = line.trim();
      // Collect address lines immediately after vendor name
      final addrParts = <String>[];
      for (int j = i + 1; j < lines.length && j < i + 6; j++) {
        final next = lines[j];
        if (phoneRe.hasMatch(next) ||
            orderDetailRe.hasMatch(next) ||
            _isItemHeaderLine(next) ||
            _extractDateString(next) != null) { break; }
        if (next.length > 3 && !noiseRe.hasMatch(next)) {
          addrParts.add(next.trim());
        }
      }
      if (addrParts.isNotEmpty) vendorAddress = addrParts.join(', ');
      break;
    }

    int itemBlockStart = -1;
    int itemBlockEnd = lines.length;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (receiptDate == null) {
        final ds = _extractDateString(line);
        if (ds != null) receiptDate = _parseDate(ds);
      }
      receiptTime ??= _extractTimeString(line);

      // Order number
      orderNumber ??= RegExp(
        r'(?:Order\s*[#No.]+|ORDER\s*(?:NUMBER|NO)\.?|Invoice\s*[#No.]+|'
        r'Receipt\s*(?:No\.?|#)|Bill\s*(?:No\.?|#)|Chq\s*#|CHK|'
        r'Token\s*#|Bill\s*Number\s*:|S\.No\s*:)\s*(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      // Order type
      if (orderType == null) {
        final m = RegExp(
          r'(?:Order\s*Type\s*[:\s]+)?(TAKE[-\s]?AWAY|TAKEAWAY|DINE[-\s]?IN|DELIVERY|EAT[-\s]?(?:OUT|IN))',
          caseSensitive: false,
        ).firstMatch(line);
        orderType = m?.group(1);
      }

      // Item block boundaries
      if (itemBlockStart == -1 && _isItemHeaderLine(line)) {
        itemBlockStart = i + 1;
      }
      if (itemBlockStart != -1 && i > itemBlockStart && _isItemEndLine(line)) {
        if (itemBlockEnd == lines.length) itemBlockEnd = i;
      }

      // Financial fields — always overwrite so we get the LAST occurrence
      if (RegExp(
        r'\b(?:sub[-\s]?total|gross\s+amount|total\s+item\s+amount|'
        r'net\s+bill(?!\s*:?\s*\d)|bill\s+total|total\s+money)\b',
        caseSensitive: false,
      ).hasMatch(line) &&
          !RegExp(r'grand|net\s+total', caseSensitive: false).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) subtotal = a;
      }

      if (RegExp(
        r'\b(?:G\.?S\.?T|VAT(?:/GST)?|sales\s+tax|total\s+tax|total\s+gst|'
        r'tax\s+excl|tax\s*\([\d.]+%\)|tax\s*@)',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) tax = a;
      }

      if (RegExp(
        r'\b(?:discount|less\s*:?\s*discount|total\s+item\s+discount|offers?\s+used)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) discount = a;
      }

      if (RegExp(
        r'\bFBR\s+POS\s+(?:Service\s+)?Fee\b|\bPOS\s+Service\s+Fee\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) fbrPosFee = a;
      }

      if (RegExp(
        r'\b(?:net\s+bill\s*:|net\s+total|net\s+amount|total\s+amount|grand\s+total|'
        r'total\s*\(PKR\)|amount\s+tendered|grand\s+amount)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) total = a;
      }

      if (RegExp(
        r'\b(?:cash\s+received|cash\s*:\s*\d|MOP\s*:\s*cash|payment\s*:\s*cash)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) cashPaid = a;
      }

      if (RegExp(
        r'\bchange\s*(?:due|back|given)?\b|\bbalance\s*:',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) changeDue = a;
      }

      if (paymentMethod == null &&
          RegExp(
            r'\b(?:payment\s+(?:mode|type|method)\s*:|MOP\s*:|mode\s+of\s+payment)\b',
            caseSensitive: false,
          ).hasMatch(line)) {
        final m = RegExp(
          r'(?:payment|MOP|mode)[^:]*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) paymentMethod = m.group(1)!.trim();
      }

      fbrInvoiceId ??= RegExp(
        r'(?:FBR|PRA|KPRA)\s*(?:Invoice|Inv)\s*(?:No|#)?\s*[:\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      ntn ??= RegExp(
        r'(?:P?NTN|PNTN|STRN)\s*[:\-#]?\s*([\d\-]{7,})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      invoiceNumber ??= RegExp(
        r'(?:Invoice|Receipt|Bill)\s*(?:No|#)?\s*[:\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
    }

    if (itemBlockStart != -1) {
      items.addAll(
        _extractItemsFromBlock(lines.sublist(itemBlockStart, itemBlockEnd)),
      );
    }

    return ParsedReceipt(
      category: 'food',
      vendorName: vendorName,
      vendorAddress: vendorAddress,
      receiptDate: receiptDate,
      receiptTime: receiptTime,
      subtotal: subtotal,
      tax: tax,
      fbrPosFee: fbrPosFee,
      discount: discount,
      total: total,
      cashPaid: cashPaid,
      changeDue: changeDue,
      paymentMethod: paymentMethod,
      fbrInvoiceId: fbrInvoiceId,
      ntn: ntn,
      invoiceNumber: invoiceNumber ?? orderNumber,
      items: items,
      extractionFailed: total == null && items.isEmpty,
      categoryData: {
        'order_number': orderNumber,
        'order_type': orderType,
      },
    );
  }

  // ─── GROCERY ─────────────────────────────────────────────────────────────────

  ParsedReceipt _parseGrocery(List<String> lines) {
    String? vendorName;
    DateTime? receiptDate;
    String? receiptTime;
    String? invoiceNumber;
    String? cashier;
    String? paymentMethod;
    String? ntn;
    String? strn;
    double? subtotal;
    double? fbrPosFee;
    double? tax;
    double? grandTotal;
    double? cashPaid;
    double? changeDue;
    String? fbrInvoiceId;
    double? totalSavings;
    final items = <ParsedItem>[];

    final noiseRe = RegExp(
      r'software\s*by|powered\s*by|computer\s*software|www\.',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length && i < 5; i++) {
      if (!noiseRe.hasMatch(lines[i]) && lines[i].length > 2) {
        vendorName = lines[i].trim();
        break;
      }
    }

    int itemBlockStart = -1;
    int itemBlockEnd = lines.length;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (receiptDate == null) {
        final ds = _extractDateString(line);
        if (ds != null) receiptDate = _parseDate(ds);
      }
      receiptTime ??= _extractTimeString(line);

      // NTN: 7 digits hyphen 1 digit
      ntn ??= RegExp(
        r'NTN\s*[#:\s]+(\d{7}-\d)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      // STRN: 9-13 digit sequence
      strn ??= RegExp(
        r'STRN\s*[#:\s/NTN\s]*(\d{9,13})',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      invoiceNumber ??= RegExp(
        r'(?:Invoice\s*(?:No\.?|#)?|INV|Receipt\s*#)\s*[:\s]+(\w+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      cashier ??= RegExp(
        r'(?:Cashier|User\s*ID|Employee)\s*[:\s]+(.+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1)?.trim();

      if (paymentMethod == null) {
        final m = RegExp(
          r'(?:Payment|MOP|Mop)\s*[:\s]+(\S+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) paymentMethod = m.group(1)!.trim();
      }

      // Item block
      if (itemBlockStart == -1 && _isItemHeaderLine(line)) {
        itemBlockStart = i + 1;
      }
      if (itemBlockStart != -1 && i > itemBlockStart && _isItemEndLine(line)) {
        if (itemBlockEnd == lines.length) itemBlockEnd = i;
      }

      // FBR POS fee — Rs 1, never added to subtotal
      if (RegExp(
        r'FBR\s*(?:Pos|POS)\s*(?:Fee|Charges?|Service\s*Fee)',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) fbrPosFee = a;
      }

      if (RegExp(
        r'\b(?:sub[-\s]?total|actual\s*price|items?\s*sold|bill\s*before\s*rounding)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) subtotal = a;
      }

      // GST — take last value (tax summary block at end overrides inline)
      if (RegExp(
        r'\bGST\b|\bsales\s*tax\b|\btax\s*summary\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null && a > 0) tax = a;
      }

      // Grand total — take last occurrence
      if (RegExp(
        r'\b(?:grand\s*total|total\s*bi?ll|net\s*total)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) grandTotal = a;
      }

      if (RegExp(
        r'\bcash\b',
        caseSensitive: false,
      ).hasMatch(line) &&
          !RegExp(
            r'cashier|cash\s*back|change|discount',
            caseSensitive: false,
          ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) cashPaid = a;
      }

      if (RegExp(r'\bchange\b', caseSensitive: false).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) changeDue = a;
      }

      fbrInvoiceId ??= RegExp(
        r'FBR\s*(?:Invoice|Inv|ID)\s*(?:No\.?|#)?\s*[:\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      if (totalSavings == null &&
          RegExp(r'you\s*saved', caseSensitive: false).hasMatch(line)) {
        totalSavings = _extractAmountFromLine(line);
      }
    }

    if (itemBlockStart != -1) {
      items.addAll(
        _extractItemsFromBlock(lines.sublist(itemBlockStart, itemBlockEnd)),
      );
    }

    return ParsedReceipt(
      category: 'grocery',
      vendorName: vendorName,
      receiptDate: receiptDate,
      receiptTime: receiptTime,
      subtotal: subtotal,
      tax: tax,
      fbrPosFee: fbrPosFee,
      total: grandTotal,
      cashPaid: cashPaid,
      changeDue: changeDue,
      paymentMethod: paymentMethod,
      fbrInvoiceId: fbrInvoiceId,
      ntn: ntn,
      invoiceNumber: invoiceNumber,
      items: items,
      extractionFailed: grandTotal == null,
      categoryData: {
        'strn': strn,
        'cashier': cashier,
        'total_savings': totalSavings,
      },
    );
  }

  // ─── STORE / RETAIL ──────────────────────────────────────────────────────────

  ParsedReceipt _parseStore(List<String> lines) {
    String? vendorName;
    String? vendorAddress;
    DateTime? receiptDate;
    String? receiptTime;
    String? invoiceNumber;
    String? cashier;
    String? paymentMethod;
    String? ntn;
    String? strn;
    double? subtotal;
    double? tax;
    double? fbrPosFee;
    double? discount;
    double? total;
    double? cashPaid;
    double? changeDue;
    String? fbrInvoiceId;
    String? subCategory;
    final items = <ParsedItem>[];

    final noiseRe = RegExp(
      r'software\s*by|powered\s*by|computer\s*software|www\.',
      caseSensitive: false,
    );
    final pharmacyRe = RegExp(
      r'drug\s*lic(?:ense)?|chemist|pharmacy|medicine|\btab\b|\bcap\b|\bmg\b|\bml\b',
      caseSensitive: false,
    );
    final clothingRe = RegExp(
      r'khaadi|limelight|diners|sapphire|fashion',
      caseSensitive: false,
    );
    final shoesRe = RegExp(r'bata|servis|\bshoe\b|size\s*:', caseSensitive: false);
    final booksRe = RegExp(r'\bbooks\b|uniform|stationery', caseSensitive: false);

    // Vendor name + address
    for (int i = 0; i < lines.length && i < 5; i++) {
      if (!noiseRe.hasMatch(lines[i]) && lines[i].length > 2) {
        vendorName = lines[i].trim();
        final addrParts = <String>[];
        for (int j = i + 1; j < lines.length && j < i + 4; j++) {
          final next = lines[j];
          if (RegExp(
            r'NTN|STRN|date|invoice|receipt',
            caseSensitive: false,
          ).hasMatch(next) || _isItemHeaderLine(next)) { break; }
          if (next.length > 3) addrParts.add(next.trim());
        }
        if (addrParts.isNotEmpty) vendorAddress = addrParts.join(', ');
        break;
      }
    }

    int itemBlockStart = -1;
    int itemBlockEnd = lines.length;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Sub-category via keyword detection
      if (subCategory == null) {
        if (pharmacyRe.hasMatch(line)) { subCategory = 'pharmacy'; }
        else if (clothingRe.hasMatch(line)) { subCategory = 'clothing'; }
        else if (shoesRe.hasMatch(line)) { subCategory = 'shoes'; }
        else if (booksRe.hasMatch(line)) { subCategory = 'books'; }
      }

      if (receiptDate == null) {
        final ds = _extractDateString(line);
        if (ds != null) receiptDate = _parseDate(ds);
      }
      receiptTime ??= _extractTimeString(line);

      ntn ??= RegExp(
        r'(?:National\s*Tax\s*No\.?|NTN)\s*[#:\s]+(\d[\d\-]+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      strn ??= RegExp(
        r'(?:St\s*Registration\s*No\.?|STN|STRN)\s*[#:\s]+(\w+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      invoiceNumber ??= RegExp(
        r'(?:Receipt\s*No|Invoice|S\.No|Ticket)\s*[:#\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);

      cashier ??= RegExp(
        r'(?:Cashier|Served\s*by|Salesman)\s*[:\s]+(.+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1)?.trim();

      if (itemBlockStart == -1 && _isItemHeaderLine(line)) {
        itemBlockStart = i + 1;
      }
      if (itemBlockStart != -1 && i > itemBlockStart && _isItemEndLine(line)) {
        if (itemBlockEnd == lines.length) itemBlockEnd = i;
      }

      // Financial — last occurrence wins
      if (RegExp(
        r'\b(?:sub[-\s]?total|gross\s+total|value\s+excl|total\s+excl(?:usive)?(?:\s+of\s+(?:tax|GST|VAT))?)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) subtotal = a;
      }

      if (RegExp(
        r'\b(?:sales?\s+tax|G\.?S\.?T|VAT|S\.?Tax|tax\s+amount)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) tax = a;
      }

      if (RegExp(
        r'\bFBR\s+POS\s+(?:Service\s+)?Fee\b|\bPOS\s+Service\s+Fee\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) fbrPosFee = a;
      }

      if (RegExp(
        r'\b(?:discount|less\s*:?\s*discount)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) discount = a;
      }

      // Total — various label forms; last occurrence wins
      if (RegExp(
        r'\b(?:net\s+total|total\s+incl(?:usive)?|grand\s+total|payable|'
        r'net\s+amount|total\s+amount|total\s+inclusive\s+amount|balance\s+after\s+discount)\b|'
        r'^(?:total)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) total = a;
      }

      if (RegExp(
        r'\b(?:cash|received|debit\s+card|credit\s+card|payment\s+received)\b',
        caseSensitive: false,
      ).hasMatch(line) &&
          !RegExp(r'change|cashier|discount|total|net', caseSensitive: false).hasMatch(line)) {
        if (paymentMethod == null) {
          final m = RegExp(
            r'cash|debit\s+card|credit\s+card',
            caseSensitive: false,
          ).firstMatch(line);
          if (m != null) paymentMethod = m.group(0)?.trim();
        }
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) cashPaid ??= a;
      }

      if (RegExp(r'\bchange\b', caseSensitive: false).hasMatch(line)) {
        final a = _extractAmountFromLine(line) ?? _peekNextAmount(lines, i);
        if (a != null) changeDue = a;
      }

      fbrInvoiceId ??= RegExp(
        r'FBR\s*(?:Invoice|Inv)\s*(?:No\.?|#)?\s*[:\s]+(\S+)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
    }

    if (itemBlockStart != -1) {
      items.addAll(
        _extractItemsFromBlock(lines.sublist(itemBlockStart, itemBlockEnd)),
      );
    }

    return ParsedReceipt(
      category: 'store',
      vendorName: vendorName,
      vendorAddress: vendorAddress,
      receiptDate: receiptDate,
      receiptTime: receiptTime,
      subtotal: subtotal,
      tax: tax,
      fbrPosFee: fbrPosFee,
      discount: discount,
      total: total,
      cashPaid: cashPaid,
      changeDue: changeDue,
      paymentMethod: paymentMethod,
      fbrInvoiceId: fbrInvoiceId,
      ntn: ntn,
      invoiceNumber: invoiceNumber,
      items: items,
      extractionFailed: total == null && items.isEmpty,
      categoryData: {
        'sub_category': subCategory ?? 'general',
        'strn': strn,
        'cashier': cashier,
      },
    );
  }

  // ─── Item extraction ─────────────────────────────────────────────────────────

  bool _isItemHeaderLine(String line) {
    // Must have at least one "item-word" AND one "measure-word"
    final hasItemWord = RegExp(
      r'\b(?:item|desc(?:ription)?|product|particular|name|barcode|s[#.]|sr\.?|code|des)\b',
      caseSensitive: false,
    ).hasMatch(line);
    final hasMeasureWord = RegExp(
      r'\b(?:qty|quantity|price|rate|amount|total|wt|weight)\b',
      caseSensitive: false,
    ).hasMatch(line);
    final isStandaloneItems = RegExp(r'^\s*ITEMS\s*$').hasMatch(line);
    return isStandaloneItems || (hasItemWord && hasMeasureWord);
  }

  bool _isItemEndLine(String line) {
    return RegExp(
      r'^\s*(?:sub[-\s]?total|gross\s+amount|total\s+money|net\s+amount|'
      r'bill\s+total|total\s+num|total\s+items?|no\.?\s+of\s+items?)',
      caseSensitive: false,
    ).hasMatch(line);
  }

  List<ParsedItem> _extractItemsFromBlock(List<String> lines) {
    final result = <ParsedItem>[];
    ParsedItem? pending; // holds an item that may need a second line for price

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^[-=*_.]{3,}$').hasMatch(line)) continue; // separator

      // Dominos: "2x Chicken Supreme  PKR 890"
      final domiM = RegExp(
        r'^(\d+)[xX]\s+(.+?)\s+(?:PKR\.?\s*)?([\d,]+(?:\.\d+)?)\s*$',
      ).firstMatch(line);
      if (domiM != null) {
        if (pending != null) { result.add(pending); pending = null; }
        final qty = double.tryParse(domiM.group(1)!) ?? 1.0;
        final name = domiM.group(2)!.trim();
        final tot = _parseAmount(domiM.group(3)!) ?? 0.0;
        if (name.isNotEmpty && tot > 0) {
          result.add(ParsedItem(
            name: name,
            quantity: qty,
            unitPrice: qty > 0 ? tot / qty : tot,
            itemTotal: tot,
          ));
        }
        continue;
      }

      final item = _parseItemLine(line);
      if (item != null) {
        if (pending != null) result.add(pending);
        pending = item;
      } else if (pending != null) {
        // Possible price-continuation line (two-line item format)
        final nums = RegExp(r'[\d,]+(?:\.\d+)?')
            .allMatches(line)
            .map((m) => _parseAmount(m.group(0)!))
            .where((v) => v != null && v > 0)
            .cast<double>()
            .toList();
        if (nums.isNotEmpty && nums.last > 0) {
          result.add(ParsedItem(
            name: pending.name,
            quantity: pending.quantity,
            unitPrice: nums.length >= 2 ? nums[nums.length - 2] : nums.last,
            itemTotal: nums.last,
          ));
          pending = null;
        } else {
          result.add(pending);
          pending = null;
        }
      }
    }
    if (pending != null) result.add(pending);
    return result;
  }

  ParsedItem? _parseItemLine(String line) {
    if (line.length < 3) return null;
    if (RegExp(r'^[-=*.]{3,}$').hasMatch(line)) return null;

    // Khaadi / branded clothing item codes: "DD-DD-XXXXX VARIANT QTY PRICE DISC TOTAL"
    if (RegExp(r'^\d{2}-\d{2}-').hasMatch(line)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      final amounts = <double>[];
      int nameEnd = parts.length;
      for (int j = parts.length - 1; j >= 0; j--) {
        final a = _parseAmount(parts[j]);
        if (a != null) {
          amounts.insert(0, a);
          nameEnd = j;
        } else {
          break;
        }
      }
      if (amounts.isNotEmpty && amounts.last > 0 && nameEnd > 0) {
        final name = parts.sublist(0, nameEnd).join(' ').trim();
        final total = amounts.last;
        double qty = 1.0;
        double unitPrice = total;
        if (amounts.length >= 4) {
          qty = amounts[0] < 100 ? amounts[0] : 1.0;
          unitPrice = amounts[1];
        } else if (amounts.length == 3) {
          qty = amounts[0] < 100 ? amounts[0] : 1.0;
          unitPrice = amounts[1];
        } else if (amounts.length == 2) {
          unitPrice = amounts[0];
        }
        if (name.isNotEmpty) {
          return ParsedItem(name: name, quantity: qty, unitPrice: unitPrice, itemTotal: total);
        }
      }
    }

    // Strip currency prefixes before column-splitting
    final cleaned = line
        .replaceAll(RegExp(r'PKR\.?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bRS\.?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bRs\.?\s*', caseSensitive: false), '');

    // Split on 2+ spaces (Pakistani receipt column delimiter)
    final cols =
        cleaned.split(RegExp(r'\s{2,}')).where((c) => c.trim().isNotEmpty).toList();
    if (cols.isEmpty) return null;

    // Walk from right: collect trailing numeric columns
    final amounts = <double>[];
    int nameEndIdx = cols.length;
    for (int i = cols.length - 1; i >= 0; i--) {
      final a = _parseAmount(cols[i].trim());
      if (a != null) {
        amounts.insert(0, a);
        nameEndIdx = i;
      } else {
        break;
      }
    }

    if (amounts.isEmpty) return null;

    // Name is everything before the numeric columns
    var name = cols.sublist(0, nameEndIdx).join(' ').trim();

    // Strip leading qty-prefix (King Mango: "1.00  item_name  600  600.00")
    name = name.replaceFirst(RegExp(r'^\d+(?:\.\d+)?\s+'), '').trim();

    // Name must contain at least one letter
    if (name.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(name)) return null;

    final total = amounts.last;
    if (total <= 0) return null;

    double qty = 1.0;
    double unitPrice = total;

    if (amounts.length >= 3) {
      // Try [qty, unitPrice, total] ordering
      final candidateQty = amounts[0];
      final candidatePrice = amounts[1];
      if ((candidateQty * candidatePrice - total).abs() <= total * 0.02 + 1.0) {
        qty = candidateQty;
        unitPrice = candidatePrice;
      } else {
        unitPrice = amounts[amounts.length - 2];
      }
    } else if (amounts.length == 2) {
      unitPrice = amounts[0];
      // amounts[0] might be qty if it's a small integer
      if (amounts[0] < 100 && amounts[0] == amounts[0].roundToDouble()) {
        qty = amounts[0];
        // unit price unknown from 2 numbers alone — best-effort: total
        unitPrice = total;
      }
    }

    return ParsedItem(name: name, quantity: qty, unitPrice: unitPrice, itemTotal: total);
  }

  // ─── Static helpers ───────────────────────────────────────────────────────────

  static List<String> _splitLines(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.length >= 2)
      .toList();

  // Strip Pakistani currency prefixes and commas, return first parseable number
  static double? _parseAmount(String? text) {
    if (text == null || text.isEmpty) return null;
    final s = text
        .replaceAll(RegExp(r'PKR\.?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bRS\.?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bRs\.?\s*', caseSensitive: false), '')
        .replaceAll(',', '');
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(s);
    return m != null ? double.tryParse(m.group(0)!) : null;
  }

  // If a label line has no inline amount, peek at the next line for a standalone number.
  // Pakistani receipts often put label on one line and value on the next.
  static double? _peekNextAmount(List<String> lines, int i) {
    if (i + 1 >= lines.length) return null;
    final next = lines[i + 1]
        .replaceAll(RegExp(r'PKR\.?\s*|Rs\.?\s*|RS\.?\s*', caseSensitive: false), '')
        .trim();
    if (RegExp(r'^[\d,]+(?:\.\d+)?$').hasMatch(next)) {
      return double.tryParse(next.replaceAll(',', ''));
    }
    return null;
  }

  // Extract the last number from a line (totals are usually at line end)
  static double? _extractAmountFromLine(String line) {
    final cleaned = line
        .replaceAll(RegExp(r'PKR\.?\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\bRS\.?\s*', caseSensitive: false), ' ')
        .replaceAll(',', '');
    final matches = RegExp(r'\d+(?:\.\d+)?').allMatches(cleaned).toList();
    if (matches.isEmpty) return null;
    return double.tryParse(matches.last.group(0)!);
  }

  // Return the first date-like substring found in a line, or null
  static String? _extractDateString(String line) {
    // YYYY[-/.]MM[-/.]DD
    var m = RegExp(r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}').firstMatch(line);
    if (m != null) return m.group(0)!;
    // DD/MM/YYYY or DD-MM-YYYY (4-digit year)
    m = RegExp(r'\d{1,2}[/\-]\d{1,2}[/\-]\d{4}').firstMatch(line);
    if (m != null) return m.group(0)!;
    // DD/MM/YY or DD-MM-YY (2-digit year)
    m = RegExp(r'\d{1,2}[/\-]\d{1,2}[/\-]\d{2}(?!\d)').firstMatch(line);
    if (m != null) return m.group(0)!;
    // D[-\s]MMM[-\s]YY[YY] e.g. "21-Oct-25", "4 Jul-25", "23Dec25"
    m = RegExp(
      r'\d{1,2}[-\s]?(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[-\s]?\d{2,4}',
      caseSensitive: false,
    ).firstMatch(line);
    if (m != null) return m.group(0)!;
    // "Tue Nov 19 2024" — weekday-first long date
    m = RegExp(
      r'(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{4}',
      caseSensitive: false,
    ).firstMatch(line);
    if (m != null) return m.group(0)!;
    // "Sunday, December 7 2025" (Date: prefix stripped later in _parseDate)
    m = RegExp(
      r'(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+'
      r'(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}',
      caseSensitive: false,
    ).firstMatch(line);
    if (m != null) return m.group(0)!;
    return null;
  }

  static DateTime? _parseDate(String text) {
    // Strip "Date:" prefix and apostrophes
    text = text
        .trim()
        .replaceAll(RegExp(r'Date\s*[:\s]+', caseSensitive: false), '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r',\s*'), ' ');

    // Remove leading day-of-week
    text = text.replaceAll(
      RegExp(
        r'^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|'
        r'Mon|Tue|Wed|Thu|Fri|Sat|Sun)[,\s]+',
        caseSensitive: false,
      ),
      '',
    );

    // Remove ordinal suffixes: 7th → 7
    text = text.replaceAllMapped(
      RegExp(r'(\d+)(?:st|nd|rd|th)\b'),
      (m) => m.group(1)!,
    );

    final months = <String, int>{
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
      'june': 6, 'july': 7, 'august': 8, 'september': 9,
      'october': 10, 'november': 11, 'december': 12,
    };

    String pad(int n) => n.toString().padLeft(2, '0');
    int fullYear(int y) => y < 100 ? y + 2000 : y;

    // YYYY[-/.]MM[-/.]DD
    var m = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
    if (m != null) {
      return DateTime.tryParse(
        '${m.group(1)}-${pad(int.parse(m.group(2)!))}-${pad(int.parse(m.group(3)!))}',
      );
    }

    // DD[-/]MM[-/]YYYY or DD[-/]MM[-/]YY
    m = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})').firstMatch(text);
    if (m != null) {
      int d = int.parse(m.group(1)!);
      int mo = int.parse(m.group(2)!);
      final y = fullYear(int.parse(m.group(3)!));
      // If month > 12 but day ≤ 12, this is MM/DD format
      if (mo > 12 && d <= 12) { final t = mo; mo = d; d = t; }
      if (d <= 31 && mo <= 12) {
        return DateTime.tryParse('$y-${pad(mo)}-${pad(d)}');
      }
    }

    // D[-\s]?MMM[-\s]?YY[YY] e.g. "21-Oct-25", "24-Dec-25", "4 Jul-25", "23Dec25"
    m = RegExp(
      r'(\d{1,2})[-\s]?([A-Za-z]{3,9})[-\s]?(\d{2,4})',
    ).firstMatch(text);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final key = m.group(2)!.toLowerCase();
      final mo = months[key] ?? months[key.substring(0, 3)];
      final y = fullYear(int.parse(m.group(3)!));
      if (mo != null && d <= 31) {
        return DateTime.tryParse('$y-${pad(mo)}-${pad(d)}');
      }
    }

    // "November 19 2024" or "Nov 19 2024"
    m = RegExp(r'([A-Za-z]{3,9})\s+(\d{1,2})\s+(\d{4})').firstMatch(text);
    if (m != null) {
      final key = m.group(1)!.toLowerCase();
      final mo = months[key] ?? months[key.length >= 3 ? key.substring(0, 3) : key];
      final d = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      if (mo != null) return DateTime.tryParse('$y-${pad(mo)}-${pad(d)}');
    }

    return null;
  }

  // Extract HH:MM[:SS][ AM/PM] from a line, returns null if none found
  static String? _extractTimeString(String line) {
    final m = RegExp(
      r'(?:TIME\s*[:\s]+)?(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)',
      caseSensitive: false,
    ).firstMatch(line);
    return m?.group(1)?.trim();
  }

  // Normalize any card number variant to ************XXXX (last 4 digits only)
  static String _maskCard(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 4) return '************????';
    return '************${digits.substring(digits.length - 4)}';
  }
}
