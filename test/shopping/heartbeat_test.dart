import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/heartbeat.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/beating_heart.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pas d'accéléromètre en test.
class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

void main() {
  test('niveaux selon le remplissage : 50 / 80 / 100 %', () {
    expect(HeartLevel.of(0.49), HeartLevel.calm);
    expect(HeartLevel.of(0.5), HeartLevel.slow);
    expect(HeartLevel.of(0.79), HeartLevel.slow);
    expect(HeartLevel.of(0.8), HeartLevel.fast);
    expect(HeartLevel.of(0.99), HeartLevel.fast);
    expect(HeartLevel.of(1.0), HeartLevel.panic);
    expect(HeartLevel.of(1.3), HeartLevel.panic);
  });

  test('sous 50 % : aucun battement', () {
    final p = heartbeatFor(0.3);
    expect(p.isEmpty, isTrue);
    expect(p.timings, isEmpty);
  });

  test('« tou-toum » : 2 impulsions par battement, rythme de plus en plus rapide sur 5 s', () {
    final slow = heartbeatFor(0.6);
    final fast = heartbeatFor(0.9);
    final panic = heartbeatFor(1.1);
    expect(slow.beats, 5, reason: '60/min sur 5 s');
    expect(fast.beats, 8, reason: '100/min sur 5 s');
    expect(panic.beats, 13, reason: '150/min : un battement toutes les 400 ms, le dernier à 4,8 s');
    for (final p in [slow, fast, panic]) {
      expect(p.total, lessThanOrEqualTo(const Duration(seconds: 5)));
      expect(p.timings.length, p.intensities.length, reason: 'une intensité par segment (Android)');
      expect(p.pulses.length, p.beats * 2);
    }
  });

  test('intensité croissante, pauses à 0', () {
    final slow = heartbeatFor(0.6);
    final panic = heartbeatFor(1.1);
    int peak(HeartbeatPattern p) => p.intensities.reduce((a, b) => a > b ? a : b);
    expect(peak(panic), greaterThan(peak(slow)));
    expect(peak(panic), 255);
    for (var i = 0; i < slow.timings.length; i += 2) {
      expect(slow.intensities[i], 0, reason: 'segment pair = pause');
    }
  });

  test('battements réguliers : un « tou » par période ; animation synchronisée', () {
    final fast = heartbeatFor(0.9);
    final starts = [for (var i = 0; i < fast.pulses.length; i += 2) fast.pulses[i].start.inMilliseconds];
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i] - starts[i - 1], 600, reason: '60 000 / 100 bpm');
    }
    expect(heartPulseAt(fast, const Duration(milliseconds: 45)), greaterThan(0.5), reason: 'cœur gonflé au « tou »');
    expect(heartPulseAt(fast, const Duration(milliseconds: 500)), 0, reason: 'au repos entre deux battements');
  });

  testWidgets('le cœur se gonfle au « tou », au repos sinon', (tester) async {
    final p = heartbeatFor(0.9);
    await tester.pumpWidget(MaterialApp(home: Center(child: BeatingHeart(level: HeartLevel.fast, pattern: p))));
    double scale() => tester.widget<Transform>(find.byType(Transform).first).transform.getMaxScaleOnAxis();
    await tester.pump(const Duration(milliseconds: 45));
    expect(scale(), greaterThan(1.2));
    await tester.pump(const Duration(milliseconds: 455)); // 500 ms : entre deux battements
    expect(scale(), closeTo(1, 0.01));
    await tester.pumpAndSettle();
  });

  group('Écrans', () {
    sqfliteFfiInit();
    late Database db;
    late SilentVibrator vibrator;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      vibrator = SilentVibrator();
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
          vibrator: vibrator,
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
          notifier: MemoryNotifier(),
          home: const ShoppingHomeScreen(),
        );
      });
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
    }

    testWidgets('Budget : « Écouter (5 s) » au rythme du remplissage (86 % : rapide)', (tester) async {
      await open(tester);
      await tester.tap(find.text('Budget'));
      await go(tester);
      await tester.ensureVisible(find.text('Écouter (5 s)'));
      await go(tester);
      expect(find.text('Battement rapide (100 battements/min)'), findsOneWidget);
      await tester.tap(find.text('Écouter (5 s)'));
      await go(tester);
      expect(vibrator.heartbeats, [HeartLevel.fast]);
      await tester.runAsync(db.close);
    });

    testWidgets('Réglages : interrupteur et « Tester le battement » (affolé)', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Réglages'));
      await go(tester);
      expect(find.text('Vibreur battement de cœur'), findsOneWidget);
      await tester.tap(find.text('Tester le battement'));
      await go(tester);
      await tester.tap(find.text('Affolé'));
      await go(tester);
      await tester.tap(find.text('Jouer 5 s'));
      await go(tester);
      expect(vibrator.heartbeats, [HeartLevel.panic]);
      await tester.tap(find.text('Fermer'));
      await go(tester);
      await tester.tap(find.text('Vibreur battement de cœur'));
      await go(tester);
      expect(find.text('Tester le battement'), findsNothing, reason: 'désactivé : plus de bouton de test');
      await tester.runAsync(db.close);
    });
  });
}

Future<void> go(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(seconds: 6)); // laisse finir le battement de 5 s
  }
}
