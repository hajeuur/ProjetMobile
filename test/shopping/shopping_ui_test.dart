import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Remplace la caméra et ML Kit : renvoie un ticket déjà « lu ».
class FakeReader implements ReceiptReader {
  @override
  Future<String?> capture(PhotoSource source) async => 'ticket.jpg';

  @override
  Future<String> readText(String photoPath) async => '''
CARREFOUR LA MARSA
LAIT DEMI ECR 1L       2,700
2 x 1,350
PAIN BAGUETTE          0,800
CAFE MOULU 250G        7,900
TOTAL                 11,400
''';
}

/// Pas d'accéléromètre en test : source de secousses silencieuse.
class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

void main() {
  sqfliteFfiInit();

  testWidgets('scan d\'un ticket depuis une liste : les articles se cochent tout seuls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = DateTime.now();
    late PanierMalinApp app;
    late ShoppingService shopping;
    late Database db;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      shopping = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await seedDemoShoppingIfEmpty(shopping.repository, 1, today);
      final recipes = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: RecipesShoppingBridge(shopping),
      );
      app = PanierMalinApp(service: recipes, shopping: shopping, shakeSource: NoShakes(), receiptReader: FakeReader(), home: const ShoppingHomeScreen());
    });

    Future<void> settle() => tester.runAsync(() async {
          for (var i = 0; i < 15; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump();
          }
        });

    await tester.runAsync(() => tester.pumpWidget(app));
    await settle();
    expect(find.text('Courses de la semaine'), findsOneWidget);
    expect(find.text('9 / 9 à prendre'), findsOneWidget);

    // Détail de la liste.
    await tester.tap(find.text('Courses de la semaine'));
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Carrefour La Marsa'), findsOneWidget);
    expect(find.text('Lait'), findsOneWidget);

    // Scan du ticket (faux lecteur), puis validation.
    await tester.tap(find.text('Scanner le ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prendre le ticket en photo'));
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Validation du ticket'), findsOneWidget);
    expect(find.text('CAFE MOULU 250G'), findsOneWidget);
    expect(find.textContaining('Valider le ticket'), findsOneWidget);

    await tester.tap(find.textContaining('Valider le ticket'));
    await settle();
    await tester.pumpAndSettle();
    // Écran résumé du rapprochement.
    expect(find.text('Rapprochement avec la liste'), findsOneWidget);
    expect(find.textContaining('3 achetés'), findsOneWidget);
    expect(find.textContaining('Oubliés ('), findsOneWidget);

    await tester.tap(find.textContaining('Terminer'));
    await settle();
    await tester.pumpAndSettle();

    final items = await tester.runAsync(() async {
      final l = (await shopping.lists(status: ListStatus.active)).first;
      return shopping.items(l.id!);
    });
    final checked = items!.where((i) => i.checked).map((i) => i.label).toSet();
    expect(checked, {'Lait', 'Pain', 'Café'});
    expect(find.text('3/9'), findsOneWidget);
    await tester.runAsync(db.close);
  });

  testWidgets('budget et alertes de prix affichent les données de démo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late PanierMalinApp app;
    late Database db;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final shopping = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await seedDemoShoppingIfEmpty(shopping.repository, 1, DateTime.now());
      final recipes = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: RecipesShoppingBridge(shopping),
      );
      app = PanierMalinApp(service: recipes, shopping: shopping, shakeSource: NoShakes(), home: const ShoppingHomeScreen());
    });
    Future<void> settle() => tester.runAsync(() async {
          for (var i = 0; i < 15; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump();
          }
        });

    await tester.runAsync(() => tester.pumpWidget(app));
    await settle();

    await tester.tap(find.text('Budget').last);
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Dépenses par mois'), findsOneWidget);
    expect(find.text('sur 140,000 DT'), findsOneWidget);

    await tester.tap(find.text('Prix').last);
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Alertes de prix'), findsOneWidget);
    expect(find.text('HUILE OLIVE 1L'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
