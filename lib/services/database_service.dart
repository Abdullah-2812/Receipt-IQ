import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../models/receipt_model.dart';
import '../utils/constants.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(DatabaseConstants.databaseName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: DatabaseConstants.databaseVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.receiptsTable} (
        id                   TEXT PRIMARY KEY,
        merchantName         TEXT NOT NULL,
        date                 TEXT NOT NULL,
        totalAmount          REAL NOT NULL,
        category             TEXT NOT NULL,
        imagePath            TEXT,
        notes                TEXT,
        createdAt            TEXT NOT NULL,
        rawOcrText           TEXT,
        vendorAddress        TEXT,
        receiptTime          TEXT,
        subtotal             REAL,
        tax                  REAL,
        fbrPosFee            REAL,
        discount             REAL,
        cashPaid             REAL,
        changeDue            REAL,
        paymentMethod        TEXT,
        fbrInvoiceId         TEXT,
        ntn                  TEXT,
        invoiceNumber        TEXT,
        syncStatus           TEXT,
        categorySpecificData TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE receipt_items (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        receiptId   TEXT NOT NULL,
        name        TEXT NOT NULL,
        quantity    REAL NOT NULL,
        price       REAL NOT NULL,
        totalPrice  REAL NOT NULL,
        FOREIGN KEY (receiptId) REFERENCES ${DatabaseConstants.receiptsTable} (id) ON DELETE CASCADE
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      const newColumns = [
        'rawOcrText TEXT',
        'vendorAddress TEXT',
        'receiptTime TEXT',
        'subtotal REAL',
        'tax REAL',
        'fbrPosFee REAL',
        'discount REAL',
        'cashPaid REAL',
        'changeDue REAL',
        'paymentMethod TEXT',
        'fbrInvoiceId TEXT',
        'ntn TEXT',
        'invoiceNumber TEXT',
        'syncStatus TEXT',
        'categorySpecificData TEXT',
      ];
      for (final col in newColumns) {
        await db.execute(
          'ALTER TABLE ${DatabaseConstants.receiptsTable} ADD COLUMN $col',
        );
      }
    }
    if (oldVersion < 3) {
      // Dedup receipt_items left over from the pre-fix insertReceipt bug.
      // Strict equality across all item fields — keeps the lowest id row,
      // drops the rest. Any genuine identical-looking duplicates would be
      // unusual on a single receipt.
      await db.execute('''
        DELETE FROM receipt_items
        WHERE id NOT IN (
          SELECT MIN(id) FROM receipt_items
          GROUP BY receiptId, name, quantity, price, totalPrice
        )
      ''');
    }
    if (oldVersion < 4) {
      // Category consolidation: 8 labels -> 6, with two renames and two
      // collapses into 'Other' (Medicines/Entertainment were never set
      // by the classifier, so any existing rows with those values came
      // from the legacy ocr_service or manual edits).
      const renames = {
        'Transportation':    'Fuel',
        'Bills & Utilities': 'Cash & ATM',
        'Medicines':         'Other',
        'Entertainment':     'Other',
      };
      for (final entry in renames.entries) {
        await db.update(
          DatabaseConstants.receiptsTable,
          {'category': entry.value},
          where: 'category = ?',
          whereArgs: [entry.key],
        );
      }
    }
  }

  // ─── Seed ─────────────────────────────────────────────────────────────────

  Future<void> seedIfEmpty() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DatabaseConstants.receiptsTable}'),
        ) ?? 0;
    if (count > 0) return;

    final now = DateTime.now();
    for (final r in _seedReceipts(now)) {
      await db.insert(DatabaseConstants.receiptsTable, r.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      for (final item in r.items) {
        await db.insert('receipt_items', {'receiptId': r.id, ...item.toMap()});
      }
    }
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> insertReceipt(Receipt receipt) async {
    final db = await database;
    await db.insert(DatabaseConstants.receiptsTable, receipt.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('receipt_items',
        where: 'receiptId = ?', whereArgs: [receipt.id]);
    for (final item in receipt.items) {
      await db.insert('receipt_items', {'receiptId': receipt.id, ...item.toMap()});
    }
  }

  Future<void> updateReceipt(Receipt receipt) async {
    final db = await database;
    await db.update(
      DatabaseConstants.receiptsTable,
      receipt.toMap(),
      where: 'id = ?',
      whereArgs: [receipt.id],
    );
    await db.delete('receipt_items',
        where: 'receiptId = ?', whereArgs: [receipt.id]);
    for (final item in receipt.items) {
      await db.insert('receipt_items', {'receiptId': receipt.id, ...item.toMap()});
    }
  }

  Future<void> deleteReceipt(String id) async {
    final db = await database;
    await db.delete(DatabaseConstants.receiptsTable,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> wipeAllReceipts() async {
    final db = await database;
    await db.delete('receipt_items');
    await db.delete(DatabaseConstants.receiptsTable);
  }

  Future<List<Receipt>> getAllReceipts({bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.query(
      DatabaseConstants.receiptsTable,
      where: includeDeleted
          ? null
          : 'syncStatus IS NULL OR syncStatus != ?',
      whereArgs: includeDeleted ? null : ['pending_delete'],
      orderBy: 'createdAt DESC',
    );
    final list = <Receipt>[];
    for (final row in rows) {
      final items = await _getItems(row['id'] as String);
      list.add(Receipt.fromMap(row)..items.addAll(items));
    }
    return list;
  }

  Future<List<ReceiptItem>> _getItems(String receiptId) async {
    final db = await database;
    final rows = await db.query('receipt_items',
        where: 'receiptId = ?', whereArgs: [receiptId]);
    return rows.map((r) => ReceiptItem.fromMap(r)).toList();
  }

  Future<List<Receipt>> getReceiptsByDateRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final rows = await db.query(
      DatabaseConstants.receiptsTable,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    final list = <Receipt>[];
    for (final row in rows) {
      final items = await _getItems(row['id'] as String);
      list.add(Receipt.fromMap(row)..items.addAll(items));
    }
    return list;
  }

  Future<int> getReceiptCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM ${DatabaseConstants.receiptsTable}');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> getTotalSpending() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(totalAmount) as total FROM ${DatabaseConstants.receiptsTable}');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getSpendingInRange(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(totalAmount) as total FROM ${DatabaseConstants.receiptsTable} WHERE date BETWEEN ? AND ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> getSpendingByCategory() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT category, SUM(totalAmount) as total FROM ${DatabaseConstants.receiptsTable} GROUP BY category');
    return {
      for (final row in result)
        row['category'] as String: (row['total'] as num).toDouble()
    };
  }

  Future close() async => (await database).close();
}

// ─── Seed data — only uses categories the classifier can produce ──────────────

List<Receipt> _seedReceipts(DateTime now) => [
      Receipt(
        id: 'seed_1',
        merchantName: 'Al-Madina Mart',
        date: now.subtract(const Duration(days: 2)),
        totalAmount: 2450.00,
        category: 'Groceries',
        items: [
          ReceiptItem(name: 'Rice 5kg', quantity: 1, price: 1200, totalPrice: 1200),
          ReceiptItem(name: 'Oil 1L', quantity: 2, price: 625, totalPrice: 1250),
        ],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_2',
        merchantName: 'Pizza Hut',
        date: now.subtract(const Duration(days: 5)),
        totalAmount: 1890.00,
        category: 'Food & Dining',
        items: [
          ReceiptItem(name: 'Medium Pizza', quantity: 1, price: 1200, totalPrice: 1200),
          ReceiptItem(name: 'Drinks', quantity: 2, price: 345, totalPrice: 690),
        ],
        notes: 'Family dinner',
        createdAt: now,
      ),
      Receipt(
        id: 'seed_3',
        merchantName: 'Shell Petrol Pump',
        date: now.subtract(const Duration(days: 7)),
        totalAmount: 5000.00,
        category: 'Fuel',
        items: [],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_4',
        merchantName: 'Daraz Online',
        date: now.subtract(const Duration(days: 10)),
        totalAmount: 3200.00,
        category: 'Shopping',
        items: [
          ReceiptItem(name: 'Phone Case', quantity: 1, price: 800, totalPrice: 800),
          ReceiptItem(name: 'USB Cable', quantity: 2, price: 600, totalPrice: 1200),
          ReceiptItem(name: 'Power Bank', quantity: 1, price: 1200, totalPrice: 1200),
        ],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_5',
        merchantName: 'HBL ATM',
        date: now.subtract(const Duration(days: 12)),
        totalAmount: 10000.00,
        category: 'Cash & ATM',
        notes: 'Cash withdrawal',
        items: [],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_6',
        merchantName: 'Imtiaz Superstore',
        date: now.subtract(const Duration(days: 15)),
        totalAmount: 6750.00,
        category: 'Groceries',
        items: [
          ReceiptItem(name: 'Chicken 2kg', quantity: 2, price: 1200, totalPrice: 2400),
          ReceiptItem(name: 'Milk 6 pack', quantity: 1, price: 1800, totalPrice: 1800),
          ReceiptItem(name: 'Bread', quantity: 3, price: 250, totalPrice: 750),
          ReceiptItem(name: 'Eggs dozen', quantity: 2, price: 400, totalPrice: 800),
        ],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_7',
        merchantName: 'PSO Pump',
        date: now.subtract(const Duration(days: 18)),
        totalAmount: 3500.00,
        category: 'Fuel',
        items: [],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_8',
        merchantName: "McDonald's",
        date: now.subtract(const Duration(days: 20)),
        totalAmount: 1450.00,
        category: 'Food & Dining',
        items: [
          ReceiptItem(name: 'Big Mac Meal', quantity: 1, price: 900, totalPrice: 900),
          ReceiptItem(name: 'McFlurry', quantity: 1, price: 350, totalPrice: 350),
          ReceiptItem(name: 'Fries', quantity: 1, price: 200, totalPrice: 200),
        ],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_9',
        merchantName: 'Khaadi',
        date: now.subtract(const Duration(days: 23)),
        totalAmount: 4800.00,
        category: 'Shopping',
        items: [
          ReceiptItem(name: 'Kurta', quantity: 2, price: 1800, totalPrice: 3600),
          ReceiptItem(name: 'Dupatta', quantity: 1, price: 1200, totalPrice: 1200),
        ],
        createdAt: now,
      ),
      Receipt(
        id: 'seed_10',
        merchantName: 'MCB ATM',
        date: now.subtract(const Duration(days: 27)),
        totalAmount: 5000.00,
        category: 'Cash & ATM',
        notes: 'Cash withdrawal',
        items: [],
        createdAt: now,
      ),
    ];
