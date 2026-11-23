import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'features/recipes/data/demo_recipes.dart';
import 'features/recipes/integration/demo_gateways.dart';
import 'features/recipes/recipes_module.dart';
import 'features/recipes/services/recipe_service.dart';
import 'features/recipes/ui/recipes_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final db = await AppDatabase.open();

  // TODO(intégration) : remplacer les passerelles de démo par les services
  // des gestions 1 (foyer), 2 (stock) et 5 (courses).
  final household = DemoHouseholdGateway();
  final service = RecipesModule.createService(
    db: db,
    stock: DemoStockGateway(),
    household: household,
    shopping: DemoShoppingGateway(),
  );
  await seedDemoRecipesIfEmpty(service.repository, household.currentUserId);
  await seedDemoMealHistory(service.repository, household.currentUserId, DateTime.now());

  runApp(PanierMalinApp(service: service));
}

class PanierMalinApp extends StatelessWidget {
  const PanierMalinApp({super.key, required this.service});

  final RecipeService service;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MultiProvider(
      providers: RecipesModule.providers(service),
      child: MaterialApp(
        title: 'PanierMalin',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const RecipesHomeScreen(),
      ),
    );
  }
}
