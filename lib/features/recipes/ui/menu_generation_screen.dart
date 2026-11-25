import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/menu_generator.dart';
import '../models/meal_plan.dart';
import '../viewmodels/meal_plan_view_model.dart';
import 'widgets.dart';

/// Génération du menu de la semaine : options, aperçu, puis enregistrement.
class MenuGenerationScreen extends StatefulWidget {
  const MenuGenerationScreen({super.key});

  @override
  State<MenuGenerationScreen> createState() => _MenuGenerationScreenState();
}

class _MenuGenerationScreenState extends State<MenuGenerationScreen> {
  bool _onlyEmpty = true;
  late int _servings;
  GeneratedMenu? _menu;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servings = context.read<MealPlanViewModel>().defaultServings;
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await context.read<MealPlanViewModel>().propose(onlyEmptySlots: _onlyEmpty, servings: _servings);
      if (mounted) setState(() => _menu = m);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final m = _menu;
    if (m == null || m.entries.isEmpty) return;
    setState(() => _busy = true);
    await context.read<MealPlanViewModel>().apply(m, replacePlanned: !_onlyEmpty);
    if (!mounted) return;
    showSnack(context, '${m.entries.length} repas ajoutés au planning.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlanViewModel>();
    final theme = Theme.of(context);
    final m = _menu;
    final dayFmt = DateFormat('EEEE d', 'fr_FR');

    // Regroupement par jour.
    final byDay = <String, List<MenuEntry>>{};
    for (final e in m?.entries ?? const <MenuEntry>[]) {
      byDay.putIfAbsent(dateKey(e.slot.date), () => []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Générer le menu')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.check),
            label: Text(m == null ? 'Appliquer' : 'Appliquer (${m.entries.length} repas)'),
            onPressed: _busy || m == null || m.entries.isEmpty ? null : _apply,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Garder les repas déjà planifiés'),
              subtitle: Text(_onlyEmpty ? 'Seuls les créneaux vides sont remplis' : 'Les repas « prévus » sont remplacés'),
              value: _onlyEmpty,
              onChanged: (v) {
                setState(() => _onlyEmpty = v);
                _generate();
              },
            ),
            ListTile(
              title: const Text('Portions par repas'),
              trailing: Stepper1(
                value: _servings,
                onChanged: (v) {
                  setState(() => _servings = v);
                  _generate();
                },
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(
                'Objectif : ${vm.dailyTarget.round()} kcal/jour/personne · allergies : '
                '${vm.profile?.allergies.join(', ') ?? '-'} · régimes : ${vm.profile?.diets.join(', ') ?? '-'}',
              ),
              subtitle: const Text('Priorité aux produits qui périment bientôt, aucune recette répétée dans la semaine.'),
            ),
          ]),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        if (m != null && m.entries.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucun créneau à remplir ou aucune recette compatible disponible.', textAlign: TextAlign.center),
          ),
        for (final entry in byDay.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Row(children: [
              Text(toBeginningOfSentenceCase(dayFmt.format(entry.value.first.slot.date)), style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${entry.value.fold<double>(0, (s, e) => s + (e.recipe.caloriesPerServing ?? 0)).round()} kcal/pers.',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
          for (final e in entry.value)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                leading: RecipeImage(e.recipe.photo, size: 44),
                title: Text(e.recipe.title),
                subtitle: Text('${e.slot.meal.label} · '
                    '${e.recipe.caloriesPerServing?.round() ?? '?'} kcal (cible ${e.targetCalories.round()})'),
                trailing: GaspiBadge(e.antiGaspi),
              ),
            ),
        ],
        if (m != null && m.unfilled.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${m.unfilled.length} créneau(x) laissé(s) vide(s) : pas assez de recettes compatibles '
              'différentes. Importez-en depuis TheMealDB pour compléter la semaine.',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
      ]),
    );
  }
}
