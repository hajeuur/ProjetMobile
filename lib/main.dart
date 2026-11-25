import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'core/ui/app_home_screen.dart';
import 'features/recipes/data/demo_recipes.dart';
import 'features/recipes/integration/demo_gateways.dart';
import 'features/recipes/recipes_module.dart';
import 'features/recipes/services/recipe_service.dart';
import 'features/shopping/data/demo_shopping.dart';
import 'features/shopping/integration/demo_gateways.dart' as shop_demo;
import 'features/shopping/integration/recipes_bridge.dart';
import 'features/shopping/services/product_scan_service.dart';
import 'features/shopping/services/shopping_devices.dart';
import 'features/shopping/ui/budget_alert_banner.dart';
import 'features/shopping/services/shopping_service.dart';
import 'features/shopping/shopping_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final db = await AppDatabase.open();

  // Gestion 5 — Courses et Budget.
  // TODO(intégration) : remplacer les passerelles de démo par les services
  // des gestions 1 (utilisateur), 2 (produits/stock) et 4 (magasins).
  final shopping = ShoppingModule.createService(
    db: db,
    users: shop_demo.DemoUserGateway(),
    products: shop_demo.DemoProductGateway(),
    stores: shop_demo.DemoStoreGateway(),
  );
  await seedDemoShoppingIfEmpty(shopping.repository, shopping.userId, DateTime.now());

  // Gestion 3 — Recettes. Les ingrédients manquants arrivent dans la vraie
  // liste de courses de la gestion 5.
  // TODO(intégration) : remplacer les passerelles de démo des gestions 1 et 2.
  final household = DemoHouseholdGateway();
  final recipes = RecipesModule.createService(
    db: db,
    stock: DemoStockGateway(),
    household: household,
    shopping: RecipesShoppingBridge(shopping),
  );
  await seedDemoRecipesIfEmpty(recipes.repository, household.currentUserId);
  await seedDemoMealHistory(recipes.repository, household.currentUserId, DateTime.now());

  runApp(PanierMalinApp(service: recipes, shopping: shopping));
}

class PanierMalinApp extends StatelessWidget {
  const PanierMalinApp({
    super.key,
    required this.service,
    required this.shopping,
    this.receiptReader,
    this.shakeSource,
    this.voiceInput,
    this.liveCamera,
    this.notifier,
    this.productScan,
    this.home,
  });

  final RecipeService service;
  final ShoppingService shopping;

  /// Remplaçable dans les tests (pas de caméra).
  final ReceiptReader? receiptReader;

  /// Remplaçable dans les tests (pas d'accéléromètre).
  final ShakeSource? shakeSource;

  /// Remplaçable dans les tests (pas de micro).
  final VoiceInput? voiceInput;

  /// Remplaçable dans les tests (pas de caméra en direct).
  final LiveCameraFactory? liveCamera;

  /// Remplaçable dans les tests (pas de notifications système).
  final LocalNotifier? notifier;

  /// Remplaçable dans les tests (réponses HTTP simulées).
  final ProductScanService? productScan;

  /// Écran de départ (accueil par défaut).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MultiProvider(
      providers: [
        ...RecipesModule.providers(service),
        ...ShoppingModule.providers(
          shopping,
          reader: receiptReader,
          shakes: shakeSource,
          voice: voiceInput,
          liveCamera: liveCamera,
          notifier: notifier,
          productScan: productScan,
        ),
      ],
      child: MaterialApp(
        title: 'PanierMalin',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
        // Bannière d'alerte de budget (gestion 5) au-dessus de tous les écrans.
        builder: (context, child) => BudgetAlertOverlay(child: child ?? const SizedBox.shrink()),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        navigatorObservers: [ShoppingModule.routeObserver],
        home: home ?? const AppHomeScreen(),
      ),
    );
  }
}
