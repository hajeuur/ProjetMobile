import 'package:sqflite/sqflite.dart';

import '../logic/pack_format.dart';

/// Tables de la gestion 5 — Courses et Budget.
///
/// shopping_lists, shopping_items, receipts, receipt_lines et budgets
/// (cahier des charges §10), plus deux tables techniques propres à la
/// gestion : shopping_api_cache (réponses Open Prices) et shopping_settings
/// (capteurs activés, alertes déjà envoyées).
///
/// `store_id` pointe vers stores (gestion 4) et `product_id` vers products
/// (gestion 2) sans être déclarés en clés étrangères : ces tables
/// appartiennent à d'autres gestions et peuvent ne pas exister tant que
/// l'intégration n'est pas faite.
class ShoppingSchema {
  ShoppingSchema._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE shopping_lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        store_id INTEGER,
        status TEXT NOT NULL DEFAULT 'active'
      )''');
    await db.execute('CREATE INDEX idx_shopping_lists_user ON shopping_lists(user_id, status)');

    await db.execute('''
      CREATE TABLE shopping_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        product_id INTEGER,
        quantity REAL,
        unit TEXT,
        checked INTEGER NOT NULL DEFAULT 0,
        origin TEXT NOT NULL DEFAULT 'manual',
        aisle TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_shopping_items_list ON shopping_items(list_id)');

    await db.execute('''
      CREATE TABLE receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        store_id INTEGER,
        store_name TEXT,
        date TEXT NOT NULL,
        total REAL NOT NULL,
        photo TEXT,
        list_id INTEGER REFERENCES shopping_lists(id) ON DELETE SET NULL
      )''');
    await db.execute('CREATE INDEX idx_receipts_user_date ON receipts(user_id, date)');

    await db.execute('''
      CREATE TABLE receipt_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        product_id INTEGER,
        barcode TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL,
        category TEXT,
        pack_size REAL,
        pack_unit TEXT,
        pack_confirmed INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX idx_receipt_lines_receipt ON receipt_lines(receipt_id)');

    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        alert_threshold INTEGER NOT NULL DEFAULT 80,
        UNIQUE(user_id, month)
      )''');

    await db.execute('''
      CREATE TABLE shopping_api_cache (
        key TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE shopping_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  static Future<void> upgrade(DatabaseExecutor db, int from, int to) async {
    // Base créée en version 1 par la gestion 3 seule : on ajoute les tables
    // (déjà avec les colonnes de la version 3).
    if (from < 2) {
      await create(db);
      return;
    }
    // Version 3 : format des produits (détecteur de shrinkflation), puis
    // lecture du format des lignes existantes à partir de leur libellé.
    if (from < 3) {
      await db.execute('ALTER TABLE receipt_lines ADD COLUMN pack_size REAL');
      await db.execute('ALTER TABLE receipt_lines ADD COLUMN pack_unit TEXT');
      await db.execute('ALTER TABLE receipt_lines ADD COLUMN pack_confirmed INTEGER NOT NULL DEFAULT 0');
      final rows = await db.query('receipt_lines', columns: ['id', 'label']);
      for (final r in rows) {
        final f = parsePackFormat(r['label'] as String);
        if (f == null) continue;
        await db.update(
          'receipt_lines',
          {'pack_size': f.amount, 'pack_unit': f.measure.base},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
    }
  }
}
