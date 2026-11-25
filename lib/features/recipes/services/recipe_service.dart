import '../data/recipe_repository.dart';
import '../data/themealdb_api.dart';
import '../integration/gateways.dart';
import '../logic/dietary_checker.dart';
import '../logic/menu_generator.dart';
import '../logic/portion_scaler.dart';
import '../logic/stock_analysis.dart';
import '../logic/units.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';

/// Service de la gestion 3 — Recettes.
///
/// Point d'entrée unique pour les écrans et pour les autres gestions :
/// - la gestion 6 lit les calories consommées via [caloriesConsumedPerPerson] ;
/// - la gestion 5 reçoit les ingrédients manquants via [ShoppingGateway] ;
/// - la gestion 2 reçoit les sorties de stock via [StockGateway].
class RecipeService {
  RecipeService({
    required this.repository,
    required this.api,
    required this.stock,
    required this.household,
    required this.shopping,
    this.checker = const DietaryChecker(),
    this.menuGenerator = const MenuGenerator(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecipeRepository repository;
  final TheMealDbApi api;
  final StockGateway stock;
  final HouseholdGateway household;
  final ShoppingGateway shopping;
  final DietaryChecker checker;
  final MenuGenerator menuGenerator;
  final DateTime Function() _clock;

  DateTime get now => _clock();
  int get userId => household.currentUserId;

  // ------------------------------------------------------------------ CRUD

  Future<List<Recipe>> recipes() => repository.listRecipes(userId);
  Future<Recipe?> recipe(int id) => repository.getRecipe(id);

  Future<int> saveRecipe(Recipe r) async {
    _validate(r);
    if (r.id == null) return repository.insertRecipe(r);
    await repository.updateRecipe(r);
    return r.id!;
  }

  void _validate(Recipe r) {
    if (r.title.trim().isEmpty) throw ArgumentError('Le titre est obligatoire.');
    if (r.baseServings < 1) throw ArgumentError('Il faut au moins une portion.');
    if (r.ingredients.isEmpty) throw ArgumentError('Ajoutez au moins un ingrédient.');
  }

  Future<void> deleteRecipe(int id) => repository.deleteRecipe(id);

  /// Importe une recette TheMealDB ; si elle l'est déjà, renvoie l'existante.
  Future<int> importFromApi(String externalId) async {
    final existing = await repository.findByExternalId(userId, externalId);
    if (existing != null) return existing.id!;
    final r = await api.fetchRecipe(externalId, userId: userId);
    return repository.insertRecipe(r);
  }

  // ------------------------------------------------------- Contexte foyer

  Future<HouseholdProfile> profile() => household.commonProfile();
  Future<List<StockSnapshot>> currentStock() => stock.currentStock();

  // -------------------------------------------------------------- Planning

  Future<List<MealPlan>> week(DateTime weekStart) =>
      repository.mealPlansBetween(userId, weekStart, addDays(weekStart, 6));

  Future<int> planMeal({required int recipeId, required DateTime date, required MealType meal, required int servings}) =>
      repository.insertMealPlan(MealPlan(date: date, meal: meal, recipeId: recipeId, servings: servings));

  Future<void> moveMeal(MealPlan plan, {required DateTime date, required MealType meal}) =>
      repository.updateMealPlan(plan.copyWith(date: date, meal: meal));

  Future<void> changeServings(MealPlan plan, int servings) =>
      repository.updateMealPlan(plan.copyWith(servings: servings < 1 ? 1 : servings));

  Future<void> deleteMeal(int id) => repository.deleteMealPlan(id);

  /// Marque le repas comme cuisiné et retire les ingrédients du stock via le
  /// service de la gestion 2. Renvoie le nombre d'ingrédients sortis du stock.
  Future<int> markCooked(int mealPlanId) async {
    final plan = await repository.getMealPlan(mealPlanId);
    if (plan == null) throw StateError('Repas introuvable.');
    if (plan.status == MealStatus.cooked) return 0;
    final recipe = plan.recipe;
    if (recipe == null) throw StateError('Recette introuvable.');

    final consumed = await consumeIngredients(recipe, plan.servings);
    await repository.updateMealPlan(plan.copyWith(status: MealStatus.cooked, cookedAt: now));
    return consumed;
  }

  /// Sort du stock les ingrédients de [recipe] pour [servings] personnes.
  Future<int> consumeIngredients(Recipe recipe, int servings) async {
    final scaled = scaleRecipe(recipe, servings);
    final snapshot = await stock.currentStock();
    var count = 0;
    for (final ing in scaled.ingredients) {
      if (ing.quantity == null) continue;
      final matches = matchingStock(ing, snapshot, now)
        ..sort((a, b) => (a.expiryDate ?? DateTime(9999)).compareTo(b.expiryDate ?? DateTime(9999)));
      if (matches.isEmpty) continue;
      // On puise d'abord dans les lignes qui périment le plus tôt.
      final need = toBase(ing.quantity!, ing.unit);
      var remaining = need.value;
      for (final s in matches) {
        if (remaining <= 0) break;
        final have = toBase(s.quantity, s.unit);
        if (have.unit != need.unit) {
          // Unités incomparables : on retire une unité de stock symbolique
          // uniquement si l'ingrédient est compté à la pièce côté stock.
          if (have.unit == 'piece') {
            await stock.consume(productId: s.productId, name: s.name, quantity: 1, unit: s.unit, reason: 'recette : ${recipe.title}');
            count++;
          }
          remaining = 0;
          break;
        }
        final take = remaining < have.value ? remaining : have.value;
        final factor = have.value == 0 ? 0.0 : s.quantity / have.value; // base -> unité du stock
        await stock.consume(
          productId: s.productId,
          name: s.name,
          quantity: _round(take * factor),
          unit: s.unit,
          reason: 'recette : ${recipe.title}',
        );
        remaining -= take;
        count++;
      }
    }
    return count;
  }

  // --------------------------------------------------- Courses (gestion 5)

  Future<List<MissingIngredient>> missingFor(Recipe recipe, int servings) async {
    final scaled = scaleRecipe(recipe, servings);
    return missingIngredients(scaled.ingredients, await stock.currentStock(), now);
  }

  /// Envoie les ingrédients manquants de la recette à la liste en cours.
  Future<int> sendMissingToShopping(Recipe recipe, int servings) async {
    final missing = await missingFor(recipe, servings);
    if (missing.isEmpty) return 0;
    return shopping.addItems([for (final m in missing) m.toShoppingRequest()]);
  }

  /// Ingrédients manquants pour tous les repas encore prévus de la semaine,
  /// en tenant compte de ce que les repas précédents auront consommé.
  Future<int> sendWeekMissingToShopping(DateTime weekStart) async {
    final plans = (await week(weekStart)).where((p) => p.status == MealStatus.planned && p.recipe != null);
    var remainingStock = [...await stock.currentStock()];
    final requests = <ShoppingRequest>[];
    for (final p in plans) {
      final scaled = scaleRecipe(p.recipe!, p.servings);
      for (final m in missingIngredients(scaled.ingredients, remainingStock, now)) {
        requests.add(m.toShoppingRequest());
      }
      remainingStock = _simulateConsumption(remainingStock, scaled.ingredients);
    }
    if (requests.isEmpty) return 0;
    return shopping.addItems(_mergeRequests(requests));
  }

  List<StockSnapshot> _simulateConsumption(List<StockSnapshot> stockList, List<RecipeIngredient> ings) {
    final result = [...stockList];
    for (final ing in ings) {
      if (ing.quantity == null) continue;
      final need = toBase(ing.quantity!, ing.unit);
      var remaining = need.value;
      for (final s in matchingStock(ing, result, now)) {
        if (remaining <= 0) break;
        final have = toBase(s.quantity, s.unit);
        if (have.unit != need.unit) continue;
        final take = remaining < have.value ? remaining : have.value;
        final i = result.indexOf(s);
        final left = s.quantity - take * (s.quantity / have.value);
        result[i] = StockSnapshot(productId: s.productId, name: s.name, quantity: left, unit: s.unit, expiryDate: s.expiryDate);
        remaining -= take;
      }
    }
    return result;
  }

  /// Regroupe les demandes identiques (même libellé et même unité).
  List<ShoppingRequest> _mergeRequests(List<ShoppingRequest> requests) {
    final merged = <String, ShoppingRequest>{};
    for (final r in requests) {
      final key = '${r.label.toLowerCase()}|${r.unit ?? ''}';
      final prev = merged[key];
      if (prev == null) {
        merged[key] = r;
      } else {
        final q = (prev.quantity == null || r.quantity == null) ? null : prev.quantity! + r.quantity!;
        merged[key] = ShoppingRequest(label: prev.label, quantity: q, unit: prev.unit, productId: prev.productId, origin: prev.origin);
      }
    }
    return merged.values.toList();
  }

  // ----------------------------------------------------- Menu automatique

  /// Propose un menu pour la semaine. Si [onlyEmptySlots], les repas déjà
  /// planifiés sont conservés et comptent pour la variété.
  Future<GeneratedMenu> proposeWeekMenu(
    DateTime weekStart, {
    bool onlyEmptySlots = true,
    double? dailyTargetPerPerson,
    int? servings,
  }) async {
    final existing = await week(weekStart);
    final kept = onlyEmptySlots ? existing : existing.where((p) => p.status == MealStatus.cooked).toList();
    final taken = {for (final p in kept) MealSlot(p.date, p.meal)};
    final today = dateOnly(now);
    final slots = weekSlots(weekStart).where((s) => !taken.contains(s) && !s.date.isBefore(today)).toList();
    return menuGenerator.generate(
      recipes: await recipes(),
      profile: await profile(),
      stock: await stock.currentStock(),
      slots: slots,
      now: now,
      alreadyUsedRecipeIds: {for (final p in kept) p.recipeId},
      dailyTargetPerPerson: dailyTargetPerPerson,
      servings: servings,
    );
  }

  /// Enregistre le menu proposé. Si [replacePlanned], les repas « prévus » de
  /// la semaine sont d'abord supprimés.
  Future<void> applyMenu(DateTime weekStart, GeneratedMenu menu, {bool replacePlanned = false}) async {
    if (replacePlanned) {
      await repository.deletePlannedBetween(userId, weekStart, addDays(weekStart, 6));
    }
    for (final e in menu.entries) {
      await planMeal(recipeId: e.recipe.id!, date: e.slot.date, meal: e.slot.meal, servings: e.servings);
    }
  }

  // ---------------------------------------------------- Lecture gestion 6

  /// Calories consommées par personne le jour [date] : somme des calories par
  /// portion des repas marqués cuisinés (chaque membre mange une portion).
  Future<double> caloriesConsumedPerPerson(DateTime date) async {
    final plans = await repository.mealPlansBetween(userId, date, date);
    return plans
        .where((p) => p.status == MealStatus.cooked)
        .fold<double>(0, (s, p) => s + (p.recipe?.caloriesPerServing ?? 0));
  }

  // --------------------------------------------------------- Statistiques

  Future<List<(String, int)>> mostCooked({int limit = 5}) => repository.mostCooked(userId, limit: limit);
}

double _round(double v) => (v * 100).roundToDouble() / 100;
