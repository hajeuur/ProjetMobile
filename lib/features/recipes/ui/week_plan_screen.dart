import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../viewmodels/meal_plan_view_model.dart';
import '../viewmodels/recipe_list_view_model.dart';
import 'cooking_mode_screen.dart';
import 'menu_generation_screen.dart';
import 'recipe_detail_screen.dart';
import 'slot_picker.dart';
import 'widgets.dart';

class WeekPlanScreen extends StatelessWidget {
  const WeekPlanScreen({super.key});

  Future<void> _sendMissing(BuildContext context, MealPlanViewModel vm) async {
    try {
      final n = await vm.sendWeekMissingToShopping();
      if (context.mounted) {
        showSnack(context, n == 0 ? 'Rien ne manque pour la semaine.' : '$n article(s) envoyé(s) à la liste de courses.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Envoi impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlanViewModel>();
    final fmt = DateFormat('d MMM', 'fr_FR');
    final today = dateOnly(vm.service.now);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Ingrédients manquants de la semaine → courses',
            onPressed: vm.plannedCount == 0 ? null : () => _sendMissing(context, vm),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-planning',
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Générer le menu'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MenuGenerationScreen())),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Semaine précédente', onPressed: () => vm.goToWeek(-1)),
            Expanded(
              child: TextButton(
                onPressed: () => vm.goToWeek(0),
                child: Text('Semaine du ${fmt.format(vm.weekStart)} au ${fmt.format(addDays(vm.weekStart, 6))}'),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Semaine suivante', onPressed: () => vm.goToWeek(1)),
          ]),
        ),
        if (vm.loading) const LinearProgressIndicator(),
        if (vm.error != null) Padding(padding: const EdgeInsets.all(12), child: Text(vm.error!)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
              children: [for (final d in vm.days) _DayCard(date: d, isToday: d == today)],
            ),
          ),
        ),
      ]),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlanViewModel>();
    final theme = Theme.of(context);
    final kcal = vm.caloriesPerPerson(date);
    final target = vm.dailyTarget;
    final ratio = target == 0 ? 0.0 : kcal / target;
    final color = kcal == 0
        ? theme.colorScheme.outline
        : (ratio > 1.1 || ratio < 0.8)
            ? Colors.orange.shade700
            : Colors.green.shade600;
    return Card(
      shape: isToday
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.colorScheme.primary, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text(toBeginningOfSentenceCase(DateFormat('EEEE d', 'fr_FR').format(date)),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: isToday ? FontWeight.bold : null)),
              const Spacer(),
              Text('${kcal.round()} / ${target.round()} kcal', style: TextStyle(color: color, fontSize: 12)),
            ]),
          ),
          for (final m in MealType.values) _SlotTile(date: date, meal: m),
        ]),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.date, required this.meal});
  final DateTime date;
  final MealType meal;

  Future<void> _pickRecipe(BuildContext context) async {
    final vm = context.read<MealPlanViewModel>();
    final list = context.read<RecipeListViewModel>();
    if (list.items.isEmpty) await list.load();
    if (!context.mounted) return;
    final recipe = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, sc) {
          // Compatibles foyer, meilleurs scores anti-gaspi d'abord.
          final items = list.items.where((i) => i.verdict.allowed).toList()
            ..sort((a, b) => b.gaspi.score.compareTo(a.gaspi.score));
          return ListView(controller: sc, children: [
            ListTile(title: Text('${meal.label} — choisir une recette', style: Theme.of(context).textTheme.titleMedium)),
            for (final it in items)
              ListTile(
                leading: RecipeImage(it.recipe.photo, size: 44),
                title: Text(it.recipe.title),
                subtitle: Text(recipeSubtitle(it.recipe)),
                trailing: GaspiBadge(it.gaspi.score, expiring: it.gaspi.expiringSoon),
                onTap: () => Navigator.pop(c, it.recipe),
              ),
          ]);
        },
      ),
    );
    if (recipe != null) await vm.plan(recipe, date, meal);
  }

  Future<void> _actions(BuildContext context, MealPlan p) async {
    final vm = context.read<MealPlanViewModel>();
    final cooked = p.status == MealStatus.cooked;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(p.recipe?.title ?? 'Recette'), subtitle: Text('${meal.label} · ${p.servings} portion(s) · ${p.status.label}')),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.visibility), title: const Text('Voir la recette'), onTap: () => Navigator.pop(c, 'view')),
          if (!cooked) ...[
            ListTile(leading: const Icon(Icons.soup_kitchen), title: const Text('Mode cuisine'), onTap: () => Navigator.pop(c, 'cook')),
            ListTile(leading: const Icon(Icons.check_circle), title: const Text('Marquer comme cuisiné'), subtitle: const Text('Retire les ingrédients du stock'), onTap: () => Navigator.pop(c, 'done')),
            ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('Déplacer / portions'), onTap: () => Navigator.pop(c, 'move')),
          ],
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Retirer du planning'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'view':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: p.recipeId, initialServings: p.servings)));
        await vm.load();
      case 'cook':
        if (p.recipe == null) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => CookingModeScreen(recipe: p.recipe!, servings: p.servings, mealPlanId: p.id),
        ));
        await vm.load();
      case 'done':
        final n = await vm.markCooked(p);
        if (context.mounted) showSnack(context, 'Repas cuisiné : $n sortie(s) de stock.');
      case 'move':
        final c = await pickSlot(context, initialDate: p.date, initialMeal: p.meal, servings: p.servings, title: 'Déplacer le repas');
        if (c == null) return;
        if (c.servings != p.servings) await vm.changeServings(p, c.servings);
        if (dateKey(c.date) != dateKey(p.date) || c.meal != p.meal) {
          await vm.move(p.copyWith(servings: c.servings), c.date, c.meal);
        }
      case 'delete':
        await vm.delete(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlanViewModel>();
    final p = vm.planAt(date, meal);
    final theme = Theme.of(context);
    if (p == null) {
      return ListTile(
        dense: true,
        leading: SizedBox(width: 88, child: Text(meal.label, style: theme.textTheme.bodySmall)),
        title: Text('+ Ajouter', style: TextStyle(color: theme.colorScheme.primary)),
        onTap: () => _pickRecipe(context),
      );
    }
    final cooked = p.status == MealStatus.cooked;
    final kcal = p.recipe?.caloriesPerServing;
    return ListTile(
      dense: true,
      leading: SizedBox(width: 88, child: Text(meal.label, style: theme.textTheme.bodySmall)),
      title: Text(
        p.recipe?.title ?? '?',
        style: TextStyle(decoration: cooked ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text([
        '${p.servings} pers.',
        if (kcal != null) '${kcal.round()} kcal/pers.',
        if (cooked) 'cuisiné',
      ].join(' · ')),
      trailing: Icon(cooked ? Icons.check_circle : Icons.more_vert, color: cooked ? Colors.green : null),
      onTap: () => _actions(context, p),
    );
  }
}
