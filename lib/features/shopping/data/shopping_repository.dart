import 'package:sqflite/sqflite.dart';

import '../models/budget.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../models/shopping_list.dart';

/// Accès SQLite aux tables de la gestion 5. Aucune logique métier ici.
class ShoppingRepository {
  ShoppingRepository(this.db);
  final Database db;

  // --------------------------------------------------------------- Listes

  static const _listSelect = '''
    SELECT l.*,
      (SELECT COUNT(*) FROM shopping_items i WHERE i.list_id = l.id) AS item_count,
      (SELECT COUNT(*) FROM shopping_items i WHERE i.list_id = l.id AND i.checked = 1) AS checked_count
    FROM shopping_lists l''';

  Future<List<ShoppingList>> lists(int userId, {ListStatus? status}) async {
    final rows = await db.rawQuery(
      '$_listSelect WHERE l.user_id = ?${status == null ? '' : ' AND l.status = ?'} ORDER BY l.created_at DESC, l.id DESC',
      [userId, if (status != null) status.dbValue],
    );
    return rows.map(ShoppingList.fromMap).toList();
  }

  Future<ShoppingList?> list(int id) async {
    final rows = await db.rawQuery('$_listSelect WHERE l.id = ?', [id]);
    return rows.isEmpty ? null : ShoppingList.fromMap(rows.first);
  }

  Future<int> insertList(ShoppingList l) => db.insert('shopping_lists', l.toMap());

  Future<void> updateList(ShoppingList l) =>
      db.update('shopping_lists', l.toMap(), where: 'id = ?', whereArgs: [l.id]);

