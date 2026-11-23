import 'package:flutter/foundation.dart';

import '../integration/gateways.dart';
import '../logic/menu_generator.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';

class MealPlanViewModel extends ChangeNotifier {
  MealPlanViewModel(this.service) : weekStart = weekStartOf(service.now);

  final RecipeService service;

  DateTime weekStart;
  bool loading = false;
  String? error;
  List<MealPlan> plans = [];
  HouseholdProfile? profile;

  List<DateTime> get days => [for (var d = 0; d < 7; d++) addDays(weekStart, d)];

  MealPlan? planAt(DateTime date, MealType meal) {
    final k = dateKey(date);
    for (final p in plans) {
      if (dateKey(p.date) == k && p.meal == meal) return p;
    }
    return null;
  }

  /// Calories prévues par personne pour la journée.
  double caloriesPerPerson(DateTime date) {
    final k = dateKey(date);
    return plans
        .where((p) => dateKey(p.date) == k)
        .fold(0.0, (s, p) => s + (p.recipe?.caloriesPerServing ?? 0));
  }

  double get dailyTarget => profile?.dailyCaloriesPerPerson ?? 2000;
  int get defaultServings => (profile?.memberCount ?? 1) < 1 ? 1 : profile!.memberCount;
  int get plannedCount => plans.where((p) => p.status == MealStatus.planned).length;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      profile = await service.profile();
      plans = await service.week(weekStart);
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> goToWeek(int offset) {
    weekStart = offset == 0 ? weekStartOf(service.now) : addDays(weekStart, 7 * offset);
    return load();
  }

  Future<void> plan(Recipe recipe, DateTime date, MealType meal, {int? servings}) async {
    final existing = planAt(date, meal);
    if (existing?.id != null) await service.deleteMeal(existing!.id!);
    await service.planMeal(recipeId: recipe.id!, date: date, meal: meal, servings: servings ?? defaultServings);
    await load();
  }

  /// Déplace un repas ; si le créneau cible est occupé, les deux sont échangés.
  Future<void> move(MealPlan plan, DateTime date, MealType meal) async {
    final target = planAt(date, meal);
    if (target != null && target.id != plan.id) {
      await service.moveMeal(target, date: plan.date, meal: plan.meal);
    }
    await service.moveMeal(plan, date: date, meal: meal);
    await load();
  }

  Future<void> changeServings(MealPlan plan, int servings) async {
    await service.changeServings(plan, servings);
    await load();
  }

  Future<void> delete(MealPlan plan) async {
    await service.deleteMeal(plan.id!);
    await load();
  }

  Future<int> markCooked(MealPlan plan) async {
    final n = await service.markCooked(plan.id!);
    await load();
    return n;
  }

  Future<int> sendWeekMissingToShopping() => service.sendWeekMissingToShopping(weekStart);

  Future<GeneratedMenu> propose({required bool onlyEmptySlots, int? servings}) =>
      service.proposeWeekMenu(weekStart, onlyEmptySlots: onlyEmptySlots, servings: servings);

  Future<void> apply(GeneratedMenu menu, {required bool replacePlanned}) async {
    await service.applyMenu(weekStart, menu, replacePlanned: replacePlanned);
    await load();
  }
}
