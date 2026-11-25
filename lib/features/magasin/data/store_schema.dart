import 'package:sqflite/sqflite.dart';

/// Tables de la gestion 4 — Magasins.
///
/// stores, store_aisles, store_prices.
///
/// store_prices.product_id pointe vers products (gestion 2) mais n'est PAS
/// déclaré en clé étrangère, pour la même raison que recipe_ingredients
/// dans RecipeSchema : la table appartient à une autre gestion.
class StoreSchema {
  StoreSchema._();

  // ── DDL version 1 ──────────────────────────────────────────────────────────

  static Future<void> create(DatabaseExecutor db) async {
    // stores
    await db.execute('''
      CREATE TABLE stores (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id              INTEGER NOT NULL,
        name                 TEXT    NOT NULL,
        type                 TEXT    NOT NULL
                             CHECK (type IN ('supermarket','grocery','market')),
        latitude             REAL    NOT NULL,
        longitude            REAL    NOT NULL,
        address              TEXT,
        opening_hours        TEXT,
        notification_radius_m INTEGER NOT NULL DEFAULT 200
                             CHECK (notification_radius_m > 0),
        is_favorite          INTEGER NOT NULL DEFAULT 0
                             CHECK (is_favorite IN (0,1)),
        osm_id               TEXT,
        source               TEXT    NOT NULL DEFAULT 'manual'
                             CHECK (source IN ('manual','osm')),
        created_at           TEXT    NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_stores_user ON stores(user_id)');
    await db.execute(
      'CREATE UNIQUE INDEX idx_stores_user_osm '
      'ON stores(user_id, osm_id) WHERE osm_id IS NOT NULL',
    );

    // store_aisles
    await db.execute('''
      CREATE TABLE store_aisles (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id   INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
        name       TEXT    NOT NULL,
        sort_order INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX idx_aisles_store_order '
      'ON store_aisles(store_id, sort_order)',
    );

    // store_prices
    await db.execute('''
      CREATE TABLE store_prices (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id    INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
        product_id  INTEGER NOT NULL,
        price       REAL    NOT NULL CHECK (price >= 0),
        recorded_at TEXT    NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX idx_prices_store_product '
      'ON store_prices(store_id, product_id, recorded_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_prices_product ON store_prices(product_id)',
    );
  }

  // ── Migrations ──────────────────────────────────────────────────────────────

  /// Called by AppDatabase._onUpgrade.  Add `if (from < N)` blocks here when
  /// a new migration is needed.  Never mutate a shipped version.
  static Future<void> upgrade(DatabaseExecutor db, int from, int to) async {
    // No migration yet — version 1.
  }
}
