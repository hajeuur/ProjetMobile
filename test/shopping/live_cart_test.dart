import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_products.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/logic/live_cart_budget.dart';
import 'package:panier_malin/features/shopping/models/budget.dart';
import 'package:panier_malin/features/shopping/models/live_cart.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/live_cart_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/live_cart_view_model.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final today = DateTime(2026, 11, 20, 10);
Budget budget100() => Budget(userId: 1, month: DateTime(2026, 11), amount: 100, alertThreshold: 80);

void main() {
  sqfliteFfiInit();

  group('Budget « si je passe en caisse »', () {
    test('phrases : il te restera / tu dépasseras / pas de budget', () {
      expect(CartBudget(spentMonth: 70, cartTotal: 21.6, budget: budget100()).sentence,
          'Si tu passes en caisse, il te restera 8,4 DT');
      expect(CartBudget(spentMonth: 90, cartTotal: 13.2, budget: budget100()).sentence,
          'Si tu passes en caisse, tu dépasseras ton budget de 3,2 DT');
      expect(const CartBudget(spentMonth: 10, cartTotal: 23.4).sentence, 'Panier : 23,4 DT (pas de budget défini ce mois-ci)');
    });

    test('franchissement : seuil puis budget ; retirer un article n\'alerte pas', () {
      CartBudget b(double cart) => CartBudget(spentMonth: 70, cartTotal: cart, budget: budget100());
      expect(crossedLevel(b(5), b(9)), isNull, reason: '79 %');
      expect(crossedLevel(b(9), b(12)), BudgetLevel.threshold);
      expect(crossedLevel(b(12), b(25)), isNull, reason: 'toujours au seuil');
      expect(crossedLevel(b(25), b(31)), BudgetLevel.exceeded);
      expect(crossedLevel(b(31), b(5)), isNull);
    });
  });

  group('Panier (view model)', () {
    late Database db;
    late ShoppingService s;
    late SilentVibrator vibrator;
    late LiveCartViewModel vm;
    late int listId;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      vibrator = SilentVibrator();
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: vibrator,
        tokens: MemoryTokenStore(),
        clock: () => today,
      );
      await s.setBudget(today, 100);
      await s.saveSettings((await s.settings()).copyWith(heartbeat: false));
      await s.saveDraft(ReceiptDraft(date: today, lines: [const ReceiptLine(label: 'COURSES', price: 70)]));
      listId = await s.createList('Samedi');
      await s.addItem(listId, label: 'Nutella');
      vm = LiveCartViewModel(s, ShoppingModule.createProductScan(s));
      await vm.load();
    });
    tearDown(() => db.close());

    test('code-barres → prix Open Prices (démo), article de la liste coché ; retirer / annuler', () async {
      final r = await vm.addBarcode(DemoProducts.nutella);
      expect(r.added, isTrue);
      final item = vm.items.single;
      expect(item.label, 'Nutella');
      expect(item.priceSource, 'moyenne Open Prices');
      expect(item.unitPrice, closeTo(13.033, 0.001));
      expect(item.listItemId, isNotNull);
      expect((await s.items(listId)).single.checked, isTrue, reason: 'coché sur la liste');

      final removed = await vm.remove(0);
      expect((await s.items(listId)).single.checked, isFalse, reason: 'retiré : redevient à prendre');
      await vm.undoRemove(0, removed);
      expect(vm.items, hasLength(1));
      expect((await s.items(listId)).single.checked, isTrue);
      expect(await s.liveCart(), hasLength(1), reason: 'panier sauvegardé');
    });

    test('prix introuvable (spaghetti : prix en euros seulement) → saisie demandée', () async {
      final r = await vm.addBarcode(DemoProducts.spaghetti);
      expect(r.added, isFalse);
      expect(r.name, 'Spaghetti n°5');
      expect(vm.items, isEmpty);
    });

    test('jauge en direct : alerte douce et vibration au seuil puis au budget, quantité +/-', () async {
      await vm.add(const LiveCartItem(label: 'Huile', unitPrice: 5));
      expect(vm.alert, isNull, reason: '75 %');
      await vm.setQuantity(0, 2); // 80 %
      expect(vm.alert, BudgetLevel.threshold);
      expect(vibrator.calls, [BudgetLevel.threshold]);
      expect(vm.budget!.sentence, 'Si tu passes en caisse, il te restera 20 DT');
      await vm.add(const LiveCartItem(label: 'Viande', unitPrice: 25)); // 105 %
      expect(vm.alert, BudgetLevel.exceeded);
      expect(vibrator.calls.last, BudgetLevel.exceeded);
      await vm.setQuantity(1, 0);
      expect(vm.items, hasLength(1), reason: 'quantité 0 : retiré');
    });

    test('passer en caisse : brouillon de ticket avec les lignes du panier', () async {
      await vm.add(const LiveCartItem(label: 'Huile', unitPrice: 5, quantity: 2));
      await vm.add(const LiveCartItem(label: 'Pain', unitPrice: 0.2));
      final d = vm.draft();
      expect(d.lines.map((l) => (l.label, l.quantity, l.price)), [('Huile', 2.0, 10.0), ('Pain', 1.0, 0.2)]);
      expect(d.total, closeTo(10.2, 1e-9));
    });
  });

  testWidgets('écran : saisie, jauge, glisser pour retirer + Annuler, passer en caisse → ticket enregistré', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late ShoppingService s;
    late PanierMalinApp app;
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
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        notifier: MemoryNotifier(),
        home: const LiveCartScreen(),
      );
    });
    Future<void> go() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    expect(find.text('Panier vide'), findsOneWidget);

    Future<void> addManual(String name, String price) async {
      await tester.tap(find.text('Sans code'));
      await go();
      await tester.enterText(find.widgetWithText(TextField, 'Produit'), name);
      await tester.enterText(find.widgetWithText(TextField, 'Prix'), price);
      await tester.tap(find.text('Ajouter'));
      await go();
    }

    await addManual('Huile olive', '18,5');
    await addManual('Pain', '0,4');
    expect(find.text('Panier : 18,900 DT'), findsOneWidget);
    expect(find.text('Si tu passes en caisse, il te restera 81,1 DT.'), findsOneWidget);
    expect(find.text('Passer en caisse · 18,900 DT'), findsOneWidget);

    await tester.drag(find.text('Pain'), const Offset(-600, 0));
    await go();
    expect(find.text('Panier : 18,500 DT'), findsOneWidget);
    // L'ancien message « ajouté » termine sa sortie, puis « retiré … Annuler » s'affiche.
    for (var k = 0; k < 4 && find.text('Annuler').evaluate().isEmpty; k++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 600)); // fin de l'animation d'entrée
    await tester.tap(find.text('Annuler'));
    await go();
    expect(find.text('Panier : 18,900 DT'), findsOneWidget);

    await tester.tap(find.text('Passer en caisse · 18,900 DT'));
    await go();
    expect(find.text('Validation du ticket'), findsOneWidget);
    await tester.tap(find.textContaining('Valider le ticket'));
    await go();
    // Enregistrement, bilan (pas de liste en cours : dialogue « OK »), puis panier vidé.
    for (var k = 0; k < 10 && find.text('Panier vide').evaluate().isEmpty; k++) {
      if (find.text('OK').evaluate().isNotEmpty) await tester.tap(find.text('OK'));
      await go();
    }
    expect(find.text('Panier vide'), findsOneWidget);
    final receipts = (await tester.runAsync(s.receipts))!;
    expect(receipts.single.total, closeTo(18.9, 1e-9));
    await tester.runAsync(db.close);
  });
}