  Future<void> deleteList(int id) => db.delete('shopping_lists', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- Articles

  Future<List<ShoppingItem>> items(int listId) async {
    final rows = await db.query('shopping_items', where: 'list_id = ?', whereArgs: [listId], orderBy: 'position, id');
    return rows.map(ShoppingItem.fromMap).toList();
  }

  Future<ShoppingItem?> item(int id) async {
    final rows = await db.query('shopping_items', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ShoppingItem.fromMap(rows.first);
  }

  Future<int> nextPosition(int listId) async {
    final r = await db.rawQuery('SELECT MAX(position) AS m FROM shopping_items WHERE list_id = ?', [listId]);
    return ((r.first['m'] as int?) ?? -1) + 1;
  }

  Future<int> insertItem(ShoppingItem i) => db.insert('shopping_items', i.toMap());

  Future<void> updateItem(ShoppingItem i) =>
      db.update('shopping_items', i.toMap(), where: 'id = ?', whereArgs: [i.id]);

  Future<void> setChecked(int id, bool checked) =>
      db.update('shopping_items', {'checked': checked ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteItem(int id) => db.delete('shopping_items', where: 'id = ?', whereArgs: [id]);

  Future<int> deleteCheckedItems(int listId) =>
      db.delete('shopping_items', where: 'list_id = ? AND checked = 1', whereArgs: [listId]);

  // -------------------------------------------------------------- Tickets

  static const _receiptSelect = '''
    SELECT r.*, (SELECT COUNT(*) FROM receipt_lines x WHERE x.receipt_id = r.id) AS line_count
    FROM receipts r''';

  Future<List<Receipt>> receipts(int userId, {DateTime? from, DateTime? to}) async {
    final where = ['r.user_id = ?'];
    final args = <Object>[userId];
    if (from != null) {
      where.add('r.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('r.date < ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.rawQuery('$_receiptSelect WHERE ${where.join(' AND ')} ORDER BY r.date DESC, r.id DESC', args);
    return rows.map((m) => Receipt.fromMap(m)).toList();
  }

  Future<Receipt?> receipt(int id) async {
    final rows = await db.rawQuery('$_receiptSelect WHERE r.id = ?', [id]);
    if (rows.isEmpty) return null;
    final lines = await db.query('receipt_lines', where: 'receipt_id = ?', whereArgs: [id], orderBy: 'id');
    return Receipt.fromMap(rows.first, lines: lines.map(ReceiptLine.fromMap).toList());
  }

  Future<int> insertReceipt(Receipt r) => db.transaction((txn) async {
        final id = await txn.insert('receipts', r.toMap());
        for (final l in r.lines) {
          await txn.insert('receipt_lines', l.toMap(id));
        }
        return id;
      });

  /// Remplace l'en-tête et toutes les lignes du ticket.
  Future<void> updateReceipt(Receipt r) => db.transaction((txn) async {
        await txn.update('receipts', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
        await txn.delete('receipt_lines', where: 'receipt_id = ?', whereArgs: [r.id]);
        for (final l in r.lines) {
          await txn.insert('receipt_lines', l.toMap(r.id!));
        }
      });

  Future<int> insertReceiptLine(int receiptId, ReceiptLine l) => db.insert('receipt_lines', l.toMap(receiptId));

  Future<void> updateReceiptLine(ReceiptLine l) =>
      db.update('receipt_lines', l.toMap(l.receiptId!), where: 'id = ?', whereArgs: [l.id]);

  Future<int?> receiptIdOfLine(int lineId) async {
    final rows = await db.query('receipt_lines', columns: ['receipt_id'], where: 'id = ?', whereArgs: [lineId]);
    return rows.isEmpty ? null : rows.first['receipt_id'] as int;
  }

  Future<void> deleteReceiptLine(int id) => db.delete('receipt_lines', where: 'id = ?', whereArgs: [id]);

  Future<void> setReceiptList(int id, int? listId) =>
      db.update('receipts', {'list_id': listId}, where: 'id = ?', whereArgs: [id]);

  Future<void> setReceiptTotal(int id, double total) =>
      db.update('receipts', {'total': total}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteReceipt(int id) => db.delete('receipts', where: 'id = ?', whereArgs: [id]);

  /// Toutes les lignes achetées depuis [from], avec la date et le magasin du
  /// ticket (pour l'historique des prix et les statistiques).
  Future<List<({ReceiptLine line, DateTime date, String? storeName, int? storeId})>> linesSince(
    int userId,
    DateTime from,
  ) async {
    final rows = await db.rawQuery('''
      SELECT x.*, r.date AS r_date, r.store_name AS r_store, r.store_id AS r_store_id
      FROM receipt_lines x JOIN receipts r ON r.id = x.receipt_id
      WHERE r.user_id = ? AND r.date >= ?
      ORDER BY r.date''', [userId, from.toIso8601String()]);
    return [
      for (final m in rows)
        (
          line: ReceiptLine.fromMap(m),
          date: DateTime.parse(m['r_date'] as String),
          storeName: m['r_store'] as String?,
          storeId: m['r_store_id'] as int?,
        ),
    ];
  }

  /// Somme des tickets entre [from] (inclus) et [to] (exclu).
  Future<double> spentBetween(int userId, DateTime from, DateTime to) async {
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS s FROM receipts WHERE user_id = ? AND date >= ? AND date < ?',
      [userId, from.toIso8601String(), to.toIso8601String()],
    );
    return (r.first['s'] as num).toDouble();
  }

  // -------------------------------------------------------------- Budgets

  Future<List<Budget>> budgets(int userId) async {
    final rows = await db.query('budgets', where: 'user_id = ?', whereArgs: [userId], orderBy: 'month DESC');
    return rows.map(Budget.fromMap).toList();
  }

  Future<Budget?> budget(int userId, DateTime month) async {
    final rows = await db.query('budgets', where: 'user_id = ? AND month = ?', whereArgs: [userId, monthKey(month)]);
    return rows.isEmpty ? null : Budget.fromMap(rows.first);
  }

  /// Crée ou remplace le budget du mois.
  Future<void> upsertBudget(Budget b) async {
    final existing = await budget(b.userId, b.month);
    if (existing == null) {
      await db.insert('budgets', b.toMap()..remove('id'));
    } else {
      await db.update('budgets', b.toMap()..remove('id'), where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  Future<void> deleteBudget(int id) => db.delete('budgets', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- Réglages

  Future<String?> setting(String key) async {
    final rows = await db.query('shopping_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db.insert(
        'shopping_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
