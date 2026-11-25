import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/calorie_estimator.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import 'form_pickers.dart';
import 'widgets.dart';

/// Création et édition d'une recette (ingrédients et étapes compris).
///
/// Les champs chiffrés, la catégorie et l'unité sont des [ComboTextField] :
/// on peut taper la valeur ou la choisir dans une liste (bouton ▼).
class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _IngredientRow {
  _IngredientRow([RecipeIngredient? i])
      : name = TextEditingController(text: i?.name ?? ''),
        qty = TextEditingController(text: i?.quantity == null ? '' : formatDecimal(i!.quantity!)),
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
      quantity: parseDecimal(qty.text),
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
  String? _photo;
  List<ComboOption> _categories = categoryOptions(const []);
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
    _calories = TextEditingController(text: r?.caloriesPerServing == null ? '' : formatDecimal(r!.caloriesPerServing!));
    _photo = r?.photo;
    _servings = r?.baseServings ?? 2;
    _ingredients = [for (final i in r?.ingredients ?? const <RecipeIngredient>[]) _IngredientRow(i)];
    if (_ingredients.isEmpty) _ingredients.add(_IngredientRow());
    _steps = [for (final s in r?.steps ?? const <RecipeStep>[]) _StepRow(s)];
    if (_steps.isEmpty) _steps.add(_StepRow());
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final service = context.read<RecipeService>();
    final used = await service.repository.categories(service.userId);
    if (mounted) setState(() => _categories = categoryOptions(used));
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _prep, _calories]) {
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

  List<RecipeIngredient> get _currentIngredients => [for (final r in _ingredients) ?r.toIngredient()];

  void _estimate() {
    final e = estimateCalories(_currentIngredients, _servings);
    if (e == null) {
      showSnack(context, 'Aucun ingrédient reconnu pour l\'estimation (indiquez quantités et unités).');
      return;
    }
    setState(() => _calories.text = formatDecimal(e.perServing.roundToDouble()));
    showSnack(context,
        'Estimation sur ${e.coveredIngredients}/${e.totalIngredients} ingrédients${e.reliable ? '' : ' (peu fiable)'}.');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Corrigez les champs en rouge.');
      return;
    }
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
        durationMin: parseWhole(s.duration.text),
      ));
    }
    final service = context.read<RecipeService>();
    final category = _category.text.trim();
    final base = widget.recipe ?? Recipe(userId: service.userId, title: '');
    final recipe = Recipe(
      id: base.id,
      userId: base.userId,
      title: _title.text.trim(),
      category: category.isEmpty ? null : category,
      prepTimeMin: parseWhole(_prep.text),
      baseServings: _servings,
      caloriesPerServing: parseDecimal(_calories.text),
      photo: _photo,
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
    const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);
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
          Text('Tapez une valeur ou choisissez-la dans la liste avec ▼.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titre *', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre obligatoire' : null,
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: ComboTextField(
                controller: _category,
                options: _categories,
                label: 'Catégorie',
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: ComboTextField(
                controller: _prep,
                options: prepTimeOptions,
                label: 'Temps',
                suffixText: 'min',
                keyboardType: TextInputType.number,
                validator: validateWhole,
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: ComboTextField(
                controller: _calories,
                options: calorieOptions,
                label: 'Calories par portion',
                suffixText: 'kcal',
                helperText: 'Virgule acceptée (ex. 320,5)',
                keyboardType: decimalKeyboard,
                validator: validateDecimal,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(onPressed: _estimate, icon: const Icon(Icons.calculate), label: const Text('Estimer')),
            ),
          ]),
          const SizedBox(height: 12),
          PhotoField(photo: _photo, onChanged: (p) => setState(() => _photo = p)),
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
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(children: [
                    TextFormField(
                      controller: _ingredients[k].name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: 'Ingrédient ${k + 1}', isDense: true),
                    ),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: ComboTextField(
                          controller: _ingredients[k].qty,
                          options: quantityOptions,
                          label: 'Quantité',
                          keyboardType: decimalKeyboard,
                          validator: validateDecimal,
                          dense: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ComboTextField(
                          controller: _ingredients[k].unit,
                          options: unitOptions,
                          label: 'Unité',
                          dense: true,
                        ),
                      ),
                    ]),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer',
                  onPressed: _ingredients.length == 1 ? null : () => setState(() => _ingredients.removeAt(k).dispose()),
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
                  child: TextFormField(
                    controller: _steps[k].text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Instruction'),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 92,
                  child: ComboTextField(
                    controller: _steps[k].duration,
                    options: stepMinuteOptions,
                    label: 'min',
                    keyboardType: TextInputType.number,
                    validator: validateWhole,
                    dense: true,
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
