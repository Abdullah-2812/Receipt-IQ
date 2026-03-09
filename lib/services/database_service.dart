import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/receipt_model.dart';
import '../utils/constants.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  // Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(DatabaseConstants.databaseName);
    return _database!;
  }

  // Initialize database
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: DatabaseConstants.databaseVersion,
      onCreate: _createDB,
    );
  }

  // Create tables
  Future _createDB(Database db, int version) async {
    // Receipts table
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.receiptsTable} (
        id TEXT PRIMARY KEY,
        merchantName TEXT NOT NULL,
        date TEXT NOT NULL,
        totalAmount REAL NOT NULL,
        category TEXT NOT NULL,
        imagePath TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    // Receipt items table
    await db.execute('''
      CREATE TABLE receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receiptId TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        totalPrice REAL NOT NULL,
        FOREIGN KEY (receiptId) REFERENCES ${DatabaseConstants.receiptsTable} (id) ON DELETE CASCADE
      )
    ''');
  }

  // Insert receipt
  Future<void> insertReceipt(Receipt receipt) async {
    final db = await database;
    
    // Insert receipt
    await db.insert(
      DatabaseConstants.receiptsTable,
      receipt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Insert items
    for (var item in receipt.items) {
      await db.insert('receipt_items', {
        'receiptId': receipt.id,
        ...item.toMap(),
      });
    }
  }

  // Get all receipts
  Future<List<Receipt>> getAllReceipts() async {
    final db = await database;
    final receipts = await db.query(
      DatabaseConstants.receiptsTable,
      orderBy: 'date DESC',
    );

    List<Receipt> receiptList = [];
    for (var receiptMap in receipts) {
      final items = await _getReceiptItems(receiptMap['id'] as String);
      receiptList.add(Receipt.fromMap(receiptMap)..items.addAll(items));
    }

    return receiptList;
  }

  // Get receipt items
  Future<List<ReceiptItem>> _getReceiptItems(String receiptId) async {
    final db = await database;
    final items = await db.query(
      'receipt_items',
      where: 'receiptId = ?',
      whereArgs: [receiptId],
    );

    return items.map((item) => ReceiptItem.fromMap(item)).toList();
  }

  // Get receipts by date range
  Future<List<Receipt>> getReceiptsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    final receipts = await db.query(
      DatabaseConstants.receiptsTable,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'date DESC',
    );

    List<Receipt> receiptList = [];
    for (var receiptMap in receipts) {
      final items = await _getReceiptItems(receiptMap['id'] as String);
      receiptList.add(Receipt.fromMap(receiptMap)..items.addAll(items));
    }

    return receiptList;
  }

  // Get receipts by category
  Future<List<Receipt>> getReceiptsByCategory(String category) async {
    final db = await database;
    final receipts = await db.query(
      DatabaseConstants.receiptsTable,
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'date DESC',
    );

    List<Receipt> receiptList = [];
    for (var receiptMap in receipts) {
      final items = await _getReceiptItems(receiptMap['id'] as String);
      receiptList.add(Receipt.fromMap(receiptMap)..items.addAll(items));
    }

    return receiptList;
  }

  // Get total spending
  Future<double> getTotalSpending() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(totalAmount) as total FROM ${DatabaseConstants.receiptsTable}',
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get spending by category
  Future<Map<String, double>> getSpendingByCategory() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT category, SUM(totalAmount) as total FROM ${DatabaseConstants.receiptsTable} GROUP BY category',
    );

    Map<String, double> categorySpending = {};
    for (var row in result) {
      categorySpending[row['category'] as String] = 
        (row['total'] as num).toDouble();
    }
    return categorySpending;
  }

  // Delete receipt
  Future<void> deleteReceipt(String id) async {
    final db = await database;
    await db.delete(
      DatabaseConstants.receiptsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}