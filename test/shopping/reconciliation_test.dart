import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/reconciliation_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

ShoppingService _service(Database db) => ShoppingModule.createService(
      db: db,
      users: shop.DemoUserGateway(),
      products: shop.DemoProductGateway(),
      stores: shop.DemoStoreGateway(),
      vibrator: SilentVibrator(),
      tokens: MemoryTokenStore(),
    );

/// Liste : Lait, Pain, Jus d'orange, Harissa, Thon (produit 77).
/// Ticket : LAIT DEMI ECR 1L, PAIN BAGUETTE, JUS POMME 1L, THON EL MANAR, LESSIVE 3KG.
Future<(int, ReceiptDraft)> _setUp(ShoppingService s) async {
  final listId = await s.createList('Courses du samedi');
  for (final l in ['Lait', 'Pain', 'Jus d\'orange', 'Harissa']) {
    await s.addItem(listId, label: l);
  }
  await s.addItem(listId, label: 'Thon', productId: 77);
  final draft = ReceiptDraft(date: s.now, listId: listId, lines: [
    const ReceiptLine(label: 'LAIT DEMI ECR 1L', price: 1.35),
    const ReceiptLine(label: 'PAIN BAGUETTE', price: 0.2),
    const ReceiptLine(label: 'JUS POMME 1L', price: 2.9),
    const ReceiptLine(label: 'THON EL MANAR 160G', price: 3.6),
    const ReceiptLine(label: 'LESSIVE 3KG', price: 12.5),
  ]);
  return (listId, draft);
}

