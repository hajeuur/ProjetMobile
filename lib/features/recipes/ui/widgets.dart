import 'dart:io';

import 'package:flutter/material.dart';

import '../logic/stock_analysis.dart';
import '../models/recipe.dart';

/// Photo de recette : URL, fichier local ou icône par défaut.
class RecipeImage extends StatelessWidget {
  const RecipeImage(this.photo, {super.key, this.size, this.height, this.radius = 12});

  final String? photo;
  final double? size;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = height ?? size;
    final placeholder = Container(
      width: w,
      height: h,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.restaurant, size: (h ?? 48) * 0.45, color: Theme.of(context).colorScheme.outline),
    );
    Widget img;
    final p = photo;
    if (p == null || p.isEmpty) {
      img = placeholder;
    } else if (p.startsWith('http')) {
      img = Image.network(p, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    } else {
      img = Image.file(File(p), width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

Color gaspiColor(double score) {
  if (score >= 70) return Colors.green.shade600;
  if (score >= 40) return Colors.orange.shade700;
  return Colors.grey.shade600;
}

/// Pastille « anti-gaspi 75 ».
class GaspiBadge extends StatelessWidget {
  const GaspiBadge(this.score, {super.key, this.expiring = 0});
  final double score;
  final int expiring;

  @override
  Widget build(BuildContext context) {
    final c = gaspiColor(score);
    return Tooltip(
      message: 'Score anti-gaspi : part des ingrédients déjà en stock, '
          'doublée pour ceux qui périment sous 3 jours',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.eco, size: 14, color: c),
          const SizedBox(width: 3),
          Text(score.round().toString(), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
          if (expiring > 0) ...[
            const SizedBox(width: 4),
            Icon(Icons.schedule, size: 13, color: Colors.orange.shade800),
            Text('$expiring', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

/// Icône de disponibilité d'un ingrédient dans le stock.
Widget availabilityIcon(IngredientAvailability a) => switch (a) {
      IngredientAvailability.inStock =>
        const Tooltip(message: 'En stock', child: Icon(Icons.check_circle, color: Colors.green)),
      IngredientAvailability.expiringSoon =>
        Tooltip(message: 'En stock, périme bientôt', child: Icon(Icons.schedule, color: Colors.orange.shade700)),
      IngredientAvailability.missing =>
        Tooltip(message: 'Manquant', child: Icon(Icons.remove_shopping_cart, color: Colors.red.shade400)),
    };

String recipeSubtitle(Recipe r) => [
      if (r.category != null) r.category!,
      if (r.prepTimeMin != null) '${r.prepTimeMin} min',
      if (r.caloriesPerServing != null) '${r.caloriesPerServing!.round()} kcal/pers.',
    ].join(' · ');

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Supprimer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Sélecteur − n +.
class Stepper1 extends StatelessWidget {
  const Stepper1({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 30, this.suffix = ''});
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.outlined(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
          tooltip: 'Moins',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('$value$suffix', style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton.outlined(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
          tooltip: 'Plus',
        ),
      ]);
}
