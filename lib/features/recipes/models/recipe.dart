/// Entités de la gestion 3 — Recettes.
///
/// Tables propriétaires : recipes, recipe_ingredients, recipe_steps, meal_plans.
library;

enum RecipeSource {
  personal('personal', 'Personnelle'),
  themealdb('themealdb', 'TheMealDB');

  const RecipeSource(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static RecipeSource fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value, orElse: () => personal);
}

class RecipeIngredient {
  const RecipeIngredient({
    this.id,
    this.recipeId,
    required this.name,
    this.quantity,
    this.unit,
    this.productId,
  });

  final int? id;
  final int? recipeId;
  final String name;

  /// Null quand la quantité n'est pas chiffrée (« sel, à volonté »).
  final double? quantity;
  final String? unit;

  /// Lien facultatif vers products (gestion 2).
  final int? productId;

  RecipeIngredient copyWith({double? quantity, int? recipeId}) => RecipeIngredient(
        id: id,
        recipeId: recipeId ?? this.recipeId,
        name: name,
        quantity: quantity ?? this.quantity,
        unit: unit,
        productId: productId,
      );

  Map<String, Object?> toMap(int recipeId, int position) => {
        'recipe_id': recipeId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'product_id': productId,
        'position': position,
      };

  factory RecipeIngredient.fromMap(Map<String, Object?> m) => RecipeIngredient(
        id: m['id'] as int?,
        recipeId: m['recipe_id'] as int?,
        name: m['name'] as String,
        quantity: (m['quantity'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        productId: m['product_id'] as int?,
      );

  /// Texte lisible, ex. « 200 g farine ».
  String get display {
    final q = quantity == null ? '' : '${formatQuantity(quantity!)} ';
    final u = (unit == null || unit!.isEmpty) ? '' : '$unit ';
    return '$q$u$name'.trim();
  }
}

class RecipeStep {
  const RecipeStep({this.id, this.recipeId, required this.number, required this.text, this.durationMin});

  final int? id;
  final int? recipeId;
  final int number;
  final String text;
  final int? durationMin;

  Map<String, Object?> toMap(int recipeId) => {
        'recipe_id': recipeId,
        'number': number,
        'text': text,
        'duration_min': durationMin,
      };

  factory RecipeStep.fromMap(Map<String, Object?> m) => RecipeStep(
        id: m['id'] as int?,
        recipeId: m['recipe_id'] as int?,
        number: m['number'] as int,
        text: m['text'] as String,
        durationMin: m['duration_min'] as int?,
      );
}

class Recipe {
  Recipe({
    this.id,
    required this.userId,
    required this.title,
    this.category,
    this.prepTimeMin,
    this.baseServings = 1,
    this.caloriesPerServing,
    this.photo,
    this.source = RecipeSource.personal,
    this.externalId,
    DateTime? createdAt,
    this.ingredients = const [],
    this.steps = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final int userId;
  final String title;
  final String? category;
  final int? prepTimeMin;
  final int baseServings;
  final double? caloriesPerServing;

  /// URL (TheMealDB) ou chemin local.
  final String? photo;
  final RecipeSource source;

  /// idMeal TheMealDB, pour éviter les imports en double.
  final String? externalId;
  final DateTime createdAt;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;

  Recipe copyWith({
    int? id,
    String? title,
    String? category,
    int? prepTimeMin,
    int? baseServings,
    double? caloriesPerServing,
    String? photo,
    List<RecipeIngredient>? ingredients,
    List<RecipeStep>? steps,
  }) =>
      Recipe(
        id: id ?? this.id,
        userId: userId,
        title: title ?? this.title,
        category: category ?? this.category,
        prepTimeMin: prepTimeMin ?? this.prepTimeMin,
        baseServings: baseServings ?? this.baseServings,
        caloriesPerServing: caloriesPerServing ?? this.caloriesPerServing,
        photo: photo ?? this.photo,
        source: source,
        externalId: externalId,
        createdAt: createdAt,
        ingredients: ingredients ?? this.ingredients,
        steps: steps ?? this.steps,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'title': title,
        'category': category,
        'prep_time_min': prepTimeMin,
        'base_servings': baseServings,
        'calories_per_serving': caloriesPerServing,
        'photo': photo,
        'source': source.dbValue,
        'external_id': externalId,
        'created_at': createdAt.toIso8601String(),
      };

  factory Recipe.fromMap(
    Map<String, Object?> m, {
    List<RecipeIngredient> ingredients = const [],
    List<RecipeStep> steps = const [],
  }) =>
      Recipe(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        title: m['title'] as String,
        category: m['category'] as String?,
        prepTimeMin: m['prep_time_min'] as int?,
        baseServings: (m['base_servings'] as int?) ?? 1,
        caloriesPerServing: (m['calories_per_serving'] as num?)?.toDouble(),
        photo: m['photo'] as String?,
        source: RecipeSource.fromDb(m['source'] as String),
        externalId: m['external_id'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        ingredients: ingredients,
        steps: steps,
      );
}

/// 1.0 -> « 1 », 0.5 -> « 0,5 », 1.333 -> « 1,33 ».
String formatQuantity(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}
