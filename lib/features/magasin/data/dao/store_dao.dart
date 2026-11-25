import 'package:sqflite/sqflite.dart';

import '../models/store.dart';

/// Data-access object for the `stores` table.
///
/// Every write/read that touches `stores` goes through this class.
/// [userId] filtering is mandatory on every public method to enforce
/// per-user data isolation (AGENTS.md rule 4).
class StoreDao {
  const StoreDao(this._db);
  final DatabaseExecutor _db;

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Insert a new store; returns the auto-generated id.
  Future<int> insert(Store store) =>
      _db.insert('stores', store.toMap()..remove('id'));

  /// Update all mutable columns of an existing store.
  Future<void> update(Store store) => _db.update(
        'stores',
        store.toMap()..remove('id'),
        where: 'id = ? AND user_id = ?',
        whereArgs: [store.id, store.userId],
      );

  /// Hard-delete a store row (cascade deletes aisles + prices via FK).
  Future<void> delete(int id, int userId) => _db.delete(
        'stores',
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );

  /// Set or clear the favorite flag for a store.
  Future<void> setFavorite(int id, int userId, {required bool isFavorite}) =>
      _db.update(
        'stores',
        {'is_favorite': isFavorite ? 1 : 0},
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Fetch a single store by [id], scoped to [userId].  Returns null if not
  /// found or if the store belongs to a different user.
  Future<Store?> findById(int id, int userId) async {
    final rows = await _db.query(
      'stores',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    return rows.isEmpty ? null : Store.fromMap(rows.first);
  }

  /// All stores belonging to [userId], optionally filtered by name [query]
  /// and/or [type].
  Future<List<Store>> findByUser(
    int userId, {
    String? query,
    StoreType? type,
  }) async {
    final conditions = <String>['user_id = ?'];
    final args = <dynamic>[userId];

    if (query != null && query.isNotEmpty) {
      conditions.add('name LIKE ?');
      args.add('%$query%');
    }
    if (type != null) {
      conditions.add('type = ?');
      args.add(type.value);
    }

    final rows = await _db.query(
      'stores',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'name ASC',
    );
    return rows.map(Store.fromMap).toList();
  }

  /// Find an already-imported OSM store by its [osmId] for the given user
  /// (used for idempotent Overpass upsert).
  Future<Store?> findByOsmId(int userId, String osmId) async {
    final rows = await _db.query(
      'stores',
      where: 'user_id = ? AND osm_id = ?',
      whereArgs: [userId, osmId],
      limit: 1,
    );
    return rows.isEmpty ? null : Store.fromMap(rows.first);
  }

  /// Return the user's favorite store, or null if none is set.
  Future<Store?> findFavorite(int userId) async {
    final rows = await _db.query(
      'stores',
      where: 'user_id = ? AND is_favorite = 1',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : Store.fromMap(rows.first);
  }
}
