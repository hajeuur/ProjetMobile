import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_products.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/store_mode.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/store_mode_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ShoppingItem it(String label, String aisle, {int pos = 0, bool checked = false}) =>
    ShoppingItem(id: pos, listId: 1, label: label, aisle: aisle, position: pos, checked: checked);

void main() {
  sqfliteFfiInit();

  group('Regroupement par rayon', () {
    final items = [
      it('Lait', 'Produits laitiers', pos: 0),
      it('Tomates', 'Fruits et légumes', pos: 1, checked: true),
      it('Eau', 'Boissons', pos: 2),
      it('Yaourt', 'Produits laitiers', pos: 3),
    ];

    test('ordre du magasin ; rayons inconnus du magasin après, dans l\'ordre par défaut', () {
      final g = groupForStore(items, StoreSort.store, aisleOrder: ['Boissons', 'Produits laitiers']);
      expect(g.map((x) => x.aisle), ['Boissons', 'Produits laitiers', 'Fruits et légumes']);
      expect(g[1].items.map((i) => i.label), ['Lait', 'Yaourt']);
    });

    test('rayons par défaut (ordre du magasin ignoré) ; ordre d\'ajout sans regroupement', () {
      expect(groupForStore(items, StoreSort.category, aisleOrder: ['Boissons']).map((x) => x.aisle), [
        'Fruits et légumes',
        'Produits laitiers',
        'Boissons',
      ]);
      final added = groupForStore(items, StoreSort.added).single;
      expect(added.aisle, allItemsTitle);
      expect(added.items.map((i) => i.label), ['Lait', 'Tomates', 'Eau', 'Yaourt']);
    });

    test('« restants » : les cochés et les rayons terminés disparaissent ; les cochés ne bougent pas sinon', () {
      final g = groupForStore(items, StoreSort.category, remainingOnly: true);
      expect(g.map((x) => x.aisle), ['Produits laitiers', 'Boissons']);
      final all = groupForStore(items, StoreSort.category);
      expect(all.first.complete, isTrue);
      expect(all.first.done, 1);
      expect(groupForStore([it('Pain', 'Boulangerie', checked: true)], StoreSort.store, remainingOnly: true), isEmpty);
    });

    test('progression : pluriel correct', () {
      expect(storeProgressLabel(12, 18), '12/18 articles');
      expect(storeProgressLabel(0, 1), '0/1 article');
    });
  });

  group('Ordre des rayons appris', () {
    test('première course : l\'ordre de visite devient l\'ordre du magasin', () {
      expect(mergeAisleOrder([], ['Boissons', 'Laitiers', 'Boissons']), ['Boissons', 'Laitiers']);
    });

    test('un seul rayon visité : rien à apprendre', () {
      expect(mergeAisleOrder(['A', 'B'], ['B']), ['A', 'B']);
    });

    test('une visite rapproche les rayons sans tout bouleverser', () {
      // E visité en premier remonte au milieu ; B visité en dernier descend d'un cran.
      expect(mergeAisleOrder(['A', 'B', 'C', 'D', 'E'], ['E', 'B']), ['A', 'E', 'C', 'B', 'D']);
    });

    test('ordre mémorisé d\'abord, puis les rayons de la gestion 4', () {
      expect(effectiveAisleOrder(['Boissons'], ['Fruits et légumes', 'boissons', 'Surgelés']), [
        'Boissons',
        'Fruits et légumes',
        'Surgelés',
      ]);
    });
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
      );
    });
    tearDown(() => db.close());

    test('ordre par magasin : enregistré, appris, séparé d\'un magasin à l\'autre', () async {
      expect(await s.savedAisleOrder(2), isEmpty);
      await s.learnAisleOrder(2, ['Boissons', 'Produits laitiers']);
      expect(await s.savedAisleOrder(2), ['Boissons', 'Produits laitiers']);
      expect(await s.savedAisleOrder(1), isEmpty);
      await s.saveAisleOrder(null, ['Boulangerie', 'Boissons']);
      expect(await s.savedAisleOrder(null), ['Boulangerie', 'Boissons']);
    });

    test('tri et contraste gardés ; interrupteur Mode magasin', () async {
      expect((await s.storeModePrefs()).sort, StoreSort.store);
      await s.saveStoreModePrefs(sort: StoreSort.added, dark: true);
      final p = await s.storeModePrefs();
      expect((p.sort, p.dark), (StoreSort.added, true));
      expect((await s.settings()).storeMode, isTrue);
      await s.saveSettings((await s.settings()).copyWith(storeMode: false));
      expect((await s.settings()).storeMode, isFalse);
    });

    test('scan en mode magasin : coche l\'article de CETTE liste, pas de la liste en cours', () async {
      final a = await s.createList('A');
      await s.addItem(a, label: 'Nutella');
      final b = await s.createList('B');
      await s.addItem(b, label: 'Nutella');
      await s.checkListItemFor('Nutella', listId: a);
      expect((await s.items(a)).single.checked, isTrue);
      expect((await s.items(b)).single.checked, isFalse);
    });
  });

  testWidgets('écran : rayons du magasin, coche + haptique, restants, scan → panier, tri, sombre, apprentissage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    late Database db;
    late ShoppingService s;
    late PanierMalinApp app;
    late int listId;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await s.setBudget(s.now, 100);
      listId = await s.createList('Samedi');
      await s.setListStore((await s.list(listId))!, 2); // Monoprix : Boissons d'abord
      await s.addItem(listId, label: 'Lait', aisle: 'Produits laitiers');
      await s.addItem(listId, label: 'Tomates', aisle: 'Fruits et légumes');
      await s.addItem(listId, label: 'Eau', aisle: 'Boissons');
      await s.addItem(listId, label: 'Nutella', aisle: 'Épicerie sucrée');
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        notifier: MemoryNotifier(),
        // Réseau coupé : les données de démo prennent le relais (mode hors ligne).
        productScan: ShoppingModule.createProductScan(s, client: MockClient((_) async => http.Response('', 503))),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoreModeScreen(
                      listId: listId,
                      scanner: (_, {required demoMode}) async => DemoProducts.nutella,
                    ),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
    });
    Future<void> go() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    double y(String text) => tester.getTopLeft(find.text(text).first).dy;

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    await tester.tap(find.text('Ouvrir'));
    await go();

    expect(find.text('0/4 articles'), findsOneWidget);
    // Ordre de Monoprix : Boissons, Épicerie sucrée, Produits laitiers, Fruits et légumes.
    expect(y('Boissons'), lessThan(y('Épicerie sucrée')));
    expect(y('Épicerie sucrée'), lessThan(y('Produits laitiers')));
    await tester.drag(find.byType(ListView), const Offset(0, -300)); // gros boutons : le dernier rayon est plus bas
    await go();
    expect(y('Produits laitiers'), lessThan(y('Fruits et légumes')));
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await go();

    await tester.tap(find.text('Eau'));
    await go();
    expect(find.text('1/4 articles'), findsOneWidget);
    expect(haptics, isNotEmpty, reason: 'retour haptique à la coche');
    expect((await tester.runAsync(() => s.items(listId)))!.firstWhere((i) => i.label == 'Eau').checked, isTrue);

    await tester.tap(find.text('Restants'));
    await go();
    expect(find.text('Eau'), findsNothing);

    // Scan (faux lecteur) : Nutella au prix Open Prices de démo, coché sur la liste.
    await tester.tap(find.text('Scanner'));
    // Réseau coupé : on laisse passer le délai d'attente avant le repli hors ligne.
    for (var k = 0; k < 8 && find.text('2/4 articles').evaluate().isEmpty; k++) {
      await go();
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.text('2/4 articles'), findsOneWidget);
    expect(find.textContaining('Panier : 13,033 DT'), findsOneWidget);
    expect(find.text('Nutella'), findsNothing, reason: 'coché : masqué par « Restants »');

    // Tri : ordre d'ajout, sans regroupement.
    await tester.tap(find.byTooltip('Tri des rayons'));
    await go();
    await tester.tap(find.text('Ordre d\'ajout'));
    await go();
    expect(find.text(allItemsTitle), findsOneWidget);

    // Contraste sombre.
    await tester.tap(find.byTooltip('Affichage sombre contrasté'));
    await go();
    expect(Theme.of(tester.element(find.text('Restants'))).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);

    // Sortie : Boissons puis Épicerie sucrée visités → ordre appris pour Monoprix.
    await tester.tap(find.byType(BackButton)); // « Retour » (app en français)
    await go();
    expect(find.byType(StoreModeScreen), findsNothing);
    List<String>? learned;
    for (var k = 0; k < 5 && (learned?.isEmpty ?? true); k++) {
      await go(); // enregistrement à la sortie, en arrière-plan
      learned = await tester.runAsync(() => s.savedAisleOrder(2));
    }
    expect(learned, ['Boissons', 'Épicerie sucrée']);
    await tester.runAsync(db.close);
  });
}
