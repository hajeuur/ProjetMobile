import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/data/demo_recipes.dart';
import 'package:panier_malin/features/recipes/data/recipe_repository.dart';
import 'package:panier_malin/features/recipes/data/themealdb_api.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/models/meal_plan.dart';
import 'package:panier_malin/features/recipes/models/recipe.dart';
import 'package:panier_malin/features/recipes/services/recipe_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 11, 23, 12); // lundi midi

  late Database db;
  late RecipeService service;
  late DemoStockGateway stock;
  late DemoShoppingGateway shopping;
  late int apiCalls;

  setUp(() async {
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    stock = DemoStockGateway(today: today);
    shopping = DemoShoppingGateway();
    apiCalls = 0;
    final client = MockClient((req) async {
      apiCalls++;
      if (req.url.path.endsWith('lookup.php')) {
        return http.Response(
          '{"meals":[{"idMeal":"1","strMeal":"Egg Fried Rice","strCategory":"Side",'
          '"strInstructions":"Cook rice.\\nFry eggs 5 minutes.","strMealThumb":null,'
          '"strIngredient1":"Rice","strMeasure1":"200g","strIngredient2":"Eggs","strMeasure2":"2"}]}',
          200,
        );
      }
      return http.Response('{"meals":null}', 200);
    });
    service = RecipeService(
      repository: RecipeRepository(db),
      api: TheMealDbApi(client: client, cache: ApiCache(db)),
      stock: stock,
      household: DemoHouseholdGateway(),
      shopping: shopping,
      clock: () => today,
    );
  });

  tearDown(() => db.close());

  test('CRUD recette avec ingrédients et étapes', () async {
    final id = await service.saveRecipe(Recipe(
      userId: 1,
      title: 'Test',
      baseServings: 2,
      ingredients: const [RecipeIngredient(name: 'Riz', quantity: 100, unit: 'g')],
      steps: const [RecipeStep(number: 1, text: 'Cuire')],
    ));
    var r = (await service.recipe(id))!;
    expect(r.ingredients.single.name, 'Riz');
    expect(r.steps.single.text, 'Cuire');

    await service.saveRecipe(r.copyWith(
      title: 'Test 2',
      ingredients: const [
        RecipeIngredient(name: 'Riz', quantity: 200, unit: 'g'),
        RecipeIngredient(name: 'Sel'),
      ],
    ));
    r = (await service.recipe(id))!;
    expect(r.title, 'Test 2');
    expect(r.ingredients.length, 2);

    await service.deleteRecipe(id);
    expect(await service.recipe(id), isNull);
  });

  test('validation : titre et ingrédient obligatoires', () async {
    expect(() => service.saveRecipe(Recipe(userId: 1, title: ' ')), throwsArgumentError);
    expect(() => service.saveRecipe(Recipe(userId: 1, title: 'A')), throwsArgumentError);
  });

  test('marquer cuisiné retire les ingrédients du stock, une seule fois', () async {
    await seedDemoRecipesIfEmpty(service.repository, 1);
    final chakchouka = (await service.recipes()).firstWhere((r) => r.title == 'Chakchouka');
    final planId = await service.planMeal(recipeId: chakchouka.id!, date: today, meal: MealType.dinner, servings: 3);

    final n = await service.markCooked(planId);
    expect(n, greaterThan(0));
    final s = await stock.currentStock();
    expect(s.firstWhere((x) => x.name == 'Tomate').quantity, 2); // 6 - 4
    expect(s.firstWhere((x) => x.name == 'Oeuf').quantity, 6); // 10 - 4

    expect(await service.markCooked(planId), 0);
    expect((await stock.currentStock()).firstWhere((x) => x.name == 'Tomate').quantity, 2);

    // Gestion 6 : calories consommées.
    expect(await service.caloriesConsumedPerPerson(today), 320);
    expect((await service.mostCooked()).first, ('Chakchouka', 1));
  });

  test('ingrédients manquants envoyés à la liste de courses', () async {
    await seedDemoRecipesIfEmpty(service.repository, 1);
    final soupe = (await service.recipes()).firstWhere((r) => r.title == 'Soupe de lentilles');
    final n = await service.sendMissingToShopping(soupe, 4);
    expect(n, 3); // lentilles, carottes et cumin ne sont pas dans le stock de démo
    expect(shopping.items.map((i) => i.label), containsAll(['Lentilles', 'Carotte', 'Cumin']));
    expect(shopping.items.map((i) => i.label), isNot(contains('Oignon')));
    expect(shopping.items.every((i) => i.origin == 'recette'), isTrue);
  });

  test('menu de la semaine : compatible foyer, sans doublon, appliqué', () async {
    await seedDemoRecipesIfEmpty(service.repository, 1);
    final week = weekStartOf(today);
    final menu = await service.proposeWeekMenu(week);
    final titles = menu.entries.map((e) => e.recipe.title).toList();
    expect(titles, isNot(contains('Poulet sauce cacahuète'))); // allergie arachide du foyer
    expect(titles.toSet().length, titles.length);
    expect(menu.entries.length, 9);

    await service.applyMenu(week, menu);
    expect((await service.week(week)).length, 9);

    // Régénérer en gardant l'existant : plus aucune recette disponible.
    expect((await service.proposeWeekMenu(week)).entries, isEmpty);
  });

  test('import TheMealDB : conversion, doublon évité, cache', () async {
    final id1 = await service.importFromApi('1');
    final id2 = await service.importFromApi('1');
    expect(id1, id2);
    final r = (await service.recipe(id1))!;
    expect(r.title, 'Egg Fried Rice');
    expect(r.source, RecipeSource.themealdb);
    expect(r.steps.length, 2);
    expect(apiCalls, 1);

    // Deuxième appel servi par le cache local.
    await service.api.fetchRecipe('1', userId: 1);
    expect(apiCalls, 1);
  });
}
