import 'package:flutter/foundation.dart';

import '../integration/gateways.dart';
import '../logic/dietary_checker.dart';
import '../logic/stock_analysis.dart';
import '../logic/text_matching.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';

enum RecipeSort {
  antiGaspi('Score anti-gaspi'),
  prepTime('Temps de préparation'),
  calories('Calories'),
  title('Titre');

  const RecipeSort(this.label);
  final String label;
}

class RecipeListItem {
  const RecipeListItem(this.recipe, this.gaspi, this.verdict);
  final Recipe recipe;
  final AntiGaspiScore gaspi;
  final DietaryVerdict verdict;
}

class RecipeListViewModel extends ChangeNotifier {
  RecipeListViewModel(this.service);

  final RecipeService service;

  bool loading = false;
  String? error;
  HouseholdProfile? profile;

  String _query = '';
  RecipeSort _sort = RecipeSort.antiGaspi;
  bool _onlyCompatible = true;
  String? _category;
  List<RecipeListItem> _all = [];

  String get query => _query;
  RecipeSort get sort => _sort;
  bool get onlyCompatible => _onlyCompatible;
  String? get category => _category;
  int get hiddenCount => _all.where((i) => !i.verdict.allowed).length;

  List<String> get categories =>
      ({for (final i in _all) if (i.recipe.category != null) i.recipe.category!}.toList()..sort());

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final recipes = await service.recipes();
      profile = await service.profile();
      List<StockSnapshot> stock;
      try {
        stock = await service.currentStock();
      } catch (_) {
        stock = const [];
      }
      final now = service.now;
      _all = [
        for (final r in recipes)
          RecipeListItem(r, antiGaspiScore(r.ingredients, stock, now), service.checker.check(r, profile!)),
      ];
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setSort(RecipeSort s) {
    _sort = s;
    notifyListeners();
  }

  void setOnlyCompatible(bool v) {
    _onlyCompatible = v;
    notifyListeners();
  }

  void setCategory(String? c) {
    _category = c;
    notifyListeners();
  }

  /// Recherche par titre ou par ingrédient (accents, pluriels et traductions
  /// français/anglais ignorés).
  static bool matches(Recipe r, String query) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    if (normalize(r.title).contains(q)) return true;
    return r.ingredients.any((i) => normalize(i.name).contains(q) || sameIngredient(i.name, query));
  }

  List<RecipeListItem> get items {
    final list = _all.where((i) {
      if (_onlyCompatible && !i.verdict.allowed) return false;
      if (_category != null && i.recipe.category != _category) return false;
      return matches(i.recipe, _query);
    }).toList();
    int nullsLast(num? a, num? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    switch (_sort) {
      case RecipeSort.antiGaspi:
        list.sort((a, b) => b.gaspi.score.compareTo(a.gaspi.score));
      case RecipeSort.prepTime:
        list.sort((a, b) => nullsLast(a.recipe.prepTimeMin, b.recipe.prepTimeMin));
      case RecipeSort.calories:
        list.sort((a, b) => nullsLast(a.recipe.caloriesPerServing, b.recipe.caloriesPerServing));
      case RecipeSort.title:
        list.sort((a, b) => normalize(a.recipe.title).compareTo(normalize(b.recipe.title)));
    }
    return list;
  }
}
