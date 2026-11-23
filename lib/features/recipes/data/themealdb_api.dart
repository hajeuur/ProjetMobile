import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../logic/calorie_estimator.dart';
import '../logic/measure_parser.dart';
import '../models/recipe.dart';

/// Erreur lisible par l'utilisateur (réseau absent, réponse invalide…).
class RecipeApiException implements Exception {
  const RecipeApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Résultat de recherche (les filtres par catégorie et ingrédient ne
/// renvoient que l'id, le nom et la vignette).
class MealSummary {
  const MealSummary({required this.id, required this.name, this.thumbnail, this.category});
  final String id;
  final String name;
  final String? thumbnail;
  final String? category;
}

/// Cache des réponses dans recipe_api_cache, pour fonctionner hors ligne.
class ApiCache {
  ApiCache(this.db);
  final Database db;

  Future<(String body, DateTime fetchedAt)?> get(String key) async {
    final rows = await db.query('recipe_api_cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return (rows.first['body'] as String, DateTime.parse(rows.first['fetched_at'] as String));
  }

  Future<void> put(String key, String body) => db.insert(
        'recipe_api_cache',
        {'key': key, 'body': body, 'fetched_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

/// Client TheMealDB (clé de test publique « 1 »).
class TheMealDbApi {
  TheMealDbApi({http.Client? client, this.cache, this.cacheTtl = const Duration(days: 7)})
      : _client = client ?? http.Client();

  static const _base = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 10);

  /// Portions supposées : TheMealDB ne les indique pas.
  static const defaultServings = 4;

  final http.Client _client;
  final ApiCache? cache;
  final Duration cacheTtl;

  Future<Map<String, dynamic>> _get(String path) async {
    final url = '$_base/$path';
    final cached = await cache?.get(url);
    if (cached != null && DateTime.now().difference(cached.$2) < cacheTtl) {
      return jsonDecode(cached.$1) as Map<String, dynamic>;
    }
    try {
      final res = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) {
        throw RecipeApiException('TheMealDB a répondu ${res.statusCode}.');
      }
      final body = utf8.decode(res.bodyBytes);
      final json = jsonDecode(body) as Map<String, dynamic>;
      await cache?.put(url, body);
      return json;
    } on RecipeApiException {
      rethrow;
    } catch (_) {
      // Hors ligne : on se rabat sur le cache, même périmé.
      if (cached != null) return jsonDecode(cached.$1) as Map<String, dynamic>;
      throw const RecipeApiException(
          'Impossible de joindre TheMealDB. Vérifiez la connexion internet.');
    }
  }

  List<Map<String, dynamic>> _meals(Map<String, dynamic> json) =>
      ((json['meals'] as List?) ?? const []).cast<Map<String, dynamic>>();

  MealSummary _summary(Map<String, dynamic> m) => MealSummary(
        id: m['idMeal'] as String,
        name: m['strMeal'] as String,
        thumbnail: m['strMealThumb'] as String?,
        category: m['strCategory'] as String?,
      );

  Future<List<MealSummary>> searchByName(String name) async =>
      _meals(await _get('search.php?s=${Uri.encodeQueryComponent(name.trim())}')).map(_summary).toList();

  Future<List<MealSummary>> filterByCategory(String category) async =>
      _meals(await _get('filter.php?c=${Uri.encodeQueryComponent(category)}')).map(_summary).toList();

  /// TheMealDB attend un ingrédient en anglais, mots séparés par « _ ».
  Future<List<MealSummary>> filterByIngredient(String ingredient) async {
    final q = ingredient.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return _meals(await _get('filter.php?i=${Uri.encodeQueryComponent(q)}')).map(_summary).toList();
  }

  Future<List<String>> categories() async {
    final json = await _get('list.php?c=list');
    return [for (final m in _meals(json)) m['strCategory'] as String]..sort();
  }

  /// Recette complète, prête à être enregistrée pour [userId].
  Future<Recipe> fetchRecipe(String id, {required int userId}) async {
    final meals = _meals(await _get('lookup.php?i=$id'));
    if (meals.isEmpty) throw const RecipeApiException('Recette introuvable sur TheMealDB.');
    return mealToRecipe(meals.first, userId: userId);
  }
}

/// Conversion d'un objet « meal » TheMealDB en [Recipe].
Recipe mealToRecipe(Map<String, dynamic> meal, {required int userId}) {
  final ingredients = <RecipeIngredient>[];
  for (var i = 1; i <= 20; i++) {
    final name = (meal['strIngredient$i'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final m = parseMeasure((meal['strMeasure$i'] as String?) ?? '');
    ingredients.add(RecipeIngredient(name: name, quantity: m.quantity, unit: m.unit));
  }
  final steps = splitInstructions((meal['strInstructions'] as String?) ?? '');
  final totalMinutes = steps.fold<int>(0, (s, e) => s + (e.durationMin ?? 0));
  final calories = estimateCalories(ingredients, TheMealDbApi.defaultServings);
  return Recipe(
    userId: userId,
    title: (meal['strMeal'] as String).trim(),
    category: meal['strCategory'] as String?,
    // Durée estimée : somme des durées citées + 10 min de préparation.
    prepTimeMin: totalMinutes > 0 ? totalMinutes + 10 : null,
    baseServings: TheMealDbApi.defaultServings,
    caloriesPerServing: calories?.perServing,
    photo: meal['strMealThumb'] as String?,
    source: RecipeSource.themealdb,
    externalId: meal['idMeal'] as String,
    ingredients: ingredients,
    steps: steps,
  );
}

final _stepHeader = RegExp(r'^(step\s*\d+|\d+[.)]?)\s*[:.-]?\s*$', caseSensitive: false);
final _stepPrefix = RegExp(r'^(step\s*\d+\s*[:.-]?|\d+[.)])\s*', caseSensitive: false);
final _duration = RegExp(r'(\d+)\s*(?:-\s*\d+\s*)?(minutes?|mins?|hours?|hrs?|heures?|h)\b', caseSensitive: false);

/// Découpe le texte d'instructions en étapes et repère les durées citées.
List<RecipeStep> splitInstructions(String text) {
  var parts = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !_stepHeader.hasMatch(l))
      .map((l) => l.replaceFirst(_stepPrefix, ''))
      .toList();
  // Un seul paragraphe : on découpe par phrases, regroupées par deux.
  if (parts.length == 1) {
    final sentences = parts.first
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    parts = [
      for (var i = 0; i < sentences.length; i += 2)
        sentences.skip(i).take(2).join(' '),
    ];
  }
  return [
    for (var i = 0; i < parts.length; i++)
      RecipeStep(number: i + 1, text: parts[i], durationMin: detectDurationMinutes(parts[i])),
  ];
}

/// Plus grande durée citée dans l'étape, en minutes (« bake for 1 hour » -> 60).
int? detectDurationMinutes(String text) {
  int? best;
  for (final m in _duration.allMatches(text)) {
    final n = int.parse(m.group(1)!);
    final unit = m.group(2)!.toLowerCase();
    final minutes = unit.startsWith('h') ? n * 60 : n;
    if (best == null || minutes > best) best = minutes;
  }
  return best;
}
