import 'package:sqflite/sqflite.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';

/// Accès à la base pour les tables de la gestion 3. Seul ce fichier écrit dans
/// recipes, recipe_ingredients, recipe_steps et meal_plans.
class RecipeRepository {
  RecipeRepository(this.db);

  final Database db;

  // ---------------------------------------------------------------- Recettes

  /// Insère la recette avec ses ingrédients et ses étapes ; renvoie son id.
  Future<int> insertRecipe(Recipe recipe) => db.transaction((txn) async {
        final map = recipe.toMap()..remove('id');
        final id = await txn.insert('recipes', map);
        await _writeChildren(txn, id, recipe);
        return id;
      });

  Future<void> updateRecipe(Recipe recipe) async {
    final id = recipe.id;
    if (id == null) throw ArgumentError('Recette sans id');
    await db.transaction((txn) async {
      await txn.update('recipes', recipe.toMap()..remove('id'), where: 'id = ?', whereArgs: [id]);
      await txn.delete('recipe_ingredients', where: 'recipe_id = ?', whereArgs: [id]);
      await txn.delete('recipe_steps', where: 'recipe_id = ?', whereArgs: [id]);
      await _writeChildren(txn, id, recipe);
    });
  }

  Future<void> _writeChildren(Transaction txn, int id, Recipe recipe) async {
    final batch = txn.batch();
    for (var i = 0; i < recipe.ingredients.length; i++) {
      batch.insert('recipe_ingredients', recipe.ingredients[i].toMap(id, i));
    }
    for (final s in recipe.steps) {
      batch.insert('recipe_steps', s.toMap(id));
    }
    await batch.commit(noResult: true);
  }

  /// Supprime la recette ; ingrédients, étapes et repas planifiés suivent
  /// (ON DELETE CASCADE).
  Future<void> deleteRecipe(int id) => db.delete('recipes', where: 'id = ?', whereArgs: [id]);

  Future<Recipe?> getRecipe(int id) async {
    final rows = await db.query('recipes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return (await _hydrate(rows)).first;
  }

  Future<Recipe?> findByExternalId(int userId, String externalId) async {
    final rows = await db.query('recipes',
        where: 'user_id = ? AND external_id = ?', whereArgs: [userId, externalId]);
    if (rows.isEmpty) return null;
    return (await _hydrate(rows)).first;
  }

  Future<Set<String>> importedExternalIds(int userId) async {
    final rows = await db.query('recipes',
        columns: ['external_id'], where: 'user_id = ? AND external_id IS NOT NULL', whereArgs: [userId]);
    return {for (final r in rows) r['external_id'] as String};
  }

  /// Toutes les recettes de l'utilisateur, avec ingrédients et étapes.
  Future<List<Recipe>> listRecipes(int userId) async {
    final rows = await db.query('recipes',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'title COLLATE NOCASE');
    return _hydrate(rows);
  }

  Future<int> countRecipes(int userId) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM recipes WHERE user_id = ?', [userId]);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<List<String>> categories(int userId) async {
    final rows = await db.rawQuery(
        'SELECT DISTINCT category FROM recipes WHERE user_id = ? AND category IS NOT NULL ORDER BY category',
        [userId]);
    return [for (final r in rows) r['category'] as String];
  }

  /// Charge ingrédients et étapes en deux requêtes pour toute la liste.
  Future<List<Recipe>> _hydrate(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final ids = [for (final r in rows) r['id'] as int];
    final placeholders = List.filled(ids.length, '?').join(',');
    final ingRows = await db.query('recipe_ingredients',
        where: 'recipe_id IN ($placeholders)', whereArgs: ids, orderBy: 'recipe_id, position');
    final stepRows = await db.query('recipe_steps',
        where: 'recipe_id IN ($placeholders)', whereArgs: ids, orderBy: 'recipe_id, number');
    final ings = <int, List<RecipeIngredient>>{};
    for (final r in ingRows) {
      ings.putIfAbsent(r['recipe_id'] as int, () => []).add(RecipeIngredient.fromMap(r));
    }
    final steps = <int, List<RecipeStep>>{};
    for (final r in stepRows) {
      steps.putIfAbsent(r['recipe_id'] as int, () => []).add(RecipeStep.fromMap(r));
    }
    return [
      for (final r in rows)
        Recipe.fromMap(r, ingredients: ings[r['id']] ?? const [], steps: steps[r['id']] ?? const []),
    ];
  }

  // ----------------------------------------------------------------- Planning

  Future<int> insertMealPlan(MealPlan plan) => db.insert('meal_plans', plan.toMap()..remove('id'));

  Future<void> updateMealPlan(MealPlan plan) =>
      db.update('meal_plans', plan.toMap()..remove('id'), where: 'id = ?', whereArgs: [plan.id]);

  Future<void> deleteMealPlan(int id) => db.delete('meal_plans', where: 'id = ?', whereArgs: [id]);

  Future<MealPlan?> getMealPlan(int id) async {
    final rows = await db.query('meal_plans', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final recipe = await getRecipe(rows.first['recipe_id'] as int);
    return MealPlan.fromMap(rows.first, recipe: recipe);
  }

  /// Repas planifiés de l'utilisateur entre [from] et [to] inclus, recette
  /// complète jointe.
  Future<List<MealPlan>> mealPlansBetween(int userId, DateTime from, DateTime to) async {
    final rows = await db.rawQuery('''
      SELECT mp.* FROM meal_plans mp
      JOIN recipes r ON r.id = mp.recipe_id
      WHERE r.user_id = ? AND mp.date BETWEEN ? AND ?
      ORDER BY mp.date, mp.meal''', [userId, dateKey(from), dateKey(to)]);
    if (rows.isEmpty) return [];
    final recipeIds = {for (final r in rows) r['recipe_id'] as int}.toList();
    final placeholders = List.filled(recipeIds.length, '?').join(',');
    final recipes = await _hydrate(
        await db.query('recipes', where: 'id IN ($placeholders)', whereArgs: recipeIds));
    final byId = {for (final r in recipes) r.id!: r};
    return [for (final r in rows) MealPlan.fromMap(r, recipe: byId[r['recipe_id']])];
  }

  /// Supprime les repas encore « prévus » de la période (avant régénération).
  Future<int> deletePlannedBetween(int userId, DateTime from, DateTime to) => db.rawDelete('''
      DELETE FROM meal_plans WHERE status = 'planned' AND date BETWEEN ? AND ?
      AND recipe_id IN (SELECT id FROM recipes WHERE user_id = ?)''', [dateKey(from), dateKey(to), userId]);

  // ------------------------------------------------------------ Statistiques

  /// Recettes les plus cuisinées : (recette, nombre de fois).
  Future<List<(String title, int count)>> mostCooked(int userId, {int limit = 5}) async {
    final rows = await db.rawQuery('''
      SELECT r.title AS title, COUNT(*) AS n FROM meal_plans mp
      JOIN recipes r ON r.id = mp.recipe_id
      WHERE r.user_id = ? AND mp.status = 'cooked'
      GROUP BY r.id ORDER BY n DESC, r.title LIMIT ?''', [userId, limit]);
    return [for (final r in rows) (r['title'] as String, r['n'] as int)];
  }

  // -------------------------------------------------------------- Réglages

  Future<String?> getSetting(String key) async {
    final rows = await db.query('recipe_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db.insert(
      'recipe_settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
