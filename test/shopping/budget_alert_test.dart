import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/logic/heartbeat.dart';
import 'package:panier_malin/features/shopping/models/budget.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/budget_alert_banner.dart';
import 'package:panier_malin/features/shopping/ui/budget_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/budget_alert_center.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final today = DateTime(2026, 11, 20, 10);

BudgetSnapshot snap(double amount, double spent, {int threshold = 80, DateTime? on}) => BudgetSnapshot.compute(
      month: DateTime(2026, 11),
      budget: Budget(userId: 1, month: DateTime(2026, 11), amount: amount, alertThreshold: threshold),
      spent: spent,
      today: on ?? today,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Phrase intelligente', () {
    test('exemple du cahier : « tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour »', () {
      // 87,2 DT dépensés au 20 novembre sur 126,2 DT : 130,8 prévus, 3,9 DT/jour pour 10 jours.
      expect(budgetSentence(snap(126.2, 87.2)), 'À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour.');
    });

    test('budget dépassé, seuil sans dépassement prévu, tout va bien', () {
      expect(budgetSentence(snap(100, 112.5)), startsWith('Budget dépassé de 12,5 DT.'));
      // 165 DT le 28 : 176,8 prévus (< 200), 35 DT pour 2 jours.
      expect(budgetSentence(snap(200, 165, on: DateTime(2026, 11, 28))),
          'Il te reste 35 DT, soit 17,5 DT/jour pour finir le mois dans le budget.');
      expect(budgetSentence(snap(300, 60)), contains('tu finiras le mois à 90 DT, sous ton budget'));
    });

    test('montants courts', () {
      expect(shortDt(4.6), '4,6 DT');
      expect(shortDt(3.871), '3,9 DT');
      expect(shortDt(0.35), '0,35 DT');
      expect(shortDt(12.0), '12 DT');
      expect(shortDt(12.54), '12,5 DT');
      expect(shortDt(240.4), '240 DT');
    });
  });

  test('couleur de la jauge : vert, transition douce, orange au seuil, rouge au budget', () {
    final green = BudgetGauge.colorFor(0.5, 0.8);
    final orange = BudgetGauge.colorFor(0.8, 0.8);
    final red = BudgetGauge.colorFor(1.0, 0.8);
    expect(green, Colors.green.shade600);
    expect(orange, Colors.orange.shade700);
    expect(red, Colors.red.shade600);
    final between = BudgetGauge.colorFor(0.77, 0.8);
    expect(between, isNot(green));
    expect(between, isNot(orange), reason: 'mélange vert → orange juste avant le seuil');
    expect(BudgetGauge.colorFor(1.3, 0.8), red);
  });

  test('motifs : court au seuil, long au budget', () {
    expect(vibrationDuration(BudgetLevel.threshold), lessThan(const Duration(milliseconds: 600)));
    expect(vibrationDuration(BudgetLevel.exceeded), greaterThan(const Duration(seconds: 2)));
  });

  group('Alerte à l\'enregistrement d\'un ticket', () {
    late Database db;
    late ShoppingService s;
    late SilentVibrator vibrator;
    late List<BudgetNotice> alerts;

    Future<void> open({bool hasVibrator = true, bool heartbeat = false}) async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      vibrator = SilentVibrator(hasVibrator: hasVibrator);
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: vibrator,
        tokens: MemoryTokenStore(),
        clock: () => today,
      );
      alerts = [];
      s.budgetAlerts.listen(alerts.add);
      await s.setBudget(today, 100);
      // Phase 3 testée seule : vibration courte / longue (sans battement de cœur).
      await s.saveSettings((await s.settings()).copyWith(heartbeat: heartbeat));
    }

    Future<int> buy(double price) async =>
        (await s.saveDraft(ReceiptDraft(date: today, lines: [ReceiptLine(label: 'COURSES', price: price)]))).receiptId;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    tearDown(() => db.close());

    test('seuil puis budget : une alerte par franchissement, motif court puis long', () async {
      await open();
      await buy(50);
      await settle();
      expect(alerts, isEmpty);
      expect(vibrator.calls, isEmpty);

      await buy(35); // 85 % : seuil de 80 % franchi
      await settle();
      expect(alerts.single.snapshot.level, BudgetLevel.threshold);
      expect(alerts.single.previousRatio, closeTo(0.5, 1e-9), reason: 'la jauge s\'anime de 50 % à 85 %');
      expect(alerts.single.vibrated, isTrue);
      expect(vibrator.calls, [BudgetLevel.threshold]);

      await buy(5); // 90 % : toujours au seuil → pas de nouvelle alerte
      await settle();
      expect(alerts, hasLength(1));

      await buy(15); // 105 % : budget dépassé
      await settle();
      expect(alerts.last.snapshot.level, BudgetLevel.exceeded);
      expect(alerts.last.title, 'Budget dépassé');
      expect(vibrator.calls, [BudgetLevel.threshold, BudgetLevel.exceeded]);
    });

    test('état mémorisé : rien à la réouverture ; ticket supprimé puis nouveau franchissement → nouvelle alerte', () async {
      await open();
      final id = await buy(85);
      await settle();
      expect(alerts, hasLength(1));
      await s.checkBudget(); // ouverture de l'écran, redémarrage…
      await settle();
      expect(alerts, hasLength(1));

      await s.deleteReceipt(id); // retour sous le seuil
      await buy(82);
      await settle();
      expect(alerts, hasLength(2));
    });

    test('interrupteur Vibreur coupé / appareil sans vibreur : alerte visuelle seulement', () async {
      await open();
      await s.saveSettings((await s.settings()).copyWith(vibration: false));
      await buy(85);
      await settle();
      expect(vibrator.calls, isEmpty);
      expect(alerts.single.vibrated, isFalse);
      expect(alerts.single.vibrationEnabled, isFalse);
      await db.close();

      await open(hasVibrator: false);
      await buy(85);
      await settle();
      expect(vibrator.calls, [BudgetLevel.threshold], reason: 'hasVibrator vérifié par le vibreur');
      expect(alerts.single.vibrated, isFalse);
      expect(alerts.single.vibrationEnabled, isTrue);
    });

    test('interrupteur « Alertes de budget » coupé : ni bannière ni vibration, niveau quand même mémorisé', () async {
      await open();
      await s.saveSettings((await s.settings()).copyWith(budgetAlerts: false));
      await buy(85);
      await settle();
      expect(alerts, isEmpty);
      expect(vibrator.calls, isEmpty);
      await s.saveSettings((await s.settings()).copyWith(budgetAlerts: true));
      await buy(1);
      await settle();
      expect(alerts, isEmpty, reason: 'pas de rafale à la réactivation : seuil déjà franchi');
    });

    test('battement de cœur : une fois par palier 50 / 80 / 100 %, rythme selon le remplissage', () async {
      await open(heartbeat: true);
      await buy(40);
      await settle();
      expect(vibrator.heartbeats, isEmpty, reason: 'sous 50 % : cœur calme');

      await buy(15); // 55 %
      await settle();
      expect(vibrator.heartbeats, [HeartLevel.slow]);
      expect(alerts.single.showBanner, isFalse, reason: '50 % : pas de bannière, juste le cœur');
      expect(alerts.single.heartbeat!.level, HeartLevel.slow);

      await buy(5); // 60 % : même palier
      await settle();
      expect(vibrator.heartbeats, hasLength(1));

      await buy(25); // 85 %
      await settle();
      expect(vibrator.heartbeats, [HeartLevel.slow, HeartLevel.fast]);
      expect(alerts.last.showBanner, isTrue);
      expect(vibrator.calls, isEmpty, reason: 'le battement remplace la vibration courte');

      await buy(20); // 105 %
      await settle();
      expect(vibrator.heartbeats.last, HeartLevel.panic);
      expect(alerts.last.heartbeat!.level, HeartLevel.panic);
    });

    test('app en arrière-plan : notification locale, bannière au retour', () async {
      await open();
      final notifier = MemoryNotifier();
      final center = BudgetAlertCenter(s, notifier);
      center.didChangeAppLifecycleState(AppLifecycleState.paused);
      await buy(85);
      await settle();
      await settle();
      expect(notifier.shown.single.$1, 'Seuil d\'alerte de 80 % atteint');
      expect(notifier.shown.single.$2, contains('85 % du budget utilisé'));
      expect(center.current, isNull);

      center.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(center.current?.title, 'Seuil d\'alerte de 80 % atteint');
      expect(center.vibrating, isFalse, reason: 'la vibration a déjà eu lieu');

      // Au premier plan : bannière directe, animation pendant la vibration.
      center.dismiss();
      await buy(20);
      await settle();
      expect(center.current?.level, BudgetLevel.exceeded);
      expect(center.vibrating, isTrue);
      expect(notifier.shown, hasLength(1));
      center.dispose();
    });
  });

  testWidgets('bannière : jauge, phrase, téléphone qui vibre le temps du motif', (tester) async {
    final notice = BudgetNotice(
      snapshot: snap(126.2, 101),
      isNewLevel: true,
      isNewForecast: true,
      previousRatio: 0.6,
      vibrated: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BudgetAlertBanner(alert: BudgetAlert(notice), vibrating: true, onClose: () {}),
      ),
    ));
    expect(find.text('Seuil d\'alerte de 80 % atteint'), findsOneWidget);
    expect(find.textContaining('80 % du budget utilisé'), findsOneWidget);
    expect(find.textContaining('À ce rythme, tu dépasseras de'), findsOneWidget);
    expect(find.text('Vibration courte…'), findsOneWidget);
    expect(find.byIcon(Icons.smartphone), findsOneWidget);
    await tester.pumpAndSettle(); // l'animation s'arrête d'elle-même
    expect(find.byType(BudgetGauge), findsOneWidget);
  });
}
