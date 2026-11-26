import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/logic/budget_report.dart';
import 'package:panier_malin/features/shopping/logic/price_alerts.dart';
import 'package:panier_malin/features/shopping/models/budget.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/services/report_builder.dart';
import 'package:panier_malin/features/shopping/services/report_sender.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/report_preview_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/budget_alert_center.dart';
import 'package:panier_malin/main.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final nov25 = DateTime(2026, 11, 25, 10);

BudgetSnapshot snap(double spent, {double? budget = 140, DateTime? today}) => BudgetSnapshot.compute(
  month: DateTime(2026, 11),
  budget: budget == null ? null : Budget(userId: 1, month: DateTime(2026, 11), amount: budget, alertThreshold: 80),
  spent: spent,
  today: today ?? nov25,
);

MonthlyReportData data(double spent, {double? budget = 140, DateTime? today}) => MonthlyReportData(
  snapshot: snap(spent, budget: budget, today: today),
  generatedAt: nov25,
  categories: const {'Épicerie salée': 60, 'Produits laitiers': 40, 'Fruits et légumes': 20.55},
  tickets: [
    Receipt(
      userId: 1,
      storeName: 'Monoprix Lafayette',
      date: DateTime(2026, 11, 15),
      total: 57.3,
      lines: const [
        ReceiptLine(label: 'CAFE MOULU 250G', price: 7.9),
        ReceiptLine(label: 'HARISSA 380G', price: 5.9, quantity: 2),
      ],
    ),
    Receipt(userId: 1, storeName: 'Carrefour La Marsa', date: DateTime(2026, 11, 8), total: 63.25),
  ],
  priceIncreases: [
    PriceAlert(
      key: 'p:6',
      label: 'CAFE MOULU 250G',
      lastPrice: 7.9,
      average: 6.85,
      lastDate: DateTime(2026, 11, 15),
      sampleCount: 3,
      storeName: 'Monoprix Lafayette',
    ),
  ],
);

final maman = AlertContact(name: 'Maman', phone: '22 123 456', consentAt: DateTime(2026, 11, 1));

