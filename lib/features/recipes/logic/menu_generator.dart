import '../integration/gateways.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import 'dietary_checker.dart';
import 'stock_analysis.dart';
import 'text_matching.dart';

/// Un créneau de la semaine (jour + repas).
class MealSlot {
  const MealSlot(this.date, this.meal);
  final DateTime date;
  final MealType meal;

  @override
  bool operator ==(Object other) =>
      other is MealSlot && dateKey(other.date) == dateKey(date) && other.meal == meal;
  @override
  int get hashCode => Object.hash(dateKey(date), meal);
}

class MenuEntry {
  const MenuEntry({
    required this.slot,
    required this.recipe,
    required this.servings,
    required this.antiGaspi,
    required this.targetCalories,
  });

  final MealSlot slot;
  final Recipe recipe;
  final int servings;
  final double antiGaspi;

  /// Calories visées par personne pour ce repas.
  final double targetCalories;
}

class GeneratedMenu {
  const GeneratedMenu({required this.entries, required this.unfilled, required this.dailyTargetPerPerson});

  final List<MenuEntry> entries;

  /// Créneaux restés vides faute de recette compatible et non encore utilisée.
  final List<MealSlot> unfilled;
  final double dailyTargetPerPerson;
}

const _breakfastCategories = {'breakfast', 'petit dejeuner', 'dessert', 'patisserie', 'gouter'};

bool isBreakfastLike(Recipe r) =>
    r.category != null && _breakfastCategories.contains(normalize(r.category!));

/// Remplit la semaine en respectant :
/// 1. les allergies et régimes du foyer (élimination stricte) ;
/// 2. la variété : jamais deux fois la même recette dans la semaine ;
/// 3. l'objectif calorique (par repas : objectif journalier × part du repas) ;
/// 4. la priorité anti-gaspi : à chaque créneau, dans l'ordre chronologique,
///    on choisit la meilleure recette ; les produits bientôt périmés partent
///    donc en début de semaine. Un produit urgent déjà utilisé par une recette
///    retenue ne compte plus comme urgent pour les suivantes.
class MenuGenerator {
  const MenuGenerator({this.checker = const DietaryChecker(), this.gaspiWeight = 0.55});

  final DietaryChecker checker;

  /// Poids du score anti-gaspi face à l'adéquation calorique (0 à 1).
  final double gaspiWeight;

  GeneratedMenu generate({
    required List<Recipe> recipes,
    required HouseholdProfile profile,
    required List<StockSnapshot> stock,
    required List<MealSlot> slots,
    required DateTime now,
    Set<int> alreadyUsedRecipeIds = const {},
    double? dailyTargetPerPerson,
    int? servings,
  }) {
    final target = dailyTargetPerPerson ?? profile.dailyCaloriesPerPerson;
    final people = servings ?? (profile.memberCount < 1 ? 1 : profile.memberCount);
    final allowed = [
      for (final r in recipes)
        if (r.id != null && checker.check(r, profile).allowed) r,
    ];
    final used = {...alreadyUsedRecipeIds};
    final claimed = <String>{};
    final entries = <MenuEntry>[];
    final unfilled = <MealSlot>[];

    final ordered = [...slots]
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.meal.index.compareTo(b.meal.index);
      });

    for (final slot in ordered) {
      final mealTarget = target * slot.meal.calorieShare;
      var candidates = allowed.where((r) => !used.contains(r.id)).toList();
      // Petit-déjeuner : recettes adaptées d'abord ; l'inverse pour les autres repas.
      final fitting = candidates
          .where((r) => slot.meal == MealType.breakfast ? isBreakfastLike(r) : !isBreakfastLike(r))
          .toList();
      if (fitting.isNotEmpty) candidates = fitting;
      if (candidates.isEmpty) {
        unfilled.add(slot);
        continue;
      }

      Recipe? best;
      var bestScore = double.negativeInfinity;
      var bestGaspi = 0.0;
      for (final r in candidates) {
        final gaspi = antiGaspiScore(r.ingredients, stock, now, claimedStock: claimed).score;
        final fit = calorieFit(r.caloriesPerServing, mealTarget);
        final score = gaspiWeight * gaspi + (1 - gaspiWeight) * fit * 100;
        if (score > bestScore) {
          bestScore = score;
          best = r;
          bestGaspi = gaspi;
        }
      }
      final chosen = best!;
      used.add(chosen.id!);
      for (final ing in chosen.ingredients) {
        for (final s in matchingStock(ing, stock, now)) {
          if (isExpiringSoon(s, now)) claimed.add(s.name);
        }
      }
      entries.add(MenuEntry(
        slot: slot,
        recipe: chosen,
        servings: people,
        antiGaspi: bestGaspi,
        targetCalories: mealTarget,
      ));
    }
    return GeneratedMenu(entries: entries, unfilled: unfilled, dailyTargetPerPerson: target);
  }
}

/// 1 quand les calories correspondent à la cible, 0 à ±100 % d'écart.
/// Calories inconnues : 0,5 (neutre).
double calorieFit(double? calories, double target) {
  if (calories == null || target <= 0) return 0.5;
  final gap = (calories - target).abs() / target;
  return gap >= 1 ? 0 : 1 - gap;
}

/// Les 21 créneaux de la semaine commençant à [weekStart].
List<MealSlot> weekSlots(DateTime weekStart) => [
      for (var d = 0; d < 7; d++)
        for (final m in MealType.values) MealSlot(addDays(weekStart, d), m),
    ];
