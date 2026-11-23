import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/data/demo_recipes.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('la gestion Recettes démarre et affiche les recettes compatibles', (tester) async {
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final service = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: DemoShoppingGateway(),
      );
      await seedDemoRecipesIfEmpty(service.repository, 1);
      app = PanierMalinApp(service: service);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      // Laisse les view models charger depuis SQLite.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.text('Chakchouka'), findsOneWidget);
    // Recette aux cacahuètes masquée (allergie du foyer).
    expect(find.text('Poulet sauce cacahuète'), findsNothing);
    expect(find.textContaining('1 masquées'), findsOneWidget);
  });
}
