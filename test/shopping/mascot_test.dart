import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/mascot.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/logic/mascot_messages.dart';
import 'package:panier_malin/features/shopping/models/budget.dart';

BudgetSnapshot snap(double spent, {DateTime? today}) => BudgetSnapshot.compute(
      month: DateTime(2026, 11),
      budget: Budget(userId: 1, month: DateTime(2026, 11), amount: 100, alertThreshold: 80),
      spent: spent,
      today: today ?? DateTime(2026, 11, 10),
    );

void main() {
  test('5 humeurs selon le budget', () {
    expect(moodFor(snap(30)), MascotMood.happy);
    expect(moodFor(snap(60)), MascotMood.calm);
    expect(moodFor(snap(85)), MascotMood.worried);
    expect(moodFor(snap(105)), MascotMood.panicked);
    expect(moodFor(snap(70, today: DateTime(2026, 11, 29))), MascotMood.proud, reason: 'fin de mois dans le budget');
  });

  test('commentaire de ticket : magasin, montant, ton selon la taille', () {
    final m = MascotMessages(random: Random(1));
    final big = m.receipt(total: 57, store: 'Monoprix');
    expect(big, contains('57 DT chez Monoprix'));
    expect(MascotMessages.receiptBig.map((t) => t.replaceAll('{t}', '57 DT').replaceAll('{at}', ' chez Monoprix')), contains(big));
    expect(MascotMessages.receiptSmall.map((t) => t.replaceAll('{t}', '8,5 DT').replaceAll('{at}', '')),
        contains(m.receipt(total: 8.5)));
  });

  test('plusieurs variantes par situation, et elles varient', () {
    expect(MascotMessages.receiptBig.length, greaterThanOrEqualTo(2));
    for (final pool in [...MascotMessages.eventPools.values, ...MascotMessages.greetingPools.values]) {
      expect(pool.length, greaterThanOrEqualTo(2));
    }
    final m = MascotMessages(random: Random(42));
    final seen = {for (var i = 0; i < 30; i++) m.receipt(total: 57, store: 'Monoprix')};
    expect(seen.length, greaterThan(1));
  });

  test('jamais culpabilisant', () {
    for (final t in MascotMessages.all) {
      for (final w in mascotForbiddenWords) {
        expect(t.toLowerCase(), isNot(contains(w)), reason: '« $t » contient « $w »');
      }
    }
  });

  test('réactions aux événements, priorité du plus marquant', () {
    final m = MascotMessages(random: Random(3));
    expect(m.event(MascotEvent.priceIncrease, name: 'Le café', pct: 15), contains('15 %'));
    expect(m.event(MascotEvent.shrinkflation, name: 'Le café'), contains('Le café'));
    expect(
      mainEvent(
        budgetExceeded: false,
        threshold: true,
        shrinkflation: true,
        priceIncrease: true,
        forgotten: true,
        badge: false,
        perfectTrip: false,
      ),
      MascotEvent.threshold,
    );
    expect(
      mainEvent(
        budgetExceeded: false,
        threshold: false,
        shrinkflation: false,
        priceIncrease: false,
        forgotten: false,
        badge: false,
        perfectTrip: false,
      ),
      isNull,
    );
    expect(moodForEvent(MascotEvent.badge), MascotMood.proud);
    expect(moodForEvent(MascotEvent.budgetExceeded), MascotMood.panicked);
  });

  test('bulle d\'accueil : pourcentage et montant par jour', () {
    final m = MascotMessages(random: Random(0));
    final t = m.greeting(MascotMood.worried, percent: 86, perDay: 3.9);
    expect(t, contains('86 %'));
    expect(t.contains('{'), isFalse, reason: 'aucun champ non rempli');
  });

  group('Service', () {
    sqfliteFfiInit();
    late Database db;
    late ShoppingService s;
    var now = DateTime(2026, 11, 10, 18);

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      now = DateTime(2026, 11, 10, 18);
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => now,
      );
      s.mascotMessages = MascotMessages(random: Random(7));
      await s.setBudget(now, 100);
    });
    tearDown(() => db.close());

    Future<ReceiptReport> buy(double price, {String? store}) => s.saveDraft(
          ReceiptDraft(date: now, storeName: store, lines: [ReceiptLine(label: 'COURSES', price: price)]),
        );

    test('commente chaque ticket (magasin, montant) puis réagit au seuil', () async {
      final r1 = await buy(30, store: 'Aziza');
      expect(r1.mascot!.text, contains('30 DT chez Aziza'));
      expect(r1.mascot!.mood, MascotMood.happy);

      final r2 = await buy(57, store: 'Monoprix'); // 87 % : seuil franchi
      expect(r2.mascot!.text, contains('57 DT chez Monoprix'));
      expect(r2.mascot!.mood, MascotMood.worried);
      expect(MascotMessages.eventPools[MascotEvent.threshold]!.any((t) => r2.mascot!.text.endsWith(t)), isTrue);
    });

    test('bulle : dernier commentaire pendant 24 h, puis accueil selon l\'humeur ; interrupteur', () async {
      await buy(60, store: 'Carrefour');
      final b = (await s.mascotBubble())!;
      expect(b.text, contains('60 DT chez Carrefour'));

      now = now.add(const Duration(hours: 25));
      final g = (await s.mascotBubble())!;
      expect(g.mood, MascotMood.calm, reason: '60 % du budget');
      expect(g.text, contains('60 %'));

      await s.saveSettings((await s.settings()).copyWith(mascot: false));
      expect(await s.mascotBubble(), isNull);
      expect((await buy(5)).mascot, isNull, reason: 'désactivée : pas de commentaire');
    });
  });

  testWidgets('la mascotte change d\'humeur avec une animation qui se termine', (tester) async {
    Widget app(MascotMood m) => MaterialApp(home: Scaffold(body: MascotCard(mood: m, text: 'Bonjour')));
    await tester.pumpWidget(app(MascotMood.happy));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Malin, la mascotte, content'), findsOneWidget);
    await tester.pumpWidget(app(MascotMood.panicked));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(); // pas d'animation en boucle
    expect(find.bySemanticsLabel('Malin, la mascotte, paniqué'), findsOneWidget);
  });

  testWidgets('accueil Courses : bulle de la mascotte', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await seedDemoShoppingIfEmpty(s.repository, 1, DateTime.now());
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        shakeSource: NoShakes(),
        home: const ShoppingHomeScreen(),
      );
    });
    await tester.runAsync(() => tester.pumpWidget(app));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
    expect(find.byType(MalinMascot), findsWidgets);
    expect(find.textContaining('du budget'), findsWidgets);
    await tester.runAsync(db.close);
  });
}

class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}
