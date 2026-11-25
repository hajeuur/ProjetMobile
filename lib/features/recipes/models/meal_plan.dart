import 'recipe.dart';

enum MealType {
  breakfast('breakfast', 'Petit-déjeuner', 0.25),
  lunch('lunch', 'Déjeuner', 0.40),
  dinner('dinner', 'Dîner', 0.35);

  const MealType(this.dbValue, this.label, this.calorieShare);
  final String dbValue;
  final String label;

  /// Part de l'apport calorique journalier attribuée à ce repas.
  final double calorieShare;

  static MealType fromDb(String v) => values.firstWhere((m) => m.dbValue == v);
}

enum MealStatus {
  planned('planned', 'Prévu'),
  cooked('cooked', 'Cuisiné');

  const MealStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static MealStatus fromDb(String v) => values.firstWhere((m) => m.dbValue == v);
}

class MealPlan {
  MealPlan({
    this.id,
    required DateTime date,
    required this.meal,
    required this.recipeId,
    required this.servings,
    this.status = MealStatus.planned,
    this.cookedAt,
    this.recipe,
  }) : date = dateOnly(date);

  final int? id;
  final DateTime date;
  final MealType meal;
  final int recipeId;
  final int servings;
  final MealStatus status;
  final DateTime? cookedAt;

  /// Rempli par les requêtes qui joignent la recette.
  final Recipe? recipe;

  MealPlan copyWith({
    DateTime? date,
    MealType? meal,
    int? servings,
    MealStatus? status,
    DateTime? cookedAt,
    Recipe? recipe,
  }) =>
      MealPlan(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        recipeId: recipeId,
        servings: servings ?? this.servings,
        status: status ?? this.status,
        cookedAt: cookedAt ?? this.cookedAt,
        recipe: recipe ?? this.recipe,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': dateKey(date),
        'meal': meal.dbValue,
        'recipe_id': recipeId,
        'servings': servings,
        'status': status.dbValue,
        'cooked_at': cookedAt?.toIso8601String(),
      };

  factory MealPlan.fromMap(Map<String, Object?> m, {Recipe? recipe}) => MealPlan(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        meal: MealType.fromDb(m['meal'] as String),
        recipeId: m['recipe_id'] as int,
        servings: m['servings'] as int,
        status: MealStatus.fromDb(m['status'] as String),
        cookedAt: DateTime.tryParse(m['cooked_at'] as String? ?? ''),
        recipe: recipe,
      );
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lundi de la semaine contenant [d].
DateTime weekStartOf(DateTime d) => addDays(d, DateTime.monday - d.weekday);

/// Ajoute des jours calendaires (sans décalage au changement d'heure).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
