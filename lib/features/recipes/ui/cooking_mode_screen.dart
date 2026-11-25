import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/portion_scaler.dart';
import '../models/recipe.dart';
import '../services/cooking_devices.dart';
import '../services/cooking_settings.dart';
import '../services/recipe_service.dart';
import '../viewmodels/cooking_view_model.dart';
import '../viewmodels/meal_plan_view_model.dart';
import 'slot_picker.dart';
import 'widgets.dart';

/// Mode cuisine sans les mains : passer la main au-dessus du téléphone pour
/// avancer, deux passages pour reculer ; commandes vocales ; lecture à voix
/// haute ; minuteurs.
class CookingModeScreen extends StatelessWidget {
  const CookingModeScreen({super.key, required this.recipe, required this.servings, this.mealPlanId});

  final Recipe recipe;
  final int servings;

  /// Repas planifié correspondant, s'il y en a un.
  final int? mealPlanId;

  @override
  Widget build(BuildContext context) {
    final service = context.read<RecipeService>();
    return ChangeNotifierProvider(
      create: (c) => CookingViewModel(
        title: recipe.title,
        steps: recipe.steps,
        ingredients: scaleRecipe(recipe, servings).ingredients,
        devices: c.read<CookingDevices>(),
        settingsStore: CookingSettingsStore(service.repository),
      )..start(),
      child: _CookingView(recipe: recipe, servings: servings, mealPlanId: mealPlanId),
    );
  }
}

class _CookingView extends StatelessWidget {
  const _CookingView({required this.recipe, required this.servings, this.mealPlanId});
  final Recipe recipe;
  final int servings;
  final int? mealPlanId;

  Future<void> _finish(BuildContext context) async {
    final service = context.read<RecipeService>();
    final planVm = context.read<MealPlanViewModel>();
    final ok = await confirm(
      context,
      'Repas terminé ?',
      'Le repas sera marqué « cuisiné » et les ingrédients (pour $servings portion(s)) seront retirés du stock.',
      ok: 'Marquer cuisiné',
    );
    if (!ok || !context.mounted) return;
    try {
      var planId = mealPlanId;
      if (planId == null) {
        final now = service.now;
        planId = await service.planMeal(recipeId: recipe.id!, date: now, meal: mealForTime(now), servings: servings);
      }
      final n = await service.markCooked(planId);
      await planVm.load();
      if (!context.mounted) return;
      showSnack(context, 'Bon appétit ! $n sortie(s) de stock enregistrée(s).');
      Navigator.pop(context, true);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Erreur : $e');
    }
  }

  Future<void> _mic(BuildContext context, CookingViewModel vm) async {
    if (vm.listening) {
      await vm.stopListening();
      return;
    }
    if (!vm.settings.micExplained) {
      final ok = await confirm(
        context,
        'Utiliser le micro ?',
        'PanierMalin utilise le micro uniquement pendant le mode cuisine, pour comprendre '
            '« suivant », « précédent », « répète » ou « minuteur 10 minutes » sans toucher l\'écran.',
        ok: 'Continuer',
      );
      if (!ok) return;
      await vm.updateSettings(vm.settings.copyWith(micExplained: true));
    }
    await vm.listen();
  }

