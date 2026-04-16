import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/receipt_model.dart';
import 'package:uuid/uuid.dart';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  // Process receipt image
  Future<Receipt?> processReceiptImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        return null;
      }

      // Extract receipt information
      final receiptData = _extractReceiptData(recognizedText.text);

      // Create receipt object
      final receipt = Receipt(
        id: const Uuid().v4(),
        merchantName: (receiptData['merchantName'] as String?) ?? 'Unknown Merchant',
        date: (receiptData['date'] as DateTime?) ?? DateTime.now(),
        totalAmount: (receiptData['totalAmount'] as num?)?.toDouble() ?? 0.0,
        category: _categorizeReceipt((receiptData['merchantName'] as String?) ?? ''),
        imagePath: imagePath,
        items: (receiptData['items'] as List<ReceiptItem>?) ?? [],
        notes: null,
        createdAt: DateTime.now(),
      );

      return receipt;
    } catch (e) {
      print('Error processing receipt: $e');
      return null;
    }
  }

  // Extract data from text
  Map<String, dynamic> _extractReceiptData(String text) {
    final lines = text.split('\n');
    
    String? merchantName;
    DateTime? date;
    double? totalAmount;
    List<ReceiptItem> items = [];

    // Extract merchant name (usually first line)
    if (lines.isNotEmpty) {
      merchantName = lines[0].trim();
    }

    // Extract date and total
    for (var line in lines) {
      // Look for date patterns (dd/mm/yyyy, dd-mm-yyyy, etc.)
      final dateMatch = RegExp(r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}').firstMatch(line);
      if (dateMatch != null && date == null) {
        try {
          date = _parseDate(dateMatch.group(0)!);
        } catch (e) {
          // Continue if date parsing fails
        }
      }

      // Look for total amount (Total, Amount, etc.)
      if (line.toLowerCase().contains('total') || 
          line.toLowerCase().contains('amount')) {
        final amountMatch = RegExp(r'[\d,]+\.?\d*').firstMatch(line);
        if (amountMatch != null) {
          totalAmount = double.tryParse(
            amountMatch.group(0)!.replaceAll(',', '')
          );
        }
      }

      // Extract items (simple pattern: name followed by price)
      final itemMatch = RegExp(r'^(.+?)\s+([\d,]+\.?\d*)$').firstMatch(line.trim());
      if (itemMatch != null) {
        final itemName = itemMatch.group(1)?.trim();
        final price = double.tryParse(
          itemMatch.group(2)!.replaceAll(',', '')
        );
        
        if (itemName != null && price != null && price > 0) {
          items.add(ReceiptItem(
            name: itemName,
            quantity: 1,
            price: price,
            totalPrice: price,
          ));
        }
      }
    }

    return {
      'merchantName': merchantName,
      'date': date,
      'totalAmount': totalAmount,
      'items': items,
    };
  }

  // Parse date string
  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split(RegExp(r'[-/]'));
    if (parts.length == 3) {
      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);
      
      // Handle 2-digit year
      if (year < 100) {
        year += 2000;
      }
      
      return DateTime(year, month, day);
    }
    return DateTime.now();
  }

  // Auto-categorize receipt based on merchant name
  String _categorizeReceipt(String merchantName) {
    final merchant = merchantName.toLowerCase();

    // Food & Dining keywords
    if (merchant.contains('restaurant') || merchant.contains('cafe') ||
        merchant.contains('food') || merchant.contains('mcdonald') ||
        merchant.contains('kfc') || merchant.contains('pizza')) {
      return 'Food & Dining';
    }

    // Groceries keywords
    if (merchant.contains('supermarket') || merchant.contains('mart') ||
        merchant.contains('grocery') || merchant.contains('store')) {
      return 'Groceries';
    }

    // Transportation keywords
    if (merchant.contains('fuel') || merchant.contains('petrol') ||
        merchant.contains('gas') || merchant.contains('uber') ||
        merchant.contains('careem')) {
      return 'Transportation';
    }

    // Medicines keywords
    if (merchant.contains('pharmacy') || merchant.contains('medical') ||
        merchant.contains('clinic') || merchant.contains('hospital')) {
      return 'Medicines';
    }

    // Entertainment keywords
    if (merchant.contains('cinema') || merchant.contains('theater') ||
        merchant.contains('movie') || merchant.contains('game')) {
      return 'Entertainment';
    }

    // Bills & Utilities keywords
    if (merchant.contains('electric') || merchant.contains('water') ||
        merchant.contains('gas') || merchant.contains('utility')) {
      return 'Bills & Utilities';
    }

    // Default to Other
    return 'Other';
  }

  // Dispose resources
  void dispose() {
    _textRecognizer.close();
  }
}
// ```

// **What this OCR service does:**
// - Takes receipt image as input
// - Uses Google ML Kit to extract all text
// - Parses text to find: merchant name, date, total amount, items
// - **Auto-categorizes** receipt based on merchant name keywords!
// - Returns a complete `Receipt` object ready to save

// **Note:** This is a basic OCR implementation. Later, you can easily replace this with your Florence-2 model by creating a new service (like `florence_ocr_service.dart`) and swapping it in!

// ---

// ### Save the file: Press `Ctrl + S`

// ---

// ## Quick Check

// You should now have these files:
// ```
// lib/
// ├── models/
// │   └── receipt_model.dart
// ├── services/
// │   ├── database_service.dart
// │   └── ocr_service.dart
// ├── utils/
// │   └── constants.dart
// └── main.dart