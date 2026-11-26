import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/data/demo_recipes.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pas d'accéléromètre en test : source de secousses silencieuse.
class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

void main() {
  sqfliteFfiInit();

  testWidgets('l\'accueil ouvre la gestion Recettes et affiche les recettes compatibles', (tester) async {
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
      final service = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: RecipesShoppingBridge(shopping),
      );
      await seedDemoRecipesIfEmpty(service.repository, 1);
      app = PanierMalinApp(service: service, shopping: shopping, shakeSource: NoShakes());
    });

    Future<void> settle() => tester.runAsync(() async {
          // Laisse les view models charger depuis SQLite.
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });

    await tester.runAsync(() => tester.pumpWidget(app));
    await settle();
    expect(find.text('Courses et Budget'), findsOneWidget);
    await tester.tap(find.text('Recettes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle();

    expect(find.text('Chakchouka'), findsOneWidget);
    // Recette aux cacahuètes masquée (allergie du foyer).
    expect(find.text('Poulet sauce cacahuète'), findsNothing);
    expect(find.textContaining('1 masquées'), findsOneWidget);
    expect(find.byType(BackButton), findsWidgets);
    await tester.runAsync(db.close);
  });
}
