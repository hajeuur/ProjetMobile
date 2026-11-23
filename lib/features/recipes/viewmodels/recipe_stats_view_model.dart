import 'package:flutter/foundation.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';

class DayCalories {
  const DayCalories(this.date, this.averagePerMeal, this.meals, this.cooked);
  final DateTime date;

  /// Calories moyennes par repas et par personne (0 si aucun repas).
  final double averagePerMeal;
  final int meals;
  final int cooked;
}

class RecipeStatsViewModel extends ChangeNotifier {
  RecipeStatsViewModel(this.service) : weekStart = weekStartOf(service.now);

  final RecipeService service;
  DateTime weekStart;

  bool loading = false;
  String? error;
  List<(String, int)> mostCooked = [];
  List<DayCalories> week = [];
  int recipeCount = 0;
  int personalCount = 0;
  int importedCount = 0;

  /// Moyenne sur la semaine des calories par repas (repas ayant des calories).
  double weekAveragePerMeal = 0;
  int weekCooked = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final recipes = await service.recipes();
      recipeCount = recipes.length;
      personalCount = recipes.where((r) => r.source == RecipeSource.personal).length;
      importedCount = recipeCount - personalCount;
      mostCooked = await service.mostCooked();

      final plans = await service.week(weekStart);
      week = [];
      var sum = 0.0;
      var n = 0;
      for (var d = 0; d < 7; d++) {
        final day = addDays(weekStart, d);
        final dayPlans = plans.where((p) => dateKey(p.date) == dateKey(day)).toList();
        final withCal = dayPlans.where((p) => p.recipe?.caloriesPerServing != null).toList();
        final total = withCal.fold<double>(0, (s, p) => s + p.recipe!.caloriesPerServing!);
        sum += total;
        n += withCal.length;
        week.add(DayCalories(
          day,
          withCal.isEmpty ? 0 : total / withCal.length,
          dayPlans.length,
          dayPlans.where((p) => p.status == MealStatus.cooked).length,
        ));
      }
      weekAveragePerMeal = n == 0 ? 0 : sum / n;
      weekCooked = plans.where((p) => p.status == MealStatus.cooked).length;
    } catch (e) {
      error = 'Statistiques indisponibles : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> goToWeek(int offset) {
    weekStart = offset == 0 ? weekStartOf(service.now) : addDays(weekStart, 7 * offset);
    return load();
  }
}
