import '../models/recipe.dart';

class ScaledRecipe {
  const ScaledRecipe({
    required this.recipe,
    required this.servings,
    required this.factor,
    required this.ingredients,
  });

  final Recipe recipe;
  final int servings;
  final double factor;
  final List<RecipeIngredient> ingredients;

  /// Les calories par portion ne changent pas ; le total si.
  double? get caloriesPerServing => recipe.caloriesPerServing;
  double? get totalCalories =>
      recipe.caloriesPerServing == null ? null : recipe.caloriesPerServing! * servings;
}

/// Recalcule les quantités pour [servings] personnes.
ScaledRecipe scaleRecipe(Recipe recipe, int servings) {
  if (servings < 1) throw ArgumentError.value(servings, 'servings', 'doit être ≥ 1');
  final base = recipe.baseServings < 1 ? 1 : recipe.baseServings;
  final factor = servings / base;
  return ScaledRecipe(
    recipe: recipe,
    servings: servings,
    factor: factor,
    ingredients: [
      for (final i in recipe.ingredients)
        i.quantity == null ? i : i.copyWith(quantity: _round(i.quantity! * factor)),
    ],
  );
}

double _round(double v) => (v * 100).roundToDouble() / 100;
