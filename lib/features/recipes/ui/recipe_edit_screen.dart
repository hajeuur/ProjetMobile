import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/calorie_estimator.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import 'widgets.dart';

/// Création et édition d'une recette (ingrédients et étapes compris).
class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _IngredientRow {
  _IngredientRow([RecipeIngredient? i])
      : name = TextEditingController(text: i?.name ?? ''),
        qty = TextEditingController(text: i?.quantity == null ? '' : formatQuantity(i!.quantity!)),
        unit = TextEditingController(text: i?.unit ?? ''),
        productId = i?.productId;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController unit;
  final int? productId;

  RecipeIngredient? toIngredient() {
    if (name.text.trim().isEmpty) return null;
    return RecipeIngredient(
      name: name.text.trim(),
      quantity: double.tryParse(qty.text.trim().replaceAll(',', '.')),
      unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
      productId: productId,
    );
  }

  void dispose() {
    name.dispose();
    qty.dispose();
    unit.dispose();
  }
}

class _StepRow {
  _StepRow([RecipeStep? s])
      : text = TextEditingController(text: s?.text ?? ''),
        duration = TextEditingController(text: s?.durationMin?.toString() ?? '');
  final TextEditingController text;
  final TextEditingController duration;

  void dispose() {
    text.dispose();
    duration.dispose();
  }
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _prep;
  late final TextEditingController _calories;
  late final TextEditingController _photo;
  late int _servings;
  late final List<_IngredientRow> _ingredients;
  late final List<_StepRow> _steps;
  bool _saving = false;

  bool get _isNew => widget.recipe == null;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _title = TextEditingController(text: r?.title ?? '');
    _category = TextEditingController(text: r?.category ?? '');
    _prep = TextEditingController(text: r?.prepTimeMin?.toString() ?? '');
    _calories = TextEditingController(text: r?.caloriesPerServing?.round().toString() ?? '');
    _photo = TextEditingController(text: r?.photo ?? '');
    _servings = r?.baseServings ?? 2;
    _ingredients = [for (final i in r?.ingredients ?? const <RecipeIngredient>[]) _IngredientRow(i)];
    if (_ingredients.isEmpty) _ingredients.add(_IngredientRow());
    _steps = [for (final s in r?.steps ?? const <RecipeStep>[]) _StepRow(s)];
    if (_steps.isEmpty) _steps.add(_StepRow());
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _prep, _calories, _photo]) {
      c.dispose();
    }
    for (final i in _ingredients) {
      i.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  List<RecipeIngredient> get _currentIngredients =>
      [for (final r in _ingredients) ?r.toIngredient()];

  void _estimate() {
    final e = estimateCalories(_currentIngredients, _servings);
    if (e == null) {
      showSnack(context, 'Aucun ingrédient reconnu pour l\'estimation (indiquez quantités et unités).');
      return;
    }
    setState(() => _calories.text = e.perServing.round().toString());
    showSnack(context,
        'Estimation sur ${e.coveredIngredients}/${e.totalIngredients} ingrédients${e.reliable ? '' : ' (peu fiable)'}.');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ingredients = _currentIngredients;
    if (ingredients.isEmpty) {
      showSnack(context, 'Ajoutez au moins un ingrédient.');
      return;
    }
    final steps = <RecipeStep>[];
    for (final s in _steps) {
      if (s.text.text.trim().isEmpty) continue;
      steps.add(RecipeStep(
        number: steps.length + 1,
        text: s.text.text.trim(),
        durationMin: int.tryParse(s.duration.text.trim()),
      ));
    }
    final service = context.read<RecipeService>();
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final base = widget.recipe ?? Recipe(userId: service.userId, title: '');
    final recipe = Recipe(
      id: base.id,
      userId: base.userId,
      title: _title.text.trim(),
      category: opt(_category),
      prepTimeMin: int.tryParse(_prep.text.trim()),
      baseServings: _servings,
      caloriesPerServing: double.tryParse(_calories.text.trim().replaceAll(',', '.')),
      photo: opt(_photo),
      source: base.source,
      externalId: base.externalId,
      createdAt: base.createdAt,
      ingredients: ingredients,
      steps: steps,
    );
    setState(() => _saving = true);
    try {
      await service.saveRecipe(recipe);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e is ArgumentError ? '${e.message}' : 'Enregistrement impossible : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nouvelle recette' : 'Modifier la recette'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titre *', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre obligatoire' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Catégorie', hintText: 'Plat, Soupe, Breakfast…', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: _prep,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Temps (min)', border: OutlineInputBorder()),
                validator: (v) => (v != null && v.trim().isNotEmpty && int.tryParse(v.trim()) == null) ? 'Nombre' : null,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Portions de base'),
            const Spacer(),
            Stepper1(value: _servings, onChanged: (v) => setState(() => _servings = v)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _calories,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Calories par portion', suffixText: 'kcal', border: OutlineInputBorder()),
                validator: (v) => (v != null && v.trim().isNotEmpty && double.tryParse(v.trim().replaceAll(',', '.')) == null)
                    ? 'Nombre'
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(onPressed: _estimate, icon: const Icon(Icons.calculate), label: const Text('Estimer')),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _photo,
            decoration: const InputDecoration(labelText: 'Photo (URL)', border: OutlineInputBorder()),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 24),
          Row(children: [
            Text('Ingrédients', style: theme.textTheme.titleLarge),
            const Spacer(),
            IconButton.filledTonal(
              icon: const Icon(Icons.add),
              tooltip: 'Ajouter un ingrédient',
              onPressed: () => setState(() => _ingredients.add(_IngredientRow())),
            ),
          ]),
          for (var k = 0; k < _ingredients.length; k++)
            Padding(
              key: ObjectKey(_ingredients[k]),
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _ingredients[k].qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qté', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _ingredients[k].unit,
                    decoration: const InputDecoration(labelText: 'Unité', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _ingredients[k].name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Ingrédient', isDense: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer',
                  onPressed: _ingredients.length == 1
                      ? null
                      : () => setState(() => _ingredients.removeAt(k).dispose()),
                ),
              ]),
            ),
          const SizedBox(height: 24),
          Row(children: [
            Text('Étapes', style: theme.textTheme.titleLarge),
            const Spacer(),
            IconButton.filledTonal(
              icon: const Icon(Icons.add),
              tooltip: 'Ajouter une étape',
              onPressed: () => setState(() => _steps.add(_StepRow())),
            ),
          ]),
          for (var k = 0; k < _steps.length; k++)
            Padding(
              key: ObjectKey(_steps[k]),
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: CircleAvatar(radius: 14, child: Text('${k + 1}', style: const TextStyle(fontSize: 12))),
                ),
                Expanded(
                  child: TextField(
                    controller: _steps[k].text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Instruction'),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _steps[k].duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'min'),
                  ),
                ),
                Column(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    tooltip: 'Monter',
                    onPressed: k == 0 ? null : () => setState(() => _steps.insert(k - 1, _steps.removeAt(k))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Retirer',
                    onPressed: _steps.length == 1 ? null : () => setState(() => _steps.removeAt(k).dispose()),
                  ),
                ]),
              ]),
            ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving ? const CircularProgressIndicator() : const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
