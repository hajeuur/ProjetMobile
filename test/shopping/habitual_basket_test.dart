import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/habitual_basket.dart';
import 'package:panier_malin/features/shopping/logic/price_alerts.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/habitual_basket_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 11, 25);
var _receipt = 0;

/// Un achat : produit, magasin, jours avant aujourd'hui, prix unitaire, quantité.
PricePoint buy(String key, String store, int daysAgo, double unit, {double qty = 1, int? receiptId}) => PricePoint(
      key: key,
      label: key.toUpperCase(),
      date: now.subtract(Duration(days: daysAgo)),
      unitPrice: unit,
      storeName: store,
      receiptId: receiptId ?? ++_receipt,
      quantity: qty,
    );

void main() {
  sqfliteFfiInit();

  group('Panier habituel', () {
    test('3 achats sur 3 mois avec quantité moyenne ; 2 achats ou trop anciens : exclus', () {
      final b = buildHabitualBasket([
        buy('lait', 'Carrefour', 5, 1.35, qty: 2),
        buy('lait', 'Monoprix', 30, 1.40, qty: 3),
        buy('lait', 'Carrefour', 60, 1.30, qty: 1),
        buy('cafe', 'Carrefour', 10, 7.0),
        buy('cafe', 'Monoprix', 40, 7.9),
        buy('cafe', 'Monoprix', 120, 7.5), // hors des 90 jours
        buy('sucre', 'Carrefour', 3, 1.4),
      ], now: now);
      expect(b.items.map((i) => i.key), ['lait']);
      expect(b.items.single.avgQuantity, 2);
      expect(b.items.single.purchases, 3);
    });

    test('deux lignes du même ticket = un seul achat', () {
      final b = buildHabitualBasket([
        buy('pain', 'Carrefour', 1, 0.2, receiptId: 900),
        buy('pain', 'Carrefour', 1, 0.2, receiptId: 900),
        buy('pain', 'Monoprix', 8, 0.25),
        buy('pain', 'Carrefour', 15, 0.2),
      ], now: now);
      expect(b.items.single.purchases, 3);
      expect(b.items.single.avgQuantity, closeTo(4 / 3, 1e-9), reason: '2 baguettes le même jour');
    });
  });

  group('Coût par magasin', () {
    // Panier : lait (2 en moyenne), café, harissa — vus chez Carrefour et Monoprix.
    final points = [
      buy('lait', 'Carrefour', 5, 1.35, qty: 2),
      buy('lait', 'Monoprix', 30, 1.50, qty: 2),
      buy('lait', 'Carrefour', 60, 1.30, qty: 2),
      buy('cafe', 'Carrefour', 10, 6.85),
      buy('cafe', 'Monoprix', 40, 7.90),
      buy('cafe', 'Monoprix', 70, 7.50),
      buy('harissa', 'Carrefour', 12, 2.75),
      buy('harissa', 'Carrefour', 45, 2.80),
      buy('harissa', 'Carrefour', 80, 2.70),
      buy('lait', 'Aziza', 20, 1.30, qty: 2), // Aziza : 1 prix connu sur 3
    ];

    test('dernier prix du magasin, sinon moyenne « estimation » ; classement ; phrases', () {
      final b = buildHabitualBasket(points, now: now);
      expect(b.status, BasketStatus.ok);
      expect(b.stores.map((s) => s.storeName), ['Carrefour', 'Monoprix']);
      final carrefour = b.cheapest!;
      // Lait 2 × 1,35 (dernier prix Carrefour) + café 6,85 + harissa 2,75 (dernier).
      expect(carrefour.total, closeTo(2 * 1.35 + 6.85 + 2.75, 1e-9));
      expect(carrefour.estimatedCount, 0);
      final monoprix = b.dearest!;
      expect(monoprix.estimatedCount, 1, reason: 'harissa jamais payée chez Monoprix');
      final harissa = monoprix.lines.firstWhere((l) => l.item.key == 'harissa');
      expect(harissa.estimated, isTrue);
      expect(harissa.unitPrice, 2.75, reason: 'moyenne des magasins connus (Carrefour seul)');
      expect(b.saving, closeTo(monoprix.total - carrefour.total, 1e-9));
      // Monoprix : lait 2 × 1,50 (son dernier prix) + café 7,90 (le plus récent) + harissa estimée 2,75.
      expect(monoprix.total, closeTo(2 * 1.50 + 7.90 + 2.75, 1e-9));
      expect(b.sentence, 'Ton panier habituel coûte 12,3 DT chez Carrefour, 13,7 DT chez Monoprix');
      expect(b.savingSentence, startsWith('Tu économises 1,'));
      expect(b.savingSentence, endsWith('DT par rapport à Monoprix'));
    });

    test('magasin avec trop peu de prix connus : non classé', () {
      final b = buildHabitualBasket(points, now: now);
      expect(b.excludedStores, ['Aziza']);
    });

    test('données insuffisantes : pas de produit régulier, un seul magasin', () {
      expect(buildHabitualBasket([buy('lait', 'Carrefour', 1, 1.3)], now: now).status, BasketStatus.notEnoughPurchases);
      final one = buildHabitualBasket([
        for (var d in [1, 20, 40]) buy('lait', 'Carrefour', d, 1.3),
      ], now: now);
      expect(one.status, BasketStatus.notEnoughStores);
      expect(one.sentence, '');
    });
  });

  group('Données de démo', () {
    late Database db;
    late ShoppingService service;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => DateTime(2026, 11, 25, 10),
      );
      await seedDemoShoppingIfEmpty(service.repository, 1, DateTime(2026, 11, 25, 10));
    });
    tearDown(() => db.close());

    test('6 produits habituels, Carrefour vs Monoprix, Aziza et Marché non classés', () async {
      final b = await service.habitualBasket();
      expect(b.status, BasketStatus.ok);
      expect(b.items, hasLength(6));
      expect(b.stores.map((s) => s.storeName).toSet(), {'Carrefour La Marsa', 'Monoprix Lafayette'});
      expect(b.excludedStores, containsAll(['Aziza Ennasr', 'Marché central']));
      expect(b.cheapest!.storeName, 'Carrefour La Marsa');
      expect(b.saving, greaterThan(0));
    });
  });

  testWidgets('écran : phrase, barres, détail au toucher, interrupteur', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late ShoppingService service;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await seedDemoShoppingIfEmpty(service.repository, 1, DateTime.now());
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(service),
        ),
        shopping: service,
        home: const Scaffold(body: SingleChildScrollView(child: HabitualBasketCard())),
      );
    });
    Future<void> go() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pumpAndSettle();
      }
    }

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    expect(find.text('Panier type par magasin'), findsOneWidget);
    expect(find.textContaining('Ton panier habituel coûte'), findsOneWidget);
    expect(find.textContaining('Tu économises'), findsOneWidget);
    expect(find.textContaining('estimation'), findsNothing);

    expect(find.textContaining(' × '), findsNothing);
    await tester.tap(find.text('Monoprix Lafayette'));
    await go();
    expect(find.textContaining(' × '), findsNWidgets(6), reason: 'détail : 6 produits, quantité × prix');

    await tester.ensureVisible(find.text('Voir le détail'));
    await go();
    await tester.tap(find.text('Voir le détail'));
    await go();
    expect(find.text('Panier type par magasin'), findsOneWidget, reason: "titre de l'écran détaillé");
    final list = find.descendant(of: find.byType(HabitualBasketScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Mon panier habituel'), 300, scrollable: list);
    await tester.scrollUntilVisible(find.textContaining('Non classés (trop peu de prix connus)'), 300, scrollable: list);
    expect(find.textContaining('6 achats').evaluate().length + find.textContaining('3 achats').evaluate().length,
        greaterThan(0));
    await tester.runAsync(db.close);
  });
}
