import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/pack_format.dart';
import 'package:panier_malin/features/shopping/logic/shrinkflation.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/shrinkflation_tab.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PackPurchase buy(String label, double price, DateTime date, {String? store}) =>
    PackPurchase(lineId: null, date: date, label: label, price: price, format: parsePackFormat(label), store: store);

ShoppingService _service(Database db, {DateTime? today}) => ShoppingModule.createService(
      db: db,
      users: shop.DemoUserGateway(),
      products: shop.DemoProductGateway(),
      stores: shop.DemoStoreGateway(),
      vibrator: SilentVibrator(),
      tokens: MemoryTokenStore(),
      clock: today == null ? null : () => today,
    );

void main() {
  sqfliteFfiInit();

  test('café 250 g puis 200 g au même prix : « Même prix, 20 % de café en grains en moins »', () {
    final r = detectShrinkflation({
      'l:cafe grain': [
        buy('CAFE EN GRAINS 250G', 9.8, DateTime(2026, 7, 22), store: 'Monoprix'),
        buy('CAFE EN GRAINS 200G', 9.8, DateTime(2026, 9, 21), store: 'Carrefour'),
      ],
    });
    final a = r.alerts.single;
    expect(a.sentence, 'Même prix, 20 % de café en grains en moins');
    expect(a.before.pricePerBig, closeTo(39.2, 1e-9));
    expect(a.after.pricePerBig, closeTo(49.0, 1e-9));
    expect(a.perBigIncrease, closeTo(0.25, 1e-9), reason: '+25 % au kilo');
    expect(r.toConfirm, isEmpty);
  });

  test('format plus petit ET prix en hausse ; élision « d\'huile »', () {
    final a = detectShrinkflation({
      'k': [buy('HUILE OLIVE 1L', 16.0, DateTime(2026, 1, 1)), buy('HUILE OLIVE 900ML', 16.5, DateTime(2026, 3, 1))],
    }).alerts.single;
    expect(a.sentence, "Prix en hausse de 3 % et 10 % d'huile olive en moins");
  });

  test('pas d\'alerte : prix baissé avec le format, format plus grand, même format', () {
    final r = detectShrinkflation({
      'a': [buy('CAFE 250G', 8.0, DateTime(2026, 1, 1)), buy('CAFE 200G', 6.4, DateTime(2026, 2, 1))],
      'b': [buy('LAIT 1L', 1.3, DateTime(2026, 1, 1)), buy('LAIT 1,5L', 1.3, DateTime(2026, 2, 1))],
      'c': [buy('SUCRE 1KG', 1.4, DateTime(2026, 1, 1)), buy('SUCRE 1KG', 1.6, DateTime(2026, 2, 1))],
    });
    expect(r.alerts, isEmpty, reason: 'une simple hausse de prix relève des alertes de prix');
  });

  test('format illisible : on n\'affirme rien, on demande confirmation', () {
    final r = detectShrinkflation({
      'l:cafe moulu': [
        buy('CAFE MOULU 250G', 6.8, DateTime(2026, 8, 4)),
        buy('CAFE MOULU', 6.9, DateTime(2026, 9, 3)), // ticket sans format
      ],
      'l:poulet': [buy('POULET ENTIER', 14.5, DateTime(2026, 8, 4)), buy('POULET ENTIER', 15.2, DateTime(2026, 10, 19))],
    });
    expect(r.alerts, isEmpty);
    final c = r.toConfirm.single;
    expect(c.name, 'café moulu');
    expect(c.known.label, '250 g', reason: 'proposition : même format que l\'achat le plus proche');
  });

  test('mesures différentes (masse / volume) : pas comparées', () {
    final r = detectShrinkflation({
      'k': [buy('CREME 500G', 3.0, DateTime(2026, 1, 1)), buy('CREME 20CL', 3.0, DateTime(2026, 2, 1))],
    });
    expect(r.alerts, isEmpty);
  });

  group('Base de données', () {
    final today = DateTime(2026, 11, 25, 10);

    test('démo : café en grains 250 g → 200 g au même prix ; format enregistré sur les lignes', () async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = _service(db, today: today);
      await seedDemoShoppingIfEmpty(s.repository, 1, today);
      final r = await s.shrinkflation();
      final a = r.alerts.single;
      expect(a.sentence, 'Même prix, 20 % de café en grains en moins');
      expect(a.before.store, 'Monoprix Lafayette');
      expect(a.after.store, 'Carrefour La Marsa');
      final lines = await s.repository.linesSince(1, DateTime(2000));
      final nutella = lines.firstWhere((x) => x.line.label == 'NUTELLA 400G').line;
      expect(nutella.packSize, 400);
      expect(nutella.packUnit, 'g');
      await db.close();
    });

    test('format à confirmer : autre format saisi, puis « je ne sais pas »', () async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = _service(db, today: today);
      Future<void> purchase(String label, double price, DateTime d) =>
          s.saveDraft(ReceiptDraft(date: d, lines: [ReceiptLine(label: label, price: price)]));
      await purchase('THE VERT 100G', 4.5, DateTime(2026, 9, 1));
      await purchase('THE VERT', 4.5, DateTime(2026, 10, 1)); // format absent du ticket
      var r = await s.shrinkflation();
      expect(r.alerts, isEmpty, reason: 'rien n\'est affirmé');
      final c = r.toConfirm.single;
      expect(c.known.label, '100 g');

      // L'utilisateur précise : 80 g → shrinkflation confirmée.
      await s.confirmPackFormat(c.purchase.lineId!, parsePackFormat('80G'));
      r = await s.shrinkflation();
      expect(r.toConfirm, isEmpty);
      expect(r.alerts.single.sentence, 'Même prix, 20 % de thé vert en moins');

      // « Je ne sais pas » : plus de question, pas d'alerte inventée.
      await purchase('THE VERT', 4.6, DateTime(2026, 11, 1));
      final c2 = (await s.shrinkflation()).toConfirm.single;
      await s.confirmPackFormat(c2.purchase.lineId!, null);
      expect((await s.shrinkflation()).toConfirm, isEmpty);
      await db.close();
    });

    test('migration v2 → v3 : colonnes ajoutées, format lu dans les lignes existantes', () async {
      final dir = await Directory.systemTemp.createTemp('pm_migr');
      final path = '${dir.path}/v2.db';
      // Base « version 2 » telle qu'installée avant cette phase (receipt_lines sans format).
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE receipts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, '
                'store_id INTEGER, store_name TEXT, date TEXT NOT NULL, total REAL NOT NULL, photo TEXT, list_id INTEGER)');
            await db.execute('CREATE TABLE receipt_lines (id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_id INTEGER NOT NULL, '
                'label TEXT NOT NULL, product_id INTEGER, barcode TEXT, quantity REAL NOT NULL DEFAULT 1, '
                'price REAL NOT NULL, category TEXT)');
          },
        ),
      );
      await old.insert('receipts', {'user_id': 1, 'date': '2026-11-01T10:00:00', 'total': 7.9});
      await old.insert('receipt_lines', {'receipt_id': 1, 'label': 'CAFE MOULU 250G', 'price': 6.9});
      await old.insert('receipt_lines', {'receipt_id': 1, 'label': 'POULET ENTIER', 'price': 1.0});
      await old.close();

      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      expect(await db.getVersion(), 3);
      final rows = await db.query('receipt_lines', orderBy: 'id');
      expect(rows[0]['pack_size'], 250);
      expect(rows[0]['pack_unit'], 'g');
      expect(rows[1]['pack_size'], isNull);
      expect(rows[1]['pack_confirmed'], 0);
      await db.close();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('onglet : carte avant / après, prix au kilo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = _service(db);
      await seedDemoShoppingIfEmpty(s.repository, 1, DateTime.now());
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        home: const Scaffold(body: ShrinkflationTab()),
      );
    });
    await tester.runAsync(() => tester.pumpWidget(app));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Même prix, 20 % de café en grains en moins'), findsOneWidget);
    expect(find.text('+25 % au kilo'), findsOneWidget);
    expect(find.text('250 g'), findsOneWidget);
    expect(find.text('200 g'), findsOneWidget);
    expect(find.text('39,200 DT/kg'), findsOneWidget);
    expect(find.text('49,000 DT/kg'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
