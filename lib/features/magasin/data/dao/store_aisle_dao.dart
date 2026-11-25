import 'package:sqflite/sqflite.dart';

import '../../models/store_aisle.dart';

/// Data-access object for the `store_aisles` table.
class StoreAisleDao {
  const StoreAisleDao(this._db);
  final DatabaseExecutor _db;

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Insert a new aisle; returns the auto-generated id.
  Future<int> insert(StoreAisle aisle) =>
      _db.insert('store_aisles', aisle.toMap()..remove('id'));

  /// Update the name and sort_order of an existing aisle.
  Future<void> update(StoreAisle aisle) => _db.update(
        'store_aisles',
        {'name': aisle.name, 'sort_order': aisle.sortOrder},
        where: 'id = ?',
        whereArgs: [aisle.id],
      );

  /// Delete a single aisle by id.
  Future<void> delete(int id) => _db.delete(
        'store_aisles',
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Atomically update the [sort_order] of multiple aisles inside a single
  /// transaction.  Pass the aisles in the desired visual order; their
  /// [sortOrder] fields will be used directly.
  Future<void> updateOrders(
    List<StoreAisle> aisles, {
    Transaction? txn,
  }) async {
    final executor = txn ?? _db;
    for (final aisle in aisles) {
      await executor.update(
        'store_aisles',
        {'sort_order': aisle.sortOrder},
        where: 'id = ?',
        whereArgs: [aisle.id],
      );
    }
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// All aisles for a store, ordered by [sort_order] ascending.
  Future<List<StoreAisle>> findByStore(int storeId) async {
    final rows = await _db.query(
      'store_aisles',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(StoreAisle.fromMap).toList();
  }
}
