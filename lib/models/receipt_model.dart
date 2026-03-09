class Receipt {
  final String id;
  final String merchantName;
  final DateTime date;
  final double totalAmount;
  final String category;
  final String? imagePath; // ? means optional
  final List<ReceiptItem> items;
  final String? notes;
  final DateTime createdAt;

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
  });

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
      items: [], // Will load separately
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class ReceiptItem {
  final String name;
  final int quantity;
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
      quantity: map['quantity'] as int,
      price: (map['price'] as num).toDouble(),
      totalPrice: (map['totalPrice'] as num).toDouble(),
    );
  }
}