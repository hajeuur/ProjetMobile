import '../models/recipe.dart';
import 'text_matching.dart';
import 'units.dart';

/// Estimation des calories d'une recette quand la source n'en donne pas
/// (TheMealDB). Table de valeurs moyennes (kcal pour 100 g ou 100 ml), clés
/// sous forme canonique (voir [canonicalIngredient]).
const Map<String, double> kcalPer100 = {
  'chicken': 165, 'chicken breast': 165, 'chicken thigh': 209, 'beef': 250, 'lamb': 282,
  'minced beef': 250, 'pork': 242, 'fish': 120, 'tuna': 130, 'salmon': 208, 'shrimp': 99, 'prawn': 99,
  'egg': 155, 'milk': 64, 'butter': 717, 'cream': 340, 'double cream': 450, 'cheese': 400,
  'parmesan': 431, 'mozzarella': 280, 'cheddar': 403, 'feta': 264, 'yogurt': 61,
  'rice': 360, 'flour': 364, 'plain flour': 364, 'pasta': 371, 'spaghetti': 371, 'couscous': 376,
  'bread': 265, 'breadcrumb': 395, 'potato': 77, 'sugar': 387, 'caster sugar': 387, 'brown sugar': 380,
  'honey': 304, 'olive oil': 884, 'vegetable oil': 884, 'oil': 884, 'sunflower oil': 884,
  'tomato': 18, 'tomato puree': 82, 'chopped tomato': 21, 'onion': 40, 'red onion': 40,
  'garlic': 149, 'pepper': 26, 'red pepper': 31, 'green pepper': 20, 'carrot': 41, 'zucchini': 17,
  'eggplant': 25, 'mushroom': 22, 'spinach': 23, 'lemon': 29, 'chickpea': 364, 'lentil': 352,
  'bean': 333, 'kidney bean': 333, 'pea': 81, 'almond': 579, 'walnut': 654, 'peanut': 567,
  'coconut milk': 230, 'chocolate': 546, 'dark chocolate': 546, 'stock': 5, 'chicken stock': 5,
  'water': 0, 'salt': 0, 'black pepper': 0, 'cumin': 0, 'paprika': 0, 'coriander': 23, 'parsley': 36,
  'harissa': 120, 'semolina': 360, 'oat': 389,
};

/// Poids moyen d'une pièce (g) pour les ingrédients comptés à l'unité.
const Map<String, double> gramsPerPiece = {
  'egg': 55, 'onion': 110, 'red onion': 110, 'tomato': 120, 'potato': 170, 'carrot': 60,
  'pepper': 150, 'red pepper': 150, 'green pepper': 150, 'lemon': 80, 'zucchini': 200,
  'eggplant': 300, 'chicken breast': 170, 'chicken thigh': 120, 'garlic': 5,
};

class CalorieEstimate {
  const CalorieEstimate({required this.perServing, required this.coveredIngredients, required this.totalIngredients});

  final double perServing;

  /// Nombre d'ingrédients dont la valeur a pu être estimée.
  final int coveredIngredients;
  final int totalIngredients;

  /// Estimation fiable si au moins la moitié des ingrédients est couverte.
  bool get reliable => totalIngredients > 0 && coveredIngredients * 2 >= totalIngredients;
}

double? _kcalFor(String name) {
  final c = canonicalIngredient(name);
  if (kcalPer100.containsKey(c)) return kcalPer100[c];
  // Dernier mot (« fresh tomato » -> « tomato »), puis premier.
  final words = c.split(' ');
  return kcalPer100[words.last] ?? kcalPer100[words.first];
}

double? _gramsPerPiece(String name) {
  final c = canonicalIngredient(name);
  return gramsPerPiece[c] ?? gramsPerPiece[c.split(' ').last];
}

/// Renvoie null si aucun ingrédient n'a pu être estimé.
CalorieEstimate? estimateCalories(List<RecipeIngredient> ingredients, int servings) {
  var total = 0.0;
  var covered = 0;
  for (final ing in ingredients) {
    final kcal = _kcalFor(ing.name);
    if (kcal == null || ing.quantity == null) continue;
    final b = toBase(ing.quantity!, ing.unit);
    double? grams;
    if (b.unit == 'g' || b.unit == 'ml') {
      grams = b.value;
    } else if (b.unit == 'piece' || b.unit == 'gousse') {
      final w = _gramsPerPiece(ing.name);
      if (w != null) grams = b.value * w;
    }
    if (grams == null) continue;
    total += grams * kcal / 100;
    covered++;
  }
  if (covered == 0) return null;
  final s = servings < 1 ? 1 : servings;
  return CalorieEstimate(
    perServing: (total / s).roundToDouble(),
    coveredIngredients: covered,
    totalIngredients: ingredients.length,
  );
}
