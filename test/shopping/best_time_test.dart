import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/best_time.dart';
import 'package:panier_malin/features/shopping/logic/price_alerts.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/best_time_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PricePoint p(DateTime d, double price, String store) =>
    PricePoint(key: 'p:7', label: 'TOMATES', date: d, unitPrice: price, storeName: store);

/// Tomates de la démo : moins chères en début de mois au Marché central.
final tomatoes = [
  p(DateTime(2026, 6, 3), 0.95, 'Marché central'),
  p(DateTime(2026, 6, 24), 1.35, 'Carrefour La Marsa'),
  p(DateTime(2026, 7, 5), 1.00, 'Marché central'),
  p(DateTime(2026, 7, 22), 1.40, 'Monoprix Lafayette'),
  p(DateTime(2026, 8, 17), 1.20, 'Marché central'),
  p(DateTime(2026, 9, 3), 1.35, 'Monoprix Lafayette'),
  p(DateTime(2026, 10, 19), 1.30, 'Carrefour La Marsa'),
  p(DateTime(2026, 11, 2), 1.50, 'Marché central'),
];

void main() {
  test('début de mois + Marché central réunis : « (-13 %) », basé sur 8 achats', () {
    final i = analyseBestTime('p:7', 'les tomates', tomatoes);
    expect(i.status, BestTimeStatus.ok);
    expect(i.monthPart, MonthPart.start);
    expect(i.store, 'Marché central');
    expect(i.sentence, 'Pour les tomates, c\'est moins cher en début de mois au Marché central (-13 %)');
    expect(i.basis, 'basé sur 8 achats');
    final store = i.dimensions.firstWhere((d) => d.dimension == Dimension.store);
    expect(store.saving, closeTo(1 - 1.1625 / 1.35, 1e-9));
  });

  test('moins de 6 achats : on ne conclut pas', () {
    final i = analyseBestTime('p:7', 'les tomates', tomatoes.take(5).toList());
    expect(i.status, BestTimeStatus.notEnoughData);
    expect(i.sentence, contains('5 sur 6 nécessaires'));
  });

  test('écart < 5 % : « le prix varie peu », honnêtement', () {
    final flat = [
      for (var m = 1; m <= 8; m++) p(DateTime(2026, m, m.isEven ? 3 : 25), 1.30 + (m % 3) * 0.02, m.isEven ? 'A' : 'B'),
    ];
    final i = analyseBestTime('k', 'le lait', flat);
    expect(i.status, BestTimeStatus.noDifference);
    expect(i.sentence, contains('moins de 5 %'));
  });

  test('magasin seul ; jour de la semaine seul', () {
    // Même moment du mois partout, Aziza nettement moins chère.
    final byStore = [
      for (var m = 1; m <= 6; m++) p(DateTime(2026, m, 15), m.isEven ? 2.0 : 2.4, m.isEven ? 'Aziza' : 'Carrefour'),
    ];
    final s = analyseBestTime('k', 'le café', byStore);
    expect(s.store, 'Aziza');
    expect(s.monthPart, isNull);
    expect(s.sentence, 'Pour le café, c\'est moins cher chez Aziza (-17 %)');

    // Samedis (7, 14, 21, 28 novembre 2026) moins chers, même magasin.
    final byDay = [
      for (final d in [7, 14, 21, 28]) p(DateTime(2026, 11, d), 3.0, 'Carrefour'),
      for (final d in [3, 11, 19, 26]) p(DateTime(2026, 11, d), 3.4, 'Carrefour'),
    ];
    final w = analyseBestTime('k', 'le poulet', byDay);
    expect(w.weekday, DateTime.saturday);
    expect(w.sentence, 'Pour le poulet, c\'est moins cher le samedi (-12 %)');
  });

  test('un groupe d\'un seul achat ne peut pas être « le meilleur »', () {
    final pts = [
      p(DateTime(2026, 1, 15), 0.5, 'Promo unique'), // un seul achat, très bas
      for (var m = 2; m <= 7; m++) p(DateTime(2026, m, 15), 1.3, 'Carrefour'),
    ];
    final i = analyseBestTime('k', 'le pain', pts);
    expect(i.store, isNot('Promo unique'));
  });

  test('rappel : prochain début de mois / prochain samedi, à 9 h', () {
    final i = analyseBestTime('p:7', 'les tomates', tomatoes);
    expect(nextReminder(i, DateTime(2026, 11, 25, 20)), DateTime(2026, 12, 1, 9));
    expect(nextReminder(i, DateTime(2026, 12, 1, 8)), DateTime(2026, 12, 1, 9));
    final byDay = analyseBestTime('k', 'le poulet', [
      for (final d in [7, 14, 21, 28]) p(DateTime(2026, 11, d), 3.0, 'Carrefour'),
      for (final d in [3, 11, 19, 26]) p(DateTime(2026, 11, d), 3.4, 'Carrefour'),
    ]);
    expect(nextReminder(byDay, DateTime(2026, 11, 25, 10)), DateTime(2026, 11, 28, 9));
    expect(i.reminderText, contains('13 % moins cher au Marché central'));
  });

  group('Données de démo', () {
    sqfliteFfiInit();

    Future<(Database, ShoppingService)> open(DateTime today) async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final service = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => today,
      );
      await seedDemoShoppingIfEmpty(service.repository, 1, today);
      return (db, service);
    }

    test('tomates : début de mois au Marché central ; les autres produits en observation', () async {
      final (db, service) = await open(DateTime(2026, 11, 25, 10));
      final all = await service.bestTimes();
      final tomatoes = all.first;
      expect(tomatoes.status, BestTimeStatus.ok);
      expect(tomatoes.sentence, "Pour « Tomates », c'est moins cher en début de mois au Marché central (-13 %)");
      expect(tomatoes.basis, 'basé sur 8 achats');
      expect(all.where((i) => i.status == BestTimeStatus.ok), hasLength(1), reason: 'pas de conclusion inventée');
      expect(all.any((i) => i.status == BestTimeStatus.notEnoughData), isTrue);
      await db.close();
    });
  });

  testWidgets('écran : conclusion, fiabilité, mini-graphiques, « Me rappeler »', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final notifier = MemoryNotifier();
    late Database db;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final service = ShoppingModule.createService(
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
        notifier: notifier,
        home: const BestTimeScreen(),
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
    expect(find.textContaining('en début de mois au Marché central'), findsOneWidget);
    expect(find.text('basé sur 8 achats'), findsOneWidget);
    expect(find.text('Fiabilité moyenne'), findsOneWidget);
    expect(find.textContaining('Selon le magasin'), findsOneWidget);
    expect(find.text('Début'), findsOneWidget, reason: 'barres du moment du mois');

    await tester.tap(find.text('Me rappeler'));
    await go();
    final (body, at) = notifier.scheduled.single;
    expect(body, contains('13 % moins cher au Marché central'));
    expect(at.day, 1, reason: 'prochain début de mois');
    expect(at.hour, 9);
    expect(find.textContaining('Rappel prévu le'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
