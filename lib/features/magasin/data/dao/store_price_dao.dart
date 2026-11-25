import 'package:sqflite/sqflite.dart';

import '../../models/store_price.dart';

/// A minimal value object used by the basket comparator and price-history chart.
class PricePoint {
  const PricePoint({
    required this.storeId,
    required this.productId,
    required this.price,
    required this.recordedAt,
  });

  final int storeId;
  final int productId;
  final double price;
  final String recordedAt; // ISO-8601

  factory PricePoint.fromMap(Map<String, dynamic> m) => PricePoint(
        storeId: m['store_id'] as int,
        productId: m['product_id'] as int,
        price: (m['price'] as num).toDouble(),
        recordedAt: m['recorded_at'] as String,
      );
}

/// Data-access object for the `store_prices` table.
class StorePriceDao {
  const StorePriceDao(this._db);
  final DatabaseExecutor _db;

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Insert a price record; returns the auto-generated id.
  Future<int> insert(StorePrice price) =>
      _db.insert('store_prices', price.toMap()..remove('id'));

  /// Update price and recorded_at of an existing record.
  Future<void> update(StorePrice price) => _db.update(
        'store_prices',
        {'price': price.price, 'recorded_at': price.recordedAt},
        where: 'id = ?',
        whereArgs: [price.id],
      );

  /// Delete a price record by id.
  Future<void> delete(int id) => _db.delete(
        'store_prices',
        where: 'id = ?',
        whereArgs: [id],
      );

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// All price records for a store, most recent first.
  Future<List<StorePrice>> findByStore(int storeId) async {
    final rows = await _db.query(
      'store_prices',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(StorePrice.fromMap).toList();
  }

  /// Latest recorded price for each product in [productIds] within a single
  /// store.  Returns a map of productId → [StorePrice].
  Future<Map<int, StorePrice>> findLatestForStore(
    int storeId,
    List<int> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    final placeholders = productIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT *
      FROM store_prices sp
      WHERE sp.store_id = ?
        AND sp.product_id IN ($placeholders)
        AND sp.recorded_at = (
          SELECT MAX(sp2.recorded_at)
          FROM store_prices sp2
          WHERE sp2.store_id = sp.store_id
            AND sp2.product_id = sp.product_id
        )
      ''',
      [storeId, ...productIds],
    );
    return {
      for (final r in rows) (r['product_id'] as int): StorePrice.fromMap(r),
    };
  }

  /// Latest recorded price of each [productIds] from stores OTHER THAN
  /// [excludeStoreId] belonging to [userId].  Used for missing-price
  /// estimation (average across other stores).
  Future<Map<int, List<double>>> findLatestAcrossOtherStores(
    int excludeStoreId,
    List<int> productIds,
    int userId,
  ) async {
    if (productIds.isEmpty) return {};
    final placeholders = productIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT sp.product_id, sp.price
      FROM store_prices sp
      INNER JOIN stores s ON s.id = sp.store_id
      WHERE s.user_id = ?
        AND sp.store_id != ?
        AND sp.product_id IN ($placeholders)
        AND sp.recorded_at = (
          SELECT MAX(sp2.recorded_at)
          FROM store_prices sp2
          WHERE sp2.store_id = sp.store_id
            AND sp2.product_id = sp.product_id
        )
      ''',
      [userId, excludeStoreId, ...productIds],
    );
    final result = <int, List<double>>{};
    for (final r in rows) {
      final pid = r['product_id'] as int;
      result.putIfAbsent(pid, () => []).add((r['price'] as num).toDouble());
    }
    return result;
  }

  /// Full chronological price history for a single (store, product) pair,
  /// oldest first — used by the price evolution chart.
  Future<List<PricePoint>> findHistory(int storeId, int productId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT store_id, product_id, price, recorded_at
      FROM store_prices
      WHERE store_id = ? AND product_id = ?
      ORDER BY recorded_at ASC
      ''',
      [storeId, productId],
    );
    return rows.map(PricePoint.fromMap).toList();
  }

  /// Average price of [productId] across ALL stores belonging to [userId].
  /// Returns null when no price exists at all.
  Future<double?> averagePriceAcrossStores(int userId, int productId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT AVG(sp.price) AS avg_price
      FROM store_prices sp
      INNER JOIN stores s ON s.id = sp.store_id
      WHERE s.user_id = ? AND sp.product_id = ?
        AND sp.recorded_at = (
          SELECT MAX(sp2.recorded_at)
          FROM store_prices sp2
          WHERE sp2.store_id = sp.store_id
            AND sp2.product_id = sp.product_id
        )
      ''',
      [userId, productId],
    );
    final avg = rows.first['avg_price'];
    return avg == null ? null : (avg as num).toDouble();
  }
}
