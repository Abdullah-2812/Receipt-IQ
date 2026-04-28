import 'package:flutter/material.dart';

// App Information
class AppConstants {
  static const String appName = 'Receipt IQ';
  static const String appVersion = '1.0.0';
}

// Backend API endpoint. Single source of truth — every API client
// (sync, analytics, future endpoints) reads from here. Swap this one
// line when changing networks or pointing at ngrok for demos.
class ApiConfig {
  // Public ngrok URL — works on any network (WiFi, cellular).
  // Tunnel is opened with:
  //   ngrok http --domain=ninetieth-zestfully-lid.ngrok-free.dev 8000
  // See D:\receipt_iq_backend\NGROK_SETUP.txt for full instructions.
  static const String baseUrl = 'https://ninetieth-zestfully-lid.ngrok-free.dev';

  // Laptop LAN IP — uncomment for same-WiFi local dev when ngrok is off.
  // static const String baseUrl = 'http://192.168.100.47:8000';
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

// Maps classifier model output labels → app category strings.
// Six labels in, six categories out — every classifier output has a
// matching entry in ExpenseCategories.categories below.
class ClassifierCategoryMap {
  static const Map<String, String> labelToCategory = {
    'atm':       'Cash & ATM',
    'food':      'Food & Dining',
    'grocery':   'Groceries',
    'pos_fuel':  'Fuel',
    'pos_store': 'Shopping',
    'store':     'Shopping',
  };
}

// Expense Categories — six labels, each one mappable from a classifier
// output (Shopping covers both pos_store and store). 'Other' is the
// manual / fallback bucket when classification confidence is low.
class ExpenseCategories {
  static const List<String> categories = [
    'Food & Dining',
    'Groceries',
    'Fuel',
    'Shopping',
    'Cash & ATM',
    'Other',
  ];

  static const Map<String, Color> categoryColors = {
    'Food & Dining': Color(0xFFFF6B6B),
    'Groceries':     Color(0xFF4ECDC4),
    'Fuel':          Color(0xFFFFE66D),
    'Shopping':      Color(0xFF95E1D3),
    'Cash & ATM':    Color(0xFFF38181),
    'Other':         Color(0xFF9E9E9E),
  };

  static const Map<String, IconData> categoryIcons = {
    'Food & Dining': Icons.restaurant,
    'Groceries':     Icons.shopping_cart,
    'Fuel':          Icons.local_gas_station,
    'Shopping':      Icons.shopping_bag,
    'Cash & ATM':    Icons.atm,
    'Other':         Icons.more_horiz,
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
  static const int databaseVersion = 4;
  
  // Table names
  static const String receiptsTable = 'receipts';
  static const String expensesTable = 'expenses';
}