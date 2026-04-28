import 'dart:convert';

class Receipt {
  final String id;
  final String merchantName;
  final DateTime date;
  final double totalAmount;
  final String category;
  final String? imagePath;
  final List<ReceiptItem> items;
  final String? notes;
  final DateTime createdAt;

  // Extended fields for Pakistani receipts
  final String? rawOcrText;
  final String? vendorAddress;
  final String? receiptTime;
  final double? subtotal;
  final double? tax;
  final double? fbrPosFee;
  final double? discount;
  final double? cashPaid;
  final double? changeDue;
  final String? paymentMethod;
  final String? fbrInvoiceId;
  final String? ntn;
  final String? invoiceNumber;
  final String? syncStatus;
  final Map<String, dynamic>? categorySpecificData;

  Receipt({
    required this.id,
    required this.merchantName,
    required this.date,
    required this.totalAmount,
    required this.category,
    this.imagePath,
    required this.items,
    this.notes,
    required this.createdAt,
    this.rawOcrText,
    this.vendorAddress,
    this.receiptTime,
    this.subtotal,
    this.tax,
    this.fbrPosFee,
    this.discount,
    this.cashPaid,
    this.changeDue,
    this.paymentMethod,
    this.fbrInvoiceId,
    this.ntn,
    this.invoiceNumber,
    this.syncStatus = 'local_only',
    this.categorySpecificData,
  });

  // Only the 8 columns that exist in the current DB schema.
  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchantName': merchantName,
        'date': date.toIso8601String(),
        'totalAmount': totalAmount,
        'category': category,
        'imagePath': imagePath,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  // Convert Receipt to Map (for database storage)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchantName': merchantName,
      'date': date.toIso8601String(),
      'totalAmount': totalAmount,
      'category': category,
      'imagePath': imagePath,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'rawOcrText': rawOcrText,
      'vendorAddress': vendorAddress,
      'receiptTime': receiptTime,
      'subtotal': subtotal,
      'tax': tax,
      'fbrPosFee': fbrPosFee,
      'discount': discount,
      'cashPaid': cashPaid,
      'changeDue': changeDue,
      'paymentMethod': paymentMethod,
      'fbrInvoiceId': fbrInvoiceId,
      'ntn': ntn,
      'invoiceNumber': invoiceNumber,
      'syncStatus': syncStatus,
      'categorySpecificData':
          categorySpecificData != null ? jsonEncode(categorySpecificData) : null,
    };
  }

  // Create Receipt from Map (when reading from database)
  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: map['id'] as String,
      merchantName: map['merchantName'] as String,
      date: DateTime.parse(map['date'] as String),
      totalAmount: (map['totalAmount'] as num).toDouble(),
      category: map['category'] as String,
      imagePath: map['imagePath'] as String?,
      items: [], // Loaded separately by DatabaseService
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      rawOcrText: map['rawOcrText'] as String?,
      vendorAddress: map['vendorAddress'] as String?,
      receiptTime: map['receiptTime'] as String?,
      subtotal: (map['subtotal'] as num?)?.toDouble(),
      tax: (map['tax'] as num?)?.toDouble(),
      fbrPosFee: (map['fbrPosFee'] as num?)?.toDouble(),
      discount: (map['discount'] as num?)?.toDouble(),
      cashPaid: (map['cashPaid'] as num?)?.toDouble(),
      changeDue: (map['changeDue'] as num?)?.toDouble(),
      paymentMethod: map['paymentMethod'] as String?,
      fbrInvoiceId: map['fbrInvoiceId'] as String?,
      ntn: map['ntn'] as String?,
      invoiceNumber: map['invoiceNumber'] as String?,
      syncStatus: (map['syncStatus'] as String?) ?? 'local_only',
      categorySpecificData: map['categorySpecificData'] != null
          ? Map<String, dynamic>.from(
              jsonDecode(map['categorySpecificData'] as String) as Map)
          : null,
    );
  }
}

class ReceiptItem {
  final String name;
  final double quantity; // double to support weight-based items (e.g. 0.135 kg)
  final double price;
  final double totalPrice;

  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.totalPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'price': price,
      'totalPrice': totalPrice,
    };
  }

  factory ReceiptItem.fromMap(Map<String, dynamic> map) {
    return ReceiptItem(
      name: map['name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      price: (map['price'] as num).toDouble(),
      totalPrice: (map['totalPrice'] as num).toDouble(),
    );
  }
}