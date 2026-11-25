import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/magasin/data/dao/store_dao.dart';
import 'package:panier_malin/features/magasin/data/dao/store_aisle_dao.dart';
import 'package:panier_malin/features/magasin/data/dao/store_price_dao.dart';
import 'package:panier_malin/features/magasin/models/store.dart';
import 'package:panier_malin/features/magasin/models/store_aisle.dart';
import 'package:panier_malin/features/magasin/models/store_price.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Store _makeStore({int userId = 1, String name = 'Carrefour', String? osmId}) =>
    Store(
      userId: userId,
      name: name,
      type: StoreType.supermarket,
      latitude: 36.8065,
      longitude: 10.1815,
      notificationRadiusM: 300,
      osmId: osmId,
      source: osmId != null ? StoreSource.osm : StoreSource.manual,
      createdAt: DateTime(2026, 11, 25).toIso8601String(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('StoreSchema — DDL & constraints', () {
    late StoreDao storeDao;
    late StoreAisleDao aisleDao;
    late StorePriceDao priceDao;

    setUp(() async {
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      storeDao = StoreDao(db);
      aisleDao = StoreAisleDao(db);
      priceDao = StorePriceDao(db);
    });

    // ── CRUD: stores ──────────────────────────────────────────────────────────

    test('insert + findById round-trip', () async {
      final id = await storeDao.insert(_makeStore());
      final found = await storeDao.findById(id, 1);
      expect(found, isNotNull);
      expect(found!.name, 'Carrefour');
      expect(found.type, StoreType.supermarket);
      expect(found.userId, 1);
    });

    test('update changes name', () async {
      final id = await storeDao.insert(_makeStore());
      final original = (await storeDao.findById(id, 1))!;
      await storeDao.update(original.copyWith(name: 'Monoprix'));
      final updated = await storeDao.findById(id, 1);
      expect(updated!.name, 'Monoprix');
    });

    test('delete removes store', () async {
      final id = await storeDao.insert(_makeStore());
      await storeDao.delete(id, 1);
      final found = await storeDao.findById(id, 1);
      expect(found, isNull);
    });

    test('setFavorite toggles is_favorite', () async {
      final id = await storeDao.insert(_makeStore());
      await storeDao.setFavorite(id, 1, isFavorite: true);
      final store = await storeDao.findById(id, 1);
      expect(store!.isFavorite, isTrue);

      await storeDao.setFavorite(id, 1, isFavorite: false);
      final store2 = await storeDao.findById(id, 1);
      expect(store2!.isFavorite, isFalse);
    });

    // ── user_id isolation ─────────────────────────────────────────────────────

    test('findById returns null for wrong userId', () async {
      final id = await storeDao.insert(_makeStore(userId: 1));
      final found = await storeDao.findById(id, 2); // different user
      expect(found, isNull);
    });

    test('findByUser only returns own stores', () async {
      await storeDao.insert(_makeStore(userId: 1, name: 'A'));
      await storeDao.insert(_makeStore(userId: 2, name: 'B'));

      final user1 = await storeDao.findByUser(1);
      final user2 = await storeDao.findByUser(2);

      expect(user1.length, 1);
      expect(user1.first.name, 'A');
      expect(user2.length, 1);
      expect(user2.first.name, 'B');
    });

    // ── search & filter ───────────────────────────────────────────────────────

    test('findByUser with name query filters correctly', () async {
      await storeDao.insert(_makeStore(name: 'Monoprix'));
      await storeDao.insert(_makeStore(name: 'Carrefour'));

      final results = await storeDao.findByUser(1, query: 'Mono');
      expect(results.length, 1);
      expect(results.first.name, 'Monoprix');
    });

    test('findByUser with type filter', () async {
      await storeDao.insert(_makeStore(name: 'Super'));
      final grocery = Store(
        userId: 1,
        name: 'Épicerie',
        type: StoreType.grocery,
        latitude: 36.8,
        longitude: 10.1,
        createdAt: DateTime.now().toIso8601String(),
      );
      await storeDao.insert(grocery);

      final supers = await storeDao.findByUser(1, type: StoreType.supermarket);
      expect(supers.every((s) => s.type == StoreType.supermarket), isTrue);
    });

    // ── OSM deduplication ─────────────────────────────────────────────────────

    test('findByOsmId returns imported OSM store', () async {
      await storeDao.insert(_makeStore(osmId: 'osm_42'));
      final found = await storeDao.findByOsmId(1, 'osm_42');
      expect(found, isNotNull);
      expect(found!.osmId, 'osm_42');
    });

    test('unique index prevents duplicate osm_id per user', () async {
      await storeDao.insert(_makeStore(osmId: 'osm_1'));
      expect(
        () => storeDao.insert(_makeStore(osmId: 'osm_1')),
        throwsException,
      );
    });

    test('two users can share the same osm_id', () async {
      await storeDao.insert(_makeStore(userId: 1, osmId: 'osm_1'));
      // should NOT throw
      final id2 = await storeDao.insert(_makeStore(userId: 2, osmId: 'osm_1'));
      expect(id2, greaterThan(0));
    });

    // ── CASCADE delete ────────────────────────────────────────────────────────

    test('deleting a store cascades to aisles', () async {
      final storeId = await storeDao.insert(_makeStore());
      await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'Fruits', sortOrder: 0));

      await storeDao.delete(storeId, 1);
      final aisles = await aisleDao.findByStore(storeId);
      expect(aisles, isEmpty);
    });

    test('deleting a store cascades to prices', () async {
      final storeId = await storeDao.insert(_makeStore());
      await priceDao.insert(StorePrice(
        storeId: storeId,
        productId: 10,
        price: 2.500,
        recordedAt: DateTime.now().toIso8601String(),
      ));

      await storeDao.delete(storeId, 1);
      final prices = await priceDao.findByStore(storeId);
      expect(prices, isEmpty);
    });

    // ── store_aisles CRUD ─────────────────────────────────────────────────────

    test('aisle insert + findByStore + order', () async {
      final storeId = await storeDao.insert(_makeStore());
      await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'Boissons', sortOrder: 2));
      await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'Fruits', sortOrder: 0));
      await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'Viandes', sortOrder: 1));

      final aisles = await aisleDao.findByStore(storeId);
      expect(aisles.map((a) => a.name).toList(),
          ['Fruits', 'Viandes', 'Boissons']);
    });

    test('updateOrders reorders aisles', () async {
      final storeId = await storeDao.insert(_makeStore());
      final id1 = await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'A', sortOrder: 0));
      final id2 = await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'B', sortOrder: 1));

      await aisleDao.updateOrders([
        StoreAisle(id: id1, storeId: storeId, name: 'A', sortOrder: 1),
        StoreAisle(id: id2, storeId: storeId, name: 'B', sortOrder: 0),
      ]);

      final aisles = await aisleDao.findByStore(storeId);
      expect(aisles.first.name, 'B');
    });

    test('delete aisle removes only that aisle', () async {
      final storeId = await storeDao.insert(_makeStore());
      final id1 = await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'A', sortOrder: 0));
      await aisleDao.insert(
          StoreAisle(storeId: storeId, name: 'B', sortOrder: 1));

      await aisleDao.delete(id1);
      final aisles = await aisleDao.findByStore(storeId);
      expect(aisles.length, 1);
      expect(aisles.first.name, 'B');
    });

    // ── store_prices CRUD ─────────────────────────────────────────────────────

    test('price insert + findByStore', () async {
      final storeId = await storeDao.insert(_makeStore());
      await priceDao.insert(StorePrice(
        storeId: storeId,
        productId: 1,
        price: 3.200,
        recordedAt: '2026-11-01T10:00:00',
      ));

      final prices = await priceDao.findByStore(storeId);
      expect(prices.length, 1);
      expect(prices.first.price, closeTo(3.200, 0.001));
    });

    test('price update changes value', () async {
      final storeId = await storeDao.insert(_makeStore());
      final priceId = await priceDao.insert(StorePrice(
        storeId: storeId,
        productId: 1,
        price: 3.200,
        recordedAt: '2026-11-01T10:00:00',
      ));

      await priceDao
          .update(StorePrice(id: priceId, storeId: storeId, productId: 1, price: 2.800, recordedAt: '2026-11-02T10:00:00'));
      final prices = await priceDao.findByStore(storeId);
      expect(prices.first.price, closeTo(2.800, 0.001));
    });

    test('price delete removes record', () async {
      final storeId = await storeDao.insert(_makeStore());
      final priceId = await priceDao.insert(StorePrice(
        storeId: storeId,
        productId: 1,
        price: 3.200,
        recordedAt: '2026-11-01T10:00:00',
      ));
      await priceDao.delete(priceId);
      final prices = await priceDao.findByStore(storeId);
      expect(prices, isEmpty);
    });

    // ── findLatestForStore ────────────────────────────────────────────────────

    test('findLatestForStore returns most recent price per product', () async {
      final storeId = await storeDao.insert(_makeStore());
      await priceDao.insert(StorePrice(
          storeId: storeId,
          productId: 1,
          price: 2.000,
          recordedAt: '2026-10-01T00:00:00'));
      await priceDao.insert(StorePrice(
          storeId: storeId,
          productId: 1,
          price: 2.500,
          recordedAt: '2026-11-01T00:00:00'));

      final latest = await priceDao.findLatestForStore(storeId, [1]);
      expect(latest[1]!.price, closeTo(2.500, 0.001));
    });

    test('findLatestForStore returns empty map for no productIds', () async {
      final storeId = await storeDao.insert(_makeStore());
      final result = await priceDao.findLatestForStore(storeId, []);
      expect(result, isEmpty);
    });

    // ── findLatestAcrossOtherStores ───────────────────────────────────────────

    test('findLatestAcrossOtherStores excludes the given store', () async {
      final s1 = await storeDao.insert(_makeStore(name: 'S1'));
      final s2 = await storeDao.insert(_makeStore(name: 'S2'));

      await priceDao.insert(StorePrice(
          storeId: s1,
          productId: 1,
          price: 2.000,
          recordedAt: '2026-11-01T00:00:00'));
      await priceDao.insert(StorePrice(
          storeId: s2,
          productId: 1,
          price: 3.000,
          recordedAt: '2026-11-01T00:00:00'));

      final otherPrices =
          await priceDao.findLatestAcrossOtherStores(s1, [1], 1);
      expect(otherPrices[1], isNotNull);
      expect(otherPrices[1]!.length, 1);
      expect(otherPrices[1]!.first, closeTo(3.000, 0.001)); // only s2
    });

    // ── findHistory ───────────────────────────────────────────────────────────

    test('findHistory returns prices in chronological order', () async {
      final storeId = await storeDao.insert(_makeStore());
      await priceDao.insert(StorePrice(
          storeId: storeId,
          productId: 1,
          price: 2.000,
          recordedAt: '2026-10-01T00:00:00'));
      await priceDao.insert(StorePrice(
          storeId: storeId,
          productId: 1,
          price: 2.500,
          recordedAt: '2026-11-01T00:00:00'));

      final history = await priceDao.findHistory(storeId, 1);
      expect(history.length, 2);
      expect(history.first.price, closeTo(2.000, 0.001));
      expect(history.last.price, closeTo(2.500, 0.001));
    });

    // ── averagePriceAcrossStores ──────────────────────────────────────────────

    test('averagePriceAcrossStores computes correctly', () async {
      final s1 = await storeDao.insert(_makeStore(name: 'S1'));
      final s2 = await storeDao.insert(_makeStore(name: 'S2'));
      await priceDao.insert(StorePrice(
          storeId: s1,
          productId: 1,
          price: 2.000,
          recordedAt: '2026-11-01T00:00:00'));
      await priceDao.insert(StorePrice(
          storeId: s2,
          productId: 1,
          price: 4.000,
          recordedAt: '2026-11-01T00:00:00'));

      final avg = await priceDao.averagePriceAcrossStores(1, 1);
      expect(avg, closeTo(3.000, 0.001));
    });

    test('averagePriceAcrossStores returns null when no prices', () async {
      await storeDao.insert(_makeStore());
      final avg = await priceDao.averagePriceAcrossStores(1, 99);
      expect(avg, isNull);
    });
  });
}