void main() {
  sqfliteFfiInit();

  group('Message pré-rempli', () {
    test('exemple du cahier des charges : 86 %, 19,4 DT pour 5 jours', () {
      expect(
        reportMessage(data(120.55), maskAmounts: false),
        'PanierMalin : budget de novembre atteint à 86 %. Il reste 19,4 DT pour 5 jours. Rapport en pièce jointe.',
      );
    });

    test('montants masqués : pourcentages seulement', () {
      final m = reportMessage(data(120.55), maskAmounts: true);
      expect(
        m,
        'PanierMalin : budget de novembre atteint à 86 %. Il reste 14 % du budget pour 5 jours. '
        'Rapport en pièce jointe.',
      );
      expect(m, isNot(contains('DT')));
    });

    test('budget dépassé, dernier jour, singulier, sans budget', () {
      expect(
        reportMessage(data(145.6), maskAmounts: false),
        'PanierMalin : budget de novembre dépassé (104 %), de 5,6 DT. Encore 5 jours avant la fin du mois. '
        'Rapport en pièce jointe.',
      );
      expect(reportMessage(data(145.6), maskAmounts: true), contains('dépassé (104 %), de 4 %'));
      expect(reportMessage(data(120.55, today: DateTime(2026, 11, 29)), maskAmounts: false), contains('pour 1 jour.'));
      expect(
        reportMessage(data(120.55, today: DateTime(2026, 11, 30)), maskAmounts: false),
        contains('jusqu\'à la fin du mois'),
      );
      expect(reportMessage(data(80, budget: null), maskAmounts: false), contains('80 DT (aucun budget défini)'));
    });
  });

  group('Contenu du rapport', () {
    test('en-tête : mois, budget, dépensé, reste, % ; ton orange au seuil', () {
      final c = buildReportContent(data(120.55), const ReportOptions(maskAmounts: false));
      expect(c.title, 'Rapport budget · novembre 2026');
      expect(c.headline, '86 %');
      expect(c.tone, ReportTone.caution);
      expect(c.metrics.map((m) => m.value), ['140,000 DT', '120,550 DT', '19,450 DT', '86 %']);
      expect(c.status, contains('80 %'));
    });

    test('vert dans le budget, rouge au dépassement', () {
      expect(buildReportContent(data(40), const ReportOptions()).tone, ReportTone.good);
      expect(buildReportContent(data(145.6), const ReportOptions()).tone, ReportTone.over);
    });

    test('catégories (parts), tickets triés par date, hausse du mois, prévision', () {
      final c = buildReportContent(data(120.55), const ReportOptions(maskAmounts: false));
      expect(c.categories.first.name, 'Épicerie salée');
      expect(c.categories.fold(0.0, (a, x) => a + x.share), closeTo(1, 1e-9));
      expect(c.tickets.first.title, '08/11/2026 · Carrefour La Marsa');
      expect(c.tickets.last.title, '15/11/2026 · Monoprix Lafayette · 2 articles');
      expect(c.priceIncreases.single, startsWith('Cafe moulu 250g : +15 %'));
      expect(c.forecast.first, contains('le mois finira vers'));
    });

    test('montants masqués (défaut) : aucun montant en DT nulle part', () {
      final c = buildReportContent(data(120.55), const ReportOptions(includeItems: true));
      for (final t in c.allText) {
        expect(t, isNot(matches(RegExp(r'\d DT'))), reason: '« $t »');
      }
      expect(c.metrics.last.value, '86 %');
      expect(c.footer, contains('montants masqués'));
    });

    test('détail des articles seulement si demandé', () {
      expect(buildReportContent(data(120.55), const ReportOptions()).tickets.last.items, isEmpty);
      final items = buildReportContent(
        data(120.55),
        const ReportOptions(maskAmounts: false, includeItems: true),
      ).tickets.last.items;
      expect(items, ['Cafe moulu 250g — 7,900 DT', 'Harissa 380g ×2 — 5,900 DT']);
    });

    test('rapport test : bandeau', () {
      expect(buildReportContent(data(50), const ReportOptions(reason: ReportReason.test)).testBanner, isNotNull);
      expect(buildReportContent(data(50), const ReportOptions()).testBanner, isNull);
    });
  });

  test('PDF : polices intégrées (accents), plusieurs pages', () async {
    final fonts = ReportFonts.fromBytes(
      (await File('assets/fonts/Roboto-Regular.ttf').readAsBytes()).buffer.asByteData(),
      (await File('assets/fonts/Roboto-Bold.ttf').readAsBytes()).buffer.asByteData(),
    );
    final big = MonthlyReportData(
      snapshot: snap(145.6),
      generatedAt: nov25,
      categories: const {'Épicerie sucrée': 10},
      tickets: [
        for (var i = 1; i <= 28; i++)
          Receipt(
            userId: 1,
            storeName: 'Magasin $i',
            date: DateTime(2026, 11, i),
            total: 5.2,
            lines: const [ReceiptLine(label: 'CRÈME FRAÎCHE « ÉPAISSE »', price: 5.2)],
          ),
      ],
    );
    final bytes = await ReportBuilder(fonts)
        .build(buildReportContent(big, const ReportOptions(includeItems: true, maskAmounts: false)));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes), contains('/FontFile2'), reason: 'police TrueType intégrée');
    expect(RegExp('/Type */Page[^s]').allMatches(String.fromCharCodes(bytes)).length, greaterThan(1));
  });

  group('Seuils : une seule proposition par seuil', () {
    final on = ReportSettings(enabled: true, contact: maman);
    test('seuil puis budget, jamais deux fois', () {
      expect(reportReasonFor(BudgetLevel.threshold, on, 0), ReportReason.threshold);
      expect(reportReasonFor(BudgetLevel.threshold, on, BudgetLevel.threshold.index), isNull);
      expect(reportReasonFor(BudgetLevel.exceeded, on, BudgetLevel.threshold.index), ReportReason.budget);
      expect(reportReasonFor(BudgetLevel.exceeded, on, BudgetLevel.exceeded.index), isNull);
    });

    test('cases décochées, pas de proche, interrupteur coupé', () {
      expect(reportReasonFor(BudgetLevel.threshold, on.copyWith(atThreshold: false), 0), isNull);
      expect(
        reportReasonFor(BudgetLevel.exceeded, on.copyWith(atBudget: false), 0),
        ReportReason.threshold,
        reason: 'saut direct au-delà de 100 % : le seuil compte',
      );
      expect(reportReasonFor(BudgetLevel.threshold, on.copyWith(clearContact: true), 0), isNull);
      expect(reportReasonFor(BudgetLevel.threshold, on.copyWith(enabled: false), 0), isNull);
    });
  });

  test('numéro international et lien wa.me (texte encodé)', () {
    expect(internationalNumber('22 123 456'), '21622123456');
    expect(internationalNumber('+216 22-123-456'), '21622123456');
    expect(internationalNumber('0033 6 12 34 56 78'), '33612345678');
    expect(internationalNumber('12'), isNull);
    final link = whatsAppLink('21622123456', 'Budget à 86 % !');
    expect(link.toString(), startsWith('https://wa.me/21622123456?text='));
    expect(link.queryParameters['text'], 'Budget à 86 % !');
  });

  test('accord obligatoire : un contact sans date d\'accord est ignoré', () {
    expect(AlertContact.fromJson({'name': 'Maman', 'phone': '1'}), isNull);
    expect(AlertContact.fromJson(maman.toJson())!.firstName, 'Maman');
  });

  test('fichiers temporaires : écriture, suppression, nettoyage', () async {
    final tmp = await Directory.systemTemp.createTemp('rapports_test');
    addTearDown(() => tmp.delete(recursive: true));
    final st = ReportStorage(baseDir: () async => tmp);
    final f = await st.write('a.pdf', Uint8List.fromList([1, 2, 3]));
    expect(f.existsSync(), isTrue);
    await st.delete(f);
    expect(f.existsSync(), isFalse);
    await st.write('b.pdf', Uint8List.fromList([1]));
    await st.cleanup();
    expect(Directory('${tmp.path}/rapports').listSync(), isEmpty);
  });

  group('Service', () {
    late Database db;
    late ShoppingService s;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => nov25,
      );
      await s.setBudget(nov25, 100);
    });
    tearDown(() => db.close());

    BudgetNotice notice(BudgetSnapshot sn) => BudgetNotice(snapshot: sn, isNewLevel: true, isNewForecast: false);

    test('réglages : par défaut désactivé et montants masqués ; sans proche, pas d\'alerte', () async {
      final d = await s.reportSettings();
      expect((d.enabled, d.maskAmounts, d.includeItems, d.atThreshold, d.atBudget), (false, true, false, true, true));
      await s.saveReportSettings(d.copyWith(enabled: true));
      expect((await s.reportSettings()).enabled, isFalse);
      await s.saveReportSettings(d.copyWith(enabled: true, contact: maman, maskAmounts: false));
      final r = await s.reportSettings();
      expect((r.enabled, r.contact!.name, r.maskAmounts), (true, 'Maman', false));
    });

    test('proposition une fois par seuil (état mémorisé)', () async {
      await s.saveReportSettings(ReportSettings(enabled: true, contact: maman));
      await s.saveDraft(
        ReceiptDraft(
          date: nov25,
          lines: [const ReceiptLine(label: 'COURSES', price: 85)],
        ),
      );
      final at = await s.snapshot(nov25);
      expect((await s.reportOffer(notice(at)))!.reason, ReportReason.threshold);
      expect(await s.reportOffer(notice(at)), isNull, reason: 'déjà proposé');
      await s.saveDraft(
        ReceiptDraft(
          date: nov25,
          lines: [const ReceiptLine(label: 'COURSES', price: 20)],
        ),
      );
      final over = await s.reportOffer(notice(await s.snapshot(nov25)));
      expect((over!.reason, over.contact.firstName), (ReportReason.budget, 'Maman'));
    });

    test('données du mois : tickets avec articles, catégories ; historique des envois', () async {
      await s.saveDraft(
        ReceiptDraft(
          date: nov25,
          storeName: 'Aziza',
          lines: [
            const ReceiptLine(label: 'LAIT DEMI ECR 1L', price: 2.7),
            const ReceiptLine(label: 'TOMATES', price: 3),
          ],
        ),
      );
      final d = await s.monthlyReport(nov25);
      expect(d.tickets.single.lines, hasLength(2));
      expect(d.categories.keys, containsAll(['Produits laitiers', 'Fruits et légumes']));
      expect(d.snapshot.spent, closeTo(5.7, 1e-9));

      await s.recordReportSent(ReportReason.threshold, recipient: 'Maman', month: nov25);
      await s.recordReportSent(ReportReason.test, recipient: 'Maman', month: nov25, confirmed: false);
      final h = await s.reportHistory();
      expect(h.map((x) => (x.reason, x.confirmed)), [(ReportReason.test, false), (ReportReason.threshold, true)]);
    });
  });

  group('Écrans', () {
    late Database db;
    late ShoppingService s;
    late Directory tmp;

    Future<PanierMalinApp> setUpApp(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late PanierMalinApp app;
      await tester.runAsync(() async {
        await initializeDateFormatting('fr_FR');
        tmp = await Directory.systemTemp.createTemp('rapports_ui');
        await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
        db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
        s = ShoppingModule.createService(
          db: db,
          users: shop.DemoUserGateway(),
          products: shop.DemoProductGateway(),
          stores: shop.DemoStoreGateway(),
          vibrator: SilentVibrator(),
          tokens: MemoryTokenStore(),
          clock: () => nov25,
        );
        await s.setBudget(nov25, 140);
        await s.saveDraft(
          ReceiptDraft(
            date: nov25,
            lines: [const ReceiptLine(label: 'COURSES', price: 120.55)],
          ),
        );
        await s.saveReportSettings(ReportSettings(enabled: true, contact: maman, maskAmounts: false));
        app = PanierMalinApp(
          service: RecipesModule.createService(
            db: db,
            stock: DemoStockGateway(),
            household: DemoHouseholdGateway(),
            shopping: RecipesShoppingBridge(s),
          ),
          shopping: s,
          notifier: MemoryNotifier(),
          home: home,
        );
      });
      addTearDown(() => tmp.delete(recursive: true));
      return app;
    }

    Future<void> go(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('aperçu : message pré-rempli ; annulé = rien compté ; envoyé = historique ; fichier effacé', (
      tester,
    ) async {
      final sender = FakeSender([SendOutcome.cancelled, SendOutcome.sent]);
      final app = await setUpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportPreviewScreen(
                      month: nov25,
                      reason: ReportReason.threshold,
                      contact: maman,
                      sender: sender,
                      storage: ReportStorage(baseDir: () async => tmp),
                      livePreview: false,
                    ),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
      await tester.tap(find.text('Ouvrir'));
      await go(tester);

      expect(find.text('86 %'), findsOneWidget);
      expect(
        find.text(
          'PanierMalin : budget de novembre atteint à 86 %. Il reste 19,4 DT pour 5 jours. Rapport en pièce jointe.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Envoyer à Maman'));
      await go(tester);
      expect(find.textContaining('Envoi annulé'), findsOneWidget);
      expect(await tester.runAsync(s.reportHistory), isEmpty, reason: 'annulé : pas compté');
      expect(sender.messages.single, contains('19,4 DT'));

      await tester.tap(find.text('Envoyer à Maman'));
      for (var k = 0; k < 5 && find.byType(ReportPreviewScreen).evaluate().isNotEmpty; k++) {
        await go(tester); // historique enregistré puis fermeture de l'aperçu
      }
      final h = (await tester.runAsync(s.reportHistory))!;
      expect((h.single.recipient, h.single.reason), ('Maman', ReportReason.threshold));
      expect(find.byType(ReportPreviewScreen), findsNothing, reason: 'envoyé : l\'aperçu se ferme');
      await go(tester);
      expect(sender.files.every((f) => !f.existsSync()), isTrue, reason: 'PDF temporaires effacés');
      await tester.runAsync(db.close);
    });

    testWidgets('aucune application de partage : solution de repli (jamais d\'impasse)', (tester) async {
      final app = await setUpApp(
        tester,
        Builder(
          builder: (context) => ReportPreviewScreen(
            month: nov25,
            reason: ReportReason.export,
            sender: FakeSender([SendOutcome.noApp]),
            storage: ReportStorage(baseDir: () async => tmp),
            livePreview: false,
          ),
        ),
      );
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
      await tester.tap(find.text('Partager'));
      await go(tester);
      expect(find.text('Envoi impossible'), findsOneWidget);
      expect(find.textContaining('Aucune application'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await go(tester);
      expect(await tester.runAsync(s.reportHistory), isEmpty);
      await tester.runAsync(db.close);
    });

    testWidgets('franchissement du seuil : la bannière propose « Envoyer le rapport à Maman »', (tester) async {
      final app = await setUpApp(tester, const Scaffold(body: Text('Accueil')));
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
      final center = tester.element(find.text('Accueil')).read<BudgetAlertCenter>();
      expect(center.current, isNull);
      // Le service signale le franchissement (comme après un ticket).
      await tester.runAsync(() async {
        await s.repository.setSetting('budget_level_2026-11', '0');
        await s.checkBudget(nov25);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await go(tester);
      expect(find.text('Envoyer le rapport à Maman'), findsOneWidget);
      expect(
        await tester.runAsync(() => s.repository.setting('report_offered_2026-11')),
        '${BudgetLevel.threshold.index}',
      );
      center.dismiss();
      await go(tester);
      await tester.runAsync(db.close);
    });
  });
}

class FakeSender implements ReportSender {
  FakeSender(this.outcomes);
  final List<SendOutcome> outcomes;
  final files = <File>[];
  final messages = <String>[];

  @override
  Future<SendResult> send(File pdf, {required String message, String? subject}) async {
    expect(pdf.existsSync(), isTrue, reason: 'le PDF existe au moment du partage');
    expect(String.fromCharCodes(pdf.readAsBytesSync().take(5)), '%PDF-');
    files.add(pdf);
    messages.add(message);
    return SendResult(outcomes.removeAt(0));
  }
}