  void _settings(BuildContext context, CookingViewModel vm) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: Consumer<CookingViewModel>(
          builder: (_, vm, _) {
            final s = vm.settings;
            return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  title: const Text('Geste de la main (proximité)'),
                  subtitle: Text(vm.proximityAvailable ? 'Un passage : suivant · deux : précédent' : 'Capteur absent sur ce téléphone'),
                  value: s.proximityEnabled && vm.proximityAvailable,
                  onChanged: vm.proximityAvailable ? (v) => vm.updateSettings(s.copyWith(proximityEnabled: v)) : null,
                ),
                SwitchListTile(
                  title: const Text('Commandes vocales'),
                  value: s.voiceEnabled,
                  onChanged: (v) => vm.updateSettings(s.copyWith(voiceEnabled: v)),
                ),
                SwitchListTile(
                  title: const Text('Écoute continue'),
                  subtitle: const Text('Relance le micro après chaque commande'),
                  value: s.continuousListening,
                  onChanged: s.voiceEnabled ? (v) => vm.updateSettings(s.copyWith(continuousListening: v)) : null,
                ),
                SwitchListTile(
                  title: const Text('Lecture à voix haute'),
                  value: s.readAloud,
                  onChanged: (v) => vm.updateSettings(s.copyWith(readAloud: v)),
                ),
                SwitchListTile(
                  title: const Text('Texte grand format'),
                  value: s.largeText,
                  onChanged: (v) => vm.updateSettings(s.copyWith(largeText: v)),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  void _ingredients(BuildContext context, CookingViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, sc) => ListView(controller: sc, children: [
          ListTile(
            title: Text('Ingrédients ($servings portions)', style: Theme.of(context).textTheme.titleLarge),
            trailing: IconButton(icon: const Icon(Icons.volume_up), onPressed: vm.readIngredients, tooltip: 'Lire'),
          ),
          for (final i in vm.ingredients) ListTile(leading: const Icon(Icons.circle, size: 8), title: Text(i.display, style: const TextStyle(fontSize: 20))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CookingViewModel>();
    final theme = Theme.of(context);
    final step = vm.current;
    final big = vm.settings.largeText;
    final n = vm.now;

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.list_alt), tooltip: 'Ingrédients', onPressed: () => _ingredients(context, vm)),
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Capteurs', onPressed: () => _settings(context, vm)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          LinearProgressIndicator(value: vm.steps.isEmpty ? 0 : (vm.index + 1) / vm.steps.length),
          // Indicateurs des capteurs actifs.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Text('Étape ${vm.index + 1} / ${vm.steps.length}', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (vm.settings.proximityEnabled && vm.proximityAvailable)
                const Tooltip(message: 'Geste de la main actif', child: Icon(Icons.back_hand_outlined, size: 20)),
              if (vm.settings.readAloud)
                const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.volume_up, size: 20)),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              // Balayage horizontal en secours.
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) vm.next();
                if (v > 200) vm.previous();
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    step?.text ?? 'Cette recette n\'a pas d\'étape.',
                    style: (big ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)?.copyWith(height: 1.35),
                  ),
                  if (step?.durationMin != null) ...[
                    const SizedBox(height: 20),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.timer),
                      label: Text('Minuteur ${step!.durationMin} min', style: const TextStyle(fontSize: 18)),
                      onPressed: () => vm.startTimer(Duration(minutes: step.durationMin!)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          if (vm.feedback != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer,
              padding: const EdgeInsets.all(10),
              child: Text(vm.feedback!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontSize: 16)),
            ),
          if (vm.timers.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final t in vm.timers)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        avatar: Icon(t.rang ? Icons.alarm_on : Icons.timer, color: t.rang ? Colors.red : null),
                        label: Text(
                          t.rang ? '${t.label} : terminé' : '${t.label} · ${formatDuration(t.remaining(n))}',
                          style: TextStyle(fontSize: 16, fontWeight: t.rang ? FontWeight.bold : null),
                        ),
                        onDeleted: () => vm.cancelTimer(t),
                      ),
                    ),
                ],
              ),
            ),
          if (vm.lastHeard != null)
            Text('« ${vm.lastHeard} »', style: theme.textTheme.bodySmall),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  onPressed: vm.isFirst ? null : vm.previous,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Précédent'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                iconSize: 30,
                tooltip: 'Répéter',
                onPressed: vm.repeat,
                icon: const Icon(Icons.replay),
              ),
              if (vm.settings.voiceEnabled) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 30,
                  tooltip: vm.listening ? 'Arrêter l\'écoute' : 'Commande vocale',
                  style: IconButton.styleFrom(backgroundColor: vm.listening ? Colors.red : null),
                  onPressed: () => _mic(context, vm),
                  icon: Icon(vm.listening ? Icons.mic : Icons.mic_none),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: vm.isLast
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                        onPressed: () => _finish(context),
                        icon: const Icon(Icons.check),
                        label: const Text('Terminé'),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                        onPressed: vm.next,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Suivant'),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
