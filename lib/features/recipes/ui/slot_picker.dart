import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/meal_plan.dart';
import 'widgets.dart';

class SlotChoice {
  const SlotChoice(this.date, this.meal, this.servings);
  final DateTime date;
  final MealType meal;
  final int servings;
}

/// Repas correspondant à l'heure actuelle.
MealType mealForTime(DateTime t) => t.hour < 11
    ? MealType.breakfast
    : t.hour < 16
        ? MealType.lunch
        : MealType.dinner;

/// Dialogue de choix d'un jour, d'un repas et (facultatif) d'un nombre de portions.
Future<SlotChoice?> pickSlot(
  BuildContext context, {
  required DateTime initialDate,
  MealType? initialMeal,
  int? servings,
  String title = 'Planifier',
}) {
  var date = dateOnly(initialDate);
  var meal = initialMeal ?? mealForTime(DateTime.now());
  var portions = servings ?? 1;
  final fmt = DateFormat('EEEE d MMMM', 'fr_FR');
  return showDialog<SlotChoice>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(fmt.format(date)),
            onPressed: () async {
              final d = await showDatePicker(
                context: c,
                initialDate: date,
                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => date = d);
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<MealType>(
            segments: [
              for (final m in MealType.values) ButtonSegment(value: m, label: Text(m.label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {meal},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => meal = s.first),
          ),
          if (servings != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Text('Portions'),
              const Spacer(),
              Stepper1(value: portions, onChanged: (v) => setState(() => portions = v)),
            ]),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, SlotChoice(date, meal, portions)), child: const Text('Valider')),
        ],
      ),
    ),
  );
}
