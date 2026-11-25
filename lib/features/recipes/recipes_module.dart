import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite/sqflite.dart';

import 'data/recipe_repository.dart';
import 'data/themealdb_api.dart';
import 'integration/gateways.dart';
import 'services/cooking_devices.dart';
import 'services/recipe_service.dart';
import 'viewmodels/meal_plan_view_model.dart';
import 'viewmodels/recipe_list_view_model.dart';
import 'viewmodels/recipe_stats_view_model.dart';

/// Branchement de la gestion 3 dans l'application.
///
/// Intégration : remplacer les passerelles de démo par les services réels des
/// gestions 1, 2 et 5 lors de l'appel à [providers].
class RecipesModule {
  RecipesModule._();

  static RecipeService createService({
    required Database db,
    required StockGateway stock,
    required HouseholdGateway household,
    required ShoppingGateway shopping,
  }) =>
      RecipeService(
        repository: RecipeRepository(db),
        api: TheMealDbApi(cache: ApiCache(db)),
        stock: stock,
        household: household,
        shopping: shopping,
      );

  static List<SingleChildWidget> providers(RecipeService service, {CookingDevices? devices}) => [
        Provider<RecipeService>.value(value: service),
        Provider<CookingDevices>(create: (_) => devices ?? CookingDevices.device()),
        ChangeNotifierProvider(create: (_) => RecipeListViewModel(service)..load()),
        ChangeNotifierProvider(create: (_) => MealPlanViewModel(service)..load()),
        ChangeNotifierProvider(create: (_) => RecipeStatsViewModel(service)..load()),
      ];
}
