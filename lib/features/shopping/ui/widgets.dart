import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../logic/budget_forecast.dart';
import '../models/shopping_list.dart';

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String errorText(Object e) => e is ArgumentError ? '${e.message}' : '$e';

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

/// Boîte de dialogue à un champ texte.
///
/// Le contrôleur appartient à l'état du dialogue : il n'est libéré qu'une
/// fois l'animation de fermeture terminée (le libérer juste après
/// `showDialog` fait planter Flutter pendant cette animation).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Nom',
  String ok = 'Valider',
  TextInputType? keyboardType,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(title: title, initial: initial, label: label, ok: ok, keyboardType: keyboardType),
    );

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial, required this.label, required this.ok, this.keyboardType});
  final String title;
  final String initial;
  final String label;
  final String ok;
  final TextInputType? keyboardType;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  // Texte proposé tout sélectionné : taper le remplace au lieu de s'y ajouter.
  late final _ctrl = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: Text(widget.ok)),
        ],
      );
}

/// Lecture d'un nombre saisi en français (« 12,350 » ou « 12.350 »).
double? parseNumber(String s) => double.tryParse(s.trim().replaceAll(' ', '').replaceAll(',', '.'));

IconData originIcon(ItemOrigin o) => switch (o) {
      ItemOrigin.manual => Icons.edit_note,
      ItemOrigin.shortage => Icons.inventory_2_outlined,
      ItemOrigin.recipe => Icons.restaurant_menu,
      ItemOrigin.voice => Icons.mic,
      ItemOrigin.forgotten => Icons.history,
      ItemOrigin.suggestion => Icons.lightbulb_outline,
    };

/// Pastille « Rupture prévue » / « Recette ».
class OriginChip extends StatelessWidget {
  const OriginChip(this.origin, {super.key});
  final ItemOrigin origin;

  @override
  Widget build(BuildContext context) {
    if (origin == ItemOrigin.manual) return const SizedBox.shrink();
    final c = switch (origin) {
      ItemOrigin.shortage => Colors.orange.shade800,
      ItemOrigin.voice => Colors.indigo.shade400,
      ItemOrigin.forgotten => Colors.deepPurple.shade400,
      ItemOrigin.suggestion => Colors.amber.shade800,
      _ => Colors.teal.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(originIcon(origin), size: 12, color: c),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            origin.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

Color budgetColor(BuildContext context, BudgetLevel level, {bool forecast = false}) => switch (level) {
      BudgetLevel.exceeded => Colors.red.shade600,
      BudgetLevel.threshold => Colors.orange.shade700,
      BudgetLevel.ok => forecast ? Colors.amber.shade800 : Colors.green.shade600,
      BudgetLevel.none => Theme.of(context).colorScheme.outline,
    };

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Photo du ticket (fichier local) ou icône.
class ReceiptPhoto extends StatelessWidget {
  const ReceiptPhoto(this.path, {super.key, this.height = 180});
  final String? path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.receipt_long, size: 48, color: Theme.of(context).colorScheme.outline),
    );
    if (path == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path!),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Indicateur chiffré (« Panier moyen 32,500 DT »).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) Icon(icon, size: 16, color: color ?? Theme.of(context).colorScheme.primary),
              if (icon != null) const SizedBox(width: 6),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
            ]),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
          ]),
        ),
      );
}

/// Pastille d'un magasin : icône selon son type (gestion 4) et couleur stable
/// tirée de son nom, pour reconnaître les enseignes d'un coup d'œil.
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({super.key, this.name, this.type});
  final String? name;
  final String? type;

  static const _colors = [
    Color(0xFF1565C0), Color(0xFFC62828), Color(0xFF2E7D32), Color(0xFFEF6C00),
    Color(0xFF6A1B9A), Color(0xFF00838F), Color(0xFF4E342E),
  ];

  static IconData iconFor(String? type, String? name) {
    final t = '${type ?? ''} ${name ?? ''}'.toLowerCase();
    if (t.contains('march')) return Icons.storefront;
    if (t.contains('picerie')) return Icons.local_convenience_store;
    if (t.contains('super') || t.contains('carrefour') || t.contains('monoprix') || t.contains('géant')) {
      return Icons.local_grocery_store;
    }
    return name == null ? Icons.receipt_long : Icons.store_mall_directory;
  }

  @override
  Widget build(BuildContext context) {
    final n = name ?? '';
    final c = n.isEmpty ? Theme.of(context).colorScheme.outline : _colors[n.codeUnits.fold<int>(0, (s, x) => s + x) % _colors.length];
    return CircleAvatar(
      backgroundColor: c.withValues(alpha: 0.15),
      child: Icon(iconFor(type, name), color: c),
    );
  }
}

/// Écran toujours allumé (mode magasin, panier en direct).
Future<void> keepScreenOn(bool on) async {
  try {
    on ? await WakelockPlus.enable() : await WakelockPlus.disable();
  } catch (_) {
    // Plateforme sans wakelock (tests) : sans conséquence.
  }
}
