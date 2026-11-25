import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/shake_detector.dart';
import 'package:panier_malin/features/shopping/logic/undo_history.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/shopping_lists_view_model.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Faux accéléromètre : le test déclenche les secousses à la main et peut
/// vérifier si l'écran écoute (abonnement actif) ou non.
class FakeShakeSource implements ShakeSource {
  final controller = StreamController<void>.broadcast();
  bool get listening => controller.hasListener;
  void shake() => controller.add(null);
  @override
  Stream<void> shakes() => controller.stream;
}

ShoppingService _service(Database db) => ShoppingModule.createService(
      db: db,
      users: shop.DemoUserGateway(),
      products: shop.DemoProductGateway(),
      stores: shop.DemoStoreGateway(),
      vibrator: SilentVibrator(),
      tokens: MemoryTokenStore(),
    );

void main() {
  sqfliteFfiInit();

  group('Détecteur de secousse', () {
    final t0 = DateTime(2026, 11, 25, 12);

    test('téléphone immobile (1 g) : rien ; geste franc : secousse', () {
      final d = ShakeDetector();
      expect(ShakeDetector.gForce(0, 0, 9.81), closeTo(1, 0.01));
      expect(d.add(0.3, 0.2, 9.8, t0), isFalse);
      expect(d.add(18, 22, 9.8, t0), isTrue); // ≈ 3 g
    });

    test('anti-rebond : un seul déclenchement par geste (800 ms)', () {
      final d = ShakeDetector();
      expect(d.add(25, 20, 10, t0), isTrue);
      expect(d.add(25, 20, 10, t0.add(const Duration(milliseconds: 200))), isFalse);
      expect(d.add(25, 20, 10, t0.add(const Duration(milliseconds: 790))), isFalse);
      expect(d.add(25, 20, 10, t0.add(const Duration(milliseconds: 820))), isTrue);
    });
  });

  group('Historique', () {
    ShoppingItem item(int id, {bool checked = false}) =>
        ShoppingItem(id: id, listId: 1, label: 'Lait', checked: checked);

    test('au plus 10 actions ; une nouvelle action efface le rétablissement', () {
      final h = ItemUndoHistory();
      for (var i = 0; i < 12; i++) {
        h.record(ItemAction(type: ItemActionType.toggle, before: item(i), after: item(i, checked: true)));
      }
      expect(h.length, 10);
      expect(h.lastUndoable!.before!.id, 11);
      h.undone(h.popUndo()!);
      expect(h.canRedo, isTrue);
      h.record(ItemAction(type: ItemActionType.delete, before: item(99)));
      expect(h.canRedo, isFalse);
    });

    test('phrases affichées', () {
      expect(ItemAction(type: ItemActionType.toggle, before: item(1), after: item(1, checked: true)).undoDescription,
          'lait décoché');
      expect(ItemAction(type: ItemActionType.delete, before: item(1)).undoDescription, 'lait remis dans la liste');
      expect(ItemAction(type: ItemActionType.add, after: item(1)).undoDescription, 'lait retiré de la liste');
      expect(ItemAction(type: ItemActionType.add, before: item(1), after: item(1)).undoDescription,
          'quantité de lait rétablie');
    });
  });

  group('Annuler / rétablir dans une liste', () {
    late Database db;
    late ShoppingService service;
    late ListDetailViewModel vm;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = _service(db);
      final listId = await service.createList('Test');
      vm = ListDetailViewModel(service, listId);
      await vm.load();
    });
    tearDown(() => db.close());

    ShoppingItem byLabel(String l) => vm.items.firstWhere((i) => i.label == l);

    test('cocher puis annuler, puis rétablir', () async {
      await vm.add('Lait', quantity: 2, unit: 'L');
      await vm.toggle(byLabel('Lait'));
      expect((await service.items(vm.listId)).single.checked, isTrue);
      final a = await vm.undo();
      expect(a!.undoDescription, 'lait décoché');
      expect(byLabel('Lait').checked, isFalse);
      await vm.redo();
      expect(byLabel('Lait').checked, isTrue);
    });

    test('suppression annulée : même position, même état ; rétablir la refait', () async {
      await vm.add('Pain');
      await vm.add('Lait');
      await vm.add('Café');
      await vm.toggle(byLabel('Lait'));
      await vm.remove(byLabel('Lait'));
      expect(vm.items.map((i) => i.label), ['Pain', 'Café']);
      await vm.undo();
      expect(vm.items.map((i) => i.label), ['Pain', 'Lait', 'Café']);
      expect(byLabel('Lait').checked, isTrue);
      await vm.redo();
      expect(vm.items.any((i) => i.label == 'Lait'), isFalse);
      // Rétablir puis annuler encore : l'identifiant suivi reste le bon.
      await vm.undo();
      expect(byLabel('Lait').checked, isTrue);
    });

    test('ajout annulé ; ajout fusionné : la quantité d\'avant revient', () async {
      await vm.add('Tomates', quantity: 1, unit: 'kg');
      await vm.add('tomate', quantity: 0.5, unit: 'kg'); // fusion
      expect(byLabel('Tomates').quantity, 1.5);
      expect((await vm.undo())!.undoDescription, 'quantité de tomates rétablie');
      expect(byLabel('Tomates').quantity, 1);
      expect((await vm.undo())!.undoDescription, 'tomates retiré de la liste');
      expect(vm.items, isEmpty);
      await vm.redo();
      expect(byLabel('Tomates').quantity, 1);
    });

    test('rien à annuler', () async {
      expect(await vm.undo(), isNull);
      expect(vm.canUndo, isFalse);
    });
  });

  testWidgets('secouer pour annuler : snackbar, Rétablir, « Rien à annuler », menu, réglage, écran masqué',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final shakes = FakeShakeSource();
    late Database db;
    late ShoppingService service;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = _service(db);
      await seedDemoShoppingIfEmpty(service.repository, 1, DateTime.now());
      final recipes = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: RecipesShoppingBridge(service),
      );
      app = PanierMalinApp(service: recipes, shopping: service, shakeSource: shakes, home: const ShoppingHomeScreen());
    });

    Future<void> go() async {
      for (var r = 0; r < 2; r++) {
        await tester.runAsync(() async {
          for (var i = 0; i < 6; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
      }
    }

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    expect(shakes.listening, isFalse, reason: 'liste des listes : pas d\'écoute');

    await tester.tap(find.text('Courses de la semaine'));
    await go();
    expect(shakes.listening, isTrue, reason: 'détail visible : écoute du capteur');

    // Rien encore fait dans cet écran.
    shakes.shake();
    await go();
    expect(find.text('Rien à annuler'), findsOneWidget);

    // Cocher « Lait », secouer : annulé, puis Rétablir.
    await tester.tap(find.byType(Checkbox).first);
    await go();
    expect(find.text('1/9'), findsOneWidget);
    shakes.shake();
    await go();
    expect(find.text('Dernière action annulée : lait décoché'), findsOneWidget);
    expect(find.text('0/9'), findsOneWidget);
    await tester.tap(find.text('Rétablir'));
    await go();
    expect(find.text('1/9'), findsOneWidget);
    expect(find.text('Action rétablie : lait coché'), findsOneWidget);

    // Supprimer, puis annuler par le menu (émulateur, sans secouer).
    await tester.tap(find.descendant(
      of: find.ancestor(of: find.text('Pain'), matching: find.byType(CheckboxListTile)),
      matching: find.byTooltip('Supprimer'),
    ));
    await go();
    expect(find.text('Pain'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await go();
    await tester.tap(find.text('Annuler la dernière action'));
    await go();
    expect(find.text('Pain'), findsOneWidget);
    expect(find.text('Dernière action annulée : pain remis dans la liste'), findsOneWidget);

    // Un écran par-dessus (Comparateur) : l'abonnement est libéré, puis repris.
    await tester.tap(find.byTooltip('Comparer les magasins'));
    await go();
    expect(shakes.listening, isFalse, reason: 'écran masqué : capteur coupé');
    await tester.tap(find.byTooltip('Retour'));
    await go();
    expect(shakes.listening, isTrue);

    // Réglage désactivé : l'écran n'écoute plus.
    await tester.runAsync(() async => service.saveSettings((await service.settings()).copyWith(shakeToUndo: false)));
    await tester.tap(find.byTooltip('Comparer les magasins'));
    await go();
    await tester.tap(find.byTooltip('Retour'));
    await go();
    expect(shakes.listening, isFalse);

    // Quitter l'écran libère l'abonnement (dispose).
    await tester.runAsync(() async => service.saveSettings((await service.settings()).copyWith(shakeToUndo: true)));
    await tester.tap(find.byTooltip('Comparer les magasins'));
    await go();
    await tester.tap(find.byTooltip('Retour'));
    await go();
    expect(shakes.listening, isTrue);
    await tester.tap(find.byTooltip('Retour'));
    await go();
    expect(shakes.listening, isFalse);

    await tester.runAsync(db.close);
  });
}
