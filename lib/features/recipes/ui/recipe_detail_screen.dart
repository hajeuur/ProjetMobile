import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../integration/gateways.dart';
import '../logic/dietary_checker.dart';
import '../logic/portion_scaler.dart';
import '../logic/stock_analysis.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import '../viewmodels/meal_plan_view_model.dart';
import 'cooking_mode_screen.dart';
import 'recipe_edit_screen.dart';
import 'slot_picker.dart';
import 'widgets.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.initialServings});
  final int recipeId;
  final int? initialServings;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Recipe? _recipe;
  List<StockSnapshot> _stock = const [];
  DietaryVerdict? _verdict;
  int _servings = 1;
  bool _loading = true;
  bool _changed = false;
  String? _error;

  RecipeService get _service => context.read<RecipeService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _service.recipe(widget.recipeId);
      final profile = await _service.profile();
      List<StockSnapshot> stock;
      try {
        stock = await _service.currentStock();
      } catch (_) {
        stock = const [];
      }
      if (!mounted) return;
      setState(() {
        _recipe = r;
        _stock = stock;
        _verdict = r == null ? null : _service.checker.check(r, profile);
        if (_loading) _servings = widget.initialServings ?? r?.baseServings ?? 1;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendMissing(Recipe r) async {
    try {
      final n = await _service.sendMissingToShopping(r, _servings);
      if (!mounted) return;
      showSnack(context, n == 0 ? 'Rien ne manque, tout est en stock.' : '$n article(s) ajouté(s) à la liste de courses.');
    } catch (e) {
      if (mounted) showSnack(context, 'Envoi impossible : $e');
    }
  }

  Future<void> _plan(Recipe r) async {
    final c = await pickSlot(context, initialDate: _service.now, servings: _servings);
    if (c == null || !mounted) return;
    await context.read<MealPlanViewModel>().plan(r, c.date, c.meal, servings: c.servings);
    if (mounted) showSnack(context, 'Repas ajouté au planning.');
  }

  Future<void> _edit(Recipe r) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: r)));
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete(Recipe r) async {
    if (!await confirm(context, 'Supprimer la recette ?',
        '« ${r.title} » et ses repas planifiés seront supprimés.')) {
      return;
    }
    await _service.deleteRecipe(r.id!);
    if (!mounted) return;
    context.read<MealPlanViewModel>().load();
    Navigator.pop(context, true);
  }

  Future<void> _cook(Recipe r) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CookingModeScreen(recipe: r, servings: _servings)));
    _changed = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _recipe;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(r?.title ?? 'Recette'),
          actions: [
            if (r != null) ...[
              IconButton(icon: const Icon(Icons.edit), tooltip: 'Modifier', onPressed: () => _edit(r)),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Supprimer', onPressed: () => _delete(r)),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : r == null
                ? Center(child: Text(_error ?? 'Recette introuvable.'))
                : _body(r),
        bottomNavigationBar: r == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.soup_kitchen),
                    label: const Text('Mode cuisine'),
                    onPressed: r.steps.isEmpty ? null : () => _cook(r),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _body(Recipe r) {
    final scaled = scaleRecipe(r, _servings);
    final now = _service.now;
    final statuses = [for (final i in scaled.ingredients) ingredientStatus(i, _stock, now)];
    final missing = statuses.where((s) => s.availability == IngredientAvailability.missing).length;
    final gaspi = antiGaspiScore(r.ingredients, _stock, now);
    final theme = Theme.of(context);

    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      RecipeImage(r.photo, height: 200, radius: 0),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (r.category != null) Chip(label: Text(r.category!)),
            if (r.prepTimeMin != null) Chip(avatar: const Icon(Icons.timer, size: 18), label: Text('${r.prepTimeMin} min')),
            Chip(avatar: const Icon(Icons.public, size: 18), label: Text(r.source.label)),
            GaspiBadge(gaspi.score, expiring: gaspi.expiringSoon),
          ]),
          if (_verdict != null && !_verdict!.allowed)
            Card(
              color: theme.colorScheme.errorContainer,
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
                title: Text('Non compatible avec le foyer', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                subtitle: Text(_verdict!.reasons.join('\n'), style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Text('Portions', style: theme.textTheme.titleMedium),
            const Spacer(),
            Stepper1(value: _servings, onChanged: (v) => setState(() => _servings = v)),
          ]),
          if (scaled.caloriesPerServing != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${scaled.caloriesPerServing!.round()} kcal par portion · ${scaled.totalCalories!.round()} kcal au total',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Text('Ingrédients', style: theme.textTheme.titleLarge),
            const Spacer(),
            if (missing > 0) Text('$missing manquant(s)', style: TextStyle(color: theme.colorScheme.error)),
          ]),
        ]),
      ),
      for (final s in statuses)
        ListTile(
          dense: true,
          leading: availabilityIcon(s.availability),
          title: Text(s.ingredient.display),
          subtitle: s.matches.isEmpty ? null : Text('Stock : ${s.matches.map((m) => m.name).join(', ')}'),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Manquants → liste de courses'),
            onPressed: missing == 0 ? null : () => _sendMissing(r),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month),
            label: const Text('Planifier'),
            onPressed: () => _plan(r),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Étapes', style: theme.textTheme.titleLarge),
      ),
      if (r.steps.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune étape.')),
      for (final s in r.steps)
        ListTile(
          leading: CircleAvatar(child: Text('${s.number}')),
          title: Text(s.text),
          subtitle: s.durationMin == null ? null : Text('⏱ ${s.durationMin} min'),
        ),
    ]);
  }
}