void main() {
  sqfliteFfiInit();

  group('Rapprochement (service)', () {
    late Database db;
    late ShoppingService s;
    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      s = _service(db);
    });
    tearDown(() => db.close());

    test('sûrs cochés + product_id rattaché, incertain à confirmer, oublié, hors liste', () async {
      final (listId, draft) = await _setUp(s);
      final rec = (await s.saveDraft(draft)).reconciliation!;
      expect(rec.listName, 'Courses du samedi');
      expect(rec.purchased.map((m) => m.itemLabel), containsAll(['Lait', 'Pain', 'Thon']));
      expect(rec.uncertain.single.itemLabel, 'Jus d\'orange');
      expect(rec.forgotten.map((i) => i.label), ['Harissa']);
      expect(rec.unplanned, ['LESSIVE 3KG']);

      final items = await s.items(listId);
      expect(items.where((i) => i.checked).map((i) => i.label).toSet(), {'Lait', 'Pain', 'Thon'});
      final lines = (await s.receipt(rec.receiptId))!.lines;
      expect(lines.firstWhere((l) => l.label.startsWith('THON')).productId, 77, reason: 'rapprochement sûr');
      expect(lines.firstWhere((l) => l.label.startsWith('JUS')).productId, isNull, reason: 'incertain : pas encore');
    });

    test('« oui » coche et est retenu : le ticket suivant ne redemande pas', () async {
      final (listId, draft) = await _setUp(s);
      final rec = (await s.saveDraft(draft)).reconciliation!;
      await s.confirmMatch(rec.uncertain.single, accepted: true);
      expect((await s.items(listId)).firstWhere((i) => i.label == 'Jus d\'orange').checked, isTrue);

      // Nouvelle liste, même article, même ligne : sûr directement.
      final l2 = await s.createList('Semaine suivante');
      await s.addItem(l2, label: 'Jus d\'orange');
      final rec2 = (await s.saveDraft(ReceiptDraft(
        date: s.now,
        listId: l2,
        lines: [const ReceiptLine(label: 'JUS POMME 1L', price: 2.9)],
      )))
          .reconciliation!;
      expect(rec2.uncertain, isEmpty);
      expect(rec2.purchased.single.itemLabel, 'Jus d\'orange');
    });

    test('« non » : plus jamais proposé', () async {
      final (_, draft) = await _setUp(s);
      final rec = (await s.saveDraft(draft)).reconciliation!;
      await s.confirmMatch(rec.uncertain.single, accepted: false);
      final l2 = await s.createList('Semaine suivante');
      await s.addItem(l2, label: 'Jus d\'orange');
      final rec2 = (await s.saveDraft(ReceiptDraft(
        date: s.now,
        listId: l2,
        lines: [const ReceiptLine(label: 'JUS POMME 1L', price: 2.9)],
      )))
          .reconciliation!;
      expect(rec2.uncertain, isEmpty);
      expect(rec2.forgotten.single.label, 'Jus d\'orange');
      expect(rec2.unplanned, ['JUS POMME 1L']);
    });

    test('oubliés gardés pour la prochaine liste (sans doublon), report automatique', () async {
      final (_, draft) = await _setUp(s);
      final rec = (await s.saveDraft(draft)).reconciliation!;
      final next = await s.keepForNextList(rec.forgotten);
      await s.keepForNextList(rec.forgotten); // deuxième fois : pas de doublon
      expect(next.name, ShoppingService.nextListName);
      final kept = await s.items(next.id!);
      expect(kept.map((i) => i.label), ['Harissa']);
      expect(kept.single.origin, ItemOrigin.forgotten);
      await s.unkeep(rec.forgotten.single);
      expect(await s.items(next.id!), isEmpty);

      // Réglage « Reporter les oubliés » : automatique.
      await s.saveSettings((await s.settings()).copyWith(carryForgotten: true));
      final (_, draft2) = await _setUp(s);
      final rec2 = (await s.saveDraft(draft2)).reconciliation!;
      expect(rec2.carriedTo, ShoppingService.nextListName);
      expect((await s.items(next.id!)).map((i) => i.label), ['Harissa']);
    });

    test('seuil réglable : sévère (90 %) = « jus pomme » ni coché ni demandé ; défaut = demandé', () async {
      await s.saveSettings((await s.settings()).copyWith(matchThreshold: 0.9));
      final (_, draft) = await _setUp(s);
      final rec = (await s.saveDraft(draft)).reconciliation!;
      expect(rec.uncertain, isEmpty, reason: '0,55 < 0,9 − 0,25');
      expect(rec.forgotten.map((i) => i.label), containsAll(['Harissa', "Jus d'orange"]));
      expect(rec.purchased.map((m) => m.itemLabel), containsAll(['Lait', 'Pain', 'Thon']));
    });

    test('liste en cours choisie toute seule (la plus récente avec des articles à prendre)', () async {
      expect(await s.currentListId(), isNull);
      final a = await s.createList('Ancienne');
      await s.addItem(a, label: 'Sel');
      final b = await s.createList('Vide');
      expect(b, isNot(a));
      expect(await s.currentListId(), a, reason: 'la liste vide est ignorée');
      await s.keepForNextList([(await s.items(a)).single]);
      expect(await s.currentListId(), a, reason: '« Prochaines courses » n\'est pas la liste en cours');
    });
  });

  testWidgets('écran résumé : « 3 achetés, 1 oublié : harissa », oui/non, garder pour la prochaine liste',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late ShoppingService s;
    late ReceiptReport report;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      s = _service(db);
      final (_, draft) = await _setUp(s);
      report = await s.saveDraft(draft);
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        shakeSource: NoShakes(),
        home: ReconciliationScreen(report: report),
      );
    });
    Future<void> go() async {
      for (var r = 0; r < 2; r++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pumpAndSettle();
      }
    }

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    expect(find.text('3 achetés, 1 oublié : harissa'), findsOneWidget);
    expect(find.text('À confirmer (1)'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNWidgets(3), reason: 'cochés après l\'animation');

    await tester.tap(find.text('Oui'));
    await go();
    expect(find.text('4 achetés, 1 oublié : harissa'), findsOneWidget);
    expect(find.text('À confirmer (1)'), findsNothing);

    await tester.scrollUntilVisible(find.text('Garder pour la prochaine liste'), 200);
    await tester.tap(find.text('Garder pour la prochaine liste'));
    await go();
    expect(find.text('Gardé pour « Prochaines courses » · annuler'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('LESSIVE 3KG'), 200);
    expect(find.text('Achats hors liste (1)'), findsOneWidget);
    final next = (await tester.runAsync(() async {
      final l = (await s.lists(status: ListStatus.active)).firstWhere((l) => l.name == 'Prochaines courses');
      return s.items(l.id!);
    }))!;
    expect(next.single.label, 'Harissa');
    await tester.runAsync(db.close);
  });
}
