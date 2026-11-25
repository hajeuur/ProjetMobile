import 'package:sqflite/sqflite.dart';

/// Tables de la gestion 3 — Recettes.
///
/// recipes, recipe_ingredients, recipe_steps et meal_plans (cahier des
/// charges §10), plus deux tables techniques propres à la gestion :
/// recipe_api_cache (réponses TheMealDB) et recipe_settings (capteurs activés).
///
/// `product_id` pointe vers products (gestion 2) mais n'est pas déclaré en
/// clé étrangère : la table appartient à une autre gestion et peut ne pas
/// exister tant que l'intégration n'est pas faite.
class RecipeSchema {
  RecipeSchema._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        category TEXT,
        prep_time_min INTEGER,
        base_servings INTEGER NOT NULL DEFAULT 1,
        calories_per_serving REAL,
        photo TEXT,
        source TEXT NOT NULL DEFAULT 'personal',
        external_id TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_recipes_user ON recipes(user_id)');
    await db.execute(
        'CREATE UNIQUE INDEX idx_recipes_external ON recipes(user_id, external_id) WHERE external_id IS NOT NULL');

    await db.execute('''
      CREATE TABLE recipe_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        quantity REAL,
        unit TEXT,
        product_id INTEGER,
        position INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX idx_ingredients_recipe ON recipe_ingredients(recipe_id)');

    await db.execute('''
      CREATE TABLE recipe_steps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        number INTEGER NOT NULL,
        text TEXT NOT NULL,
        duration_min INTEGER
      )''');
    await db.execute('CREATE INDEX idx_steps_recipe ON recipe_steps(recipe_id)');

    await db.execute('''
      CREATE TABLE meal_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        meal TEXT NOT NULL,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        servings INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'planned',
        cooked_at TEXT
      )''');
    await db.execute('CREATE INDEX idx_meal_plans_date ON meal_plans(date)');

    await db.execute('''
      CREATE TABLE recipe_api_cache (
        key TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE recipe_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  static Future<void> upgrade(DatabaseExecutor db, int from, int to) async {
    // Pas encore de migration : version 1.
  }
}
