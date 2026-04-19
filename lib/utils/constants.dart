import 'package:flutter/material.dart';

// App Information
class AppConstants {
  static const String appName = 'Receipt IQ';
  static const String appVersion = '1.0.0';
}

// App Colors
class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF2196F3); // Blue
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF64B5F6);
  
  // Accent Colors
  static const Color accent = Color(0xFF4CAF50); // Green
  static const Color accentDark = Color(0xFF388E3C);
  static const Color accentLight = Color(0xFF81C784);
  
  // Background Colors
  static const Color background = Color(0xFFF5F5F5); // Light gray
  static const Color surface = Color(0xFFFFFFFF); // White
  static const Color error = Color(0xFFE53935); // Red
  
  // Text Colors
  static const Color textPrimary = Color(0xFF212121); // Dark gray
  static const Color textSecondary = Color(0xFF757575); // Medium gray
  static const Color textHint = Color(0xFFBDBDBD); // Light gray
}

// Maps classifier model output labels → app category strings
class ClassifierCategoryMap {
  static const Map<String, String> labelToCategory = {
    'atm': 'ATM',
    'food': 'Food & Dining',
    'grocery': 'Groceries',
    'pos_fuel': 'Fuel',
    'pos_store': 'Shopping',
    'store': 'Shopping',
  };
}

// Expense Categories
class ExpenseCategories {
  static const List<String> categories = [
    'Food & Dining',
    'Groceries',
    'Transportation',
    'Shopping',
    'Bills & Utilities',
    'Medicines',
    'Entertainment',
    'Other',
  ];
  
  // Category colors for charts
  static const Map<String, Color> categoryColors = {
    'Food & Dining': Color(0xFFFF6B6B),
    'Groceries': Color(0xFF4ECDC4),
    'Transportation': Color(0xFFFFE66D),
    'Shopping': Color(0xFF95E1D3),
    'Bills & Utilities': Color(0xFFF38181),
    'Medicines': Color(0xFFAA96DA),
    'Entertainment': Color(0xFFFCBF49),
    'Other': Color(0xFF9E9E9E),
  };
  
  // Category icons
  static const Map<String, IconData> categoryIcons = {
    'Food & Dining': Icons.restaurant,
    'Groceries': Icons.shopping_cart,
    'Transportation': Icons.directions_car,
    'Shopping': Icons.shopping_bag,
    'Bills & Utilities': Icons.receipt_long,
    'Medicines': Icons.medical_services,
    'Entertainment': Icons.movie,
    'Other': Icons.more_horiz,
  };
}

// Date Formats
class DateFormats {
  static const String displayDate = 'MMM dd, yyyy'; // Jan 20, 2026
  static const String fullDate = 'MMMM dd, yyyy'; // January 20, 2026
  static const String shortDate = 'MM/dd/yyyy'; // 01/20/2026
  static const String monthYear = 'MMMM yyyy'; // January 2026
}

// Database Constants
class DatabaseConstants {
  static const String databaseName = 'receipt_iq.db';
  static const int databaseVersion = 1;
  
  // Table names
  static const String receiptsTable = 'receipts';
  static const String expensesTable = 'expenses';
}