import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/heartbeat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/gateways.dart' as recipes;
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/data/open_prices_api.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart';
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 11, 24, 12);

  late Database db;
  late ShoppingService service;
  late SilentVibrator vibrator;
  late DemoProductGateway products;
  late DemoStoreGateway stores;
  late int apiCalls;
  late bool offline;

  setUp(() async {
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    vibrator = SilentVibrator();
    products = DemoProductGateway(today: today);
    stores = DemoStoreGateway();
    apiCalls = 0;
    offline = false;
    final client = MockClient((req) async {
      apiCalls++;
      if (offline) throw http.ClientException('pas de réseau');
      if (req.url.path.endsWith('/prices')) {
        return http.Response(
          '{"items":[{"price":12.0,"currency":"TND","date":"2026-11-01","location":{"osm_name":"Carrefour"}},'
          '{"price":13.0,"currency":"TND","date":"2026-10-01"},'
          '{"price":14.0,"currency":"TND","date":"2026-09-01"},'
          '{"price":4.5,"currency":"EUR","date":"2026-10-01"}],"total":4}',
          200,
        );
      }
      return http.Response('{}', 404);
    });
    service = ShoppingModule.createService(
      db: db,
      users: DemoUserGateway(),
      products: products,
      stores: stores,
      vibrator: vibrator,
      tokens: MemoryTokenStore(),
      api: OpenPricesApi(client: client, cache: ShoppingApiCache(db)),
      clock: () => today,
    );
  });

  tearDown(() => db.close());

  test('CRUD des listes et des articles', () async {
    final id = await service.createList('Samedi');
    var l = (await service.list(id))!;
    expect(l.status, ListStatus.active);
    await service.renameList(l, 'Samedi matin');
    l = (await service.list(id))!;
    expect(l.name, 'Samedi matin');
    expect(() => service.createList('  '), throwsArgumentError);

    final a = await service.addItem(id, label: 'Tomates', quantity: 1, unit: 'kg');
    // Même article non coché : les quantités s'additionnent (pas de doublon).
    final b = await service.addItem(id, label: 'tomate', quantity: 0.5, unit: 'kg');
    expect(b, a);
    var items = await service.items(id);
    expect(items.single.quantity, 1.5);
    expect(items.single.aisle, 'Fruits et légumes');

    await service.setChecked(items.single, true);
    await service.addItem(id, label: 'Tomates', quantity: 1, unit: 'kg');
    items = await service.items(id);
    expect(items.length, 2, reason: 'un article coché ne fusionne plus');

    expect(await service.removeCheckedItems(id), 1);
    await service.archiveList(l);
    expect((await service.lists(status: ListStatus.done)).single.id, id);
    await service.deleteList(id);
    expect(await service.lists(), isEmpty);
  });

  test('alimentation automatique : ruptures (sans doublon) et recettes (via le pont)', () async {
    expect(await service.importShortages(), 2);
    expect(await service.importShortages(), 0, reason: 'déjà présentes');
    final bridge = RecipesShoppingBridge(service);
    final n = await bridge.addItems(const [
      recipes.ShoppingRequest(label: 'Pois chiches', quantity: 200, unit: 'g'),
      recipes.ShoppingRequest(label: 'Lait demi-écrémé 1L', quantity: 1, unit: 'l'),
    ]);
    expect(n, 2);
    final list = await service.activeList();
    final items = await service.items(list.id!);
    expect(items.map((i) => i.origin).toSet(), {ItemOrigin.shortage, ItemOrigin.recipe});
    expect(items.firstWhere((i) => i.label.startsWith('Lait')).quantity, 3, reason: '2 l prévus + 1 l recette');
    expect(await service.pendingItemCount(), 3);
  });

  test('ticket scanné : lecture, rapprochement, magasin, stock, budget et vibration', () async {
    final listId = await service.createList('Courses', storeId: 1);
    for (final label in ['Lait', 'Pain', 'Café', 'Harissa']) {
      await service.addItem(listId, label: label);
    }
    await service.setBudget(today, 30, alertThreshold: 80);

    const ocr = '''
CARREFOUR LA MARSA
24/11/2026 18:10
LAIT DEMI ECR 1L       2,700
2 x 1,350
PAIN BAGUETTE          0,400
CAFE MOULU 250G        7,900
LESSIVE 3KG           15,000
TOTAL                 26,000
''';
    final draft = await service.draftFromText(ocr, listId: listId);
    expect(draft.storeId, 1, reason: 'magasin reconnu dans l\'en-tête');
    expect(draft.lines.length, 4);
    expect(draft.lines.first.productId, 1, reason: 'rapproché du produit Lait (gestion 2)');
    expect(draft.isConsistent, isTrue);

    final report = await service.saveDraft(draft);
    expect(report.checkedLabels, containsAll(['Lait', 'Pain', 'Café']));
    expect(report.forgottenLabels, ['Harissa']);
    expect(report.unplannedLabels, ['LESSIVE 3KG']);
    expect(stores.recorded.length, 4, reason: 'prix payés transmis à la gestion 4');
    expect(products.purchases.length, 4, reason: 'entrées en stock (gestion 2)');

    // 26 DT sur 30 : seuil de 80 % franchi → battement rapide (le battement de
    // cœur, activé par défaut, remplace la vibration courte du seuil).
    expect(report.budget!.snapshot.level, BudgetLevel.threshold);
    expect(report.budget!.isNewLevel, isTrue);
    expect(vibrator.heartbeats, [HeartLevel.fast]);
    expect(vibrator.calls, isEmpty);

    // Un second contrôle ne revibre pas ; le dépassement, si (cœur affolé).
    await service.checkBudget();
    expect(vibrator.heartbeats.length, 1);
    final d2 = ReceiptDraft(date: today, lines: [const ReceiptLine(label: 'EAU', price: 5)]);
    final r2 = await service.saveDraft(d2);
    expect(r2.budget!.snapshot.level, BudgetLevel.exceeded);
    expect(vibrator.heartbeats, [HeartLevel.fast, HeartLevel.panic]);

    // Vibreur désactivé dans les réglages : plus de vibration.
    await service.saveSettings(const ShoppingSettings(vibration: false));
    await service.setBudget(today, 31);
    await service.checkBudget();
    expect(vibrator.heartbeats.length, 2);
    expect(vibrator.calls, isEmpty);
  });

  test('correction d\'une ligne : le total suit s\'il était la somme', () async {
    final report = await service.saveDraft(ReceiptDraft(date: today, lines: [
      const ReceiptLine(label: 'PAIN', price: 0.4),
      const ReceiptLine(label: 'YAOURT', price: 2.4),
    ]));
    var r = (await service.receipt(report.receiptId))!;
    expect(r.total, closeTo(2.8, 1e-9));
    await service.saveLine(r, r.lines.last.copyWith(price: 2.6));
    r = (await service.receipt(report.receiptId))!;
    expect(r.total, closeTo(3.0, 1e-9));
    await service.removeLine(r, r.lines.first);
    r = (await service.receipt(report.receiptId))!;
    expect(r.lines.length, 1);
    expect(r.total, closeTo(2.6, 1e-9));
    await service.deleteReceipt(r.id!);
    expect(await service.receipts(), isEmpty);
  });

  test('données de démo : statistiques et hausses de prix', () async {
    await seedDemoShoppingIfEmpty(service.repository, 1, today);
    await seedDemoShoppingIfEmpty(service.repository, 1, today); // idempotent
    expect((await service.lists()).length, 1);

    final alerts = await service.priceAlerts();
    expect(alerts.map((a) => a.key), containsAll(['p:4', 'p:6', 'p:7'])); // huile, café, tomates
    expect(alerts.every((a) => a.increase > 0.10), isTrue);

    final months = await service.monthlySpending(count: 4);
    expect(months.length, 4);
    expect(months.last.spent, closeTo(120.55, 1e-6));
    expect(months[1].spent > months[1].budget!, isTrue, reason: 'mois -2 dépassé');

    final s = await service.snapshot(today);
    expect(s.level, BudgetLevel.threshold);
    expect(s.forecastOverrun, isTrue);

    final cats = await service.categorySpending(today);
    expect(cats.keys.first, 'Viandes et poissons');
    expect(await service.averageBasket(), greaterThan(0));
    expect(await service.budgetRespect(), (2, 3));
  });

  test('Open Prices : comparaison, cache hors ligne, code-barres manquant', () async {
    const line = ReceiptLine(label: 'NUTELLA 400G', price: 13.5, productId: 13);
    final cmp = await service.compareWithCommunity(line);
    expect(cmp.sameCurrency.length, 3, reason: 'le prix en EUR est écarté');
    expect(cmp.median, 13.0);
    expect(cmp.difference, closeTo(0.0385, 1e-3));
    expect(apiCalls, 1);

    // Réponse en cache : pas de nouvel appel, et hors ligne la dernière
    // réponse connue est renvoyée.
    await service.compareWithCommunity(line);
    expect(apiCalls, 1);
    offline = true;
    final again = await service.prices.pricesFor('3017620422003');
    expect(again.length, 4);

    expect(
      () => service.compareWithCommunity(const ReceiptLine(label: 'POMMES', price: 3)),
      throwsA(isA<OpenPricesException>()),
    );
    expect(() => service.sharePrice(Receipt(id: 1, userId: 1, date: today, total: 1), line),
        throwsA(isA<OpenPricesException>()),
        reason: 'pas de compte connecté');
  });

  test('budget : message cohérent (86 % utilisé, seuil 80 %) et dépassement prévu', () async {
    await seedDemoShoppingIfEmpty(service.repository, 1, today);
    final n = await service.checkBudget();
    expect(n.snapshot.ratio, closeTo(120.55 / 140, 1e-9));
    expect(n.snapshot.projected > 140, isTrue);
    expect(n.message, contains('Seuil d\'alerte de 80 % franchi : 86 % du budget utilisé'));
    expect(n.message, contains('Dépassement prévu'));
    expect(n.isNewForecast, isTrue);
  });

  test('comparateur de magasins, alerte vers la liste, conseil et badges', () async {
    await seedDemoShoppingIfEmpty(service.repository, 1, today);
    final prices = await service.storePrices();
    expect(prices['p:7']!.cheapest.storeName, 'Carrefour La Marsa', reason: 'tomates 1,300 contre 1,500 au marché');

    final list = (await service.lists(status: ListStatus.active)).first;
    final basket = await service.compareListStores(list.id!);
    expect(basket.best, isNotNull);
    expect(basket.unknownLabels, contains('Liquide vaisselle'));

    final alerts = await service.priceAlerts();
    final huile = alerts.firstWhere((a) => a.key == 'p:4');
    expect(await service.addAlertToList(huile), 0, reason: 'l\'huile est déjà sur la liste');
    final cafe = alerts.firstWhere((a) => a.key == 'p:6');
    final cafeItem = (await service.items(list.id!)).firstWhere((i) => i.label == 'Café');
    await service.removeItem(cafeItem.id!);
    expect(await service.addAlertToList(cafe), 1);
    final items = await service.items(list.id!);
    expect(items.where((i) => i.label == 'Café moulu 250g').length, 1, reason: 'nom du produit (gestion 2)');

    final advice = await service.advice();
    expect(advice.message, contains('par jour'));

    final badges = await service.badges();
    expect(badges.firstWhere((b) => b.id == 'scanner').current, 13, reason: '13 tickets de démo');
    expect(badges.firstWhere((b) => b.id == 'budget3').current, 1, reason: 'octobre tenu, septembre dépassé');
  });

  test('badge « Zéro oubli » après une course complète', () async {
    final listId = await service.createList('Express');
    await service.addItem(listId, label: 'Pain');
    await service.saveDraft(ReceiptDraft(date: today, listId: listId, lines: [const ReceiptLine(label: 'PAIN BAGUETTE', price: 0.4)]));
    final badges = await service.badges();
    expect(badges.firstWhere((b) => b.id == 'zero_oubli').unlocked, isTrue);
  });
}
