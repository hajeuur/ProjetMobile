import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/purchase_suggestions.dart';
import '../services/shopping_service.dart';

/// Suggestions intelligentes (accueil Courses et détail d'une liste) :
/// « Tu achètes « Lait » tous les 6 jours, l'ajouter ? » avec Ajouter /
/// Pas maintenant / Ne plus proposer. N'affiche rien sans suggestion.
class SuggestionsCard extends StatefulWidget {
  const SuggestionsCard({super.key, this.listId, this.revision = 0, this.onAdded, this.max = 3});

  /// Liste cible ; null = liste en cours.
  final int? listId;

  /// Change quand les articles de la liste changent : recalcul.
  final int revision;

  /// Un article vient d'être ajouté (ou retiré par « Annuler »).
  final VoidCallback? onAdded;

  /// Nombre de suggestions affichées (accueil : la plus sûre seulement).
  final int max;

  @override
  State<SuggestionsCard> createState() => _SuggestionsCardState();
}

class _SuggestionsCardState extends State<SuggestionsCard> {
  late final ShoppingService _service = context.read<ShoppingService>();
  List<Suggestion> _items = const [];
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.receiptsChanged.listen((_) => _load());
  }

  @override
  void didUpdateWidget(SuggestionsCard old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || old.listId != widget.listId) _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _service.suggestions(listId: widget.listId, max: widget.max);
      if (mounted) setState(() => _items = s);
    } catch (_) {
      if (mounted) setState(() => _items = const []); // jamais bloquant
    }
  }

  Future<void> _act(Suggestion s, Future<void> Function() action, String message, {VoidCallback? undo}) async {
    setState(() => _items = [..._items]..remove(s));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Action impossible : $e')));
      return _load();
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: undo == null ? null : SnackBarAction(label: 'Annuler', onPressed: undo),
        ),
      );
    await _load();
  }

  Future<void> _add(Suggestion s) async {
    late ({int listId, int itemId}) added;
    await _act(
      s,
      () async {
        added = await _service.acceptSuggestion(s, listId: widget.listId);
        widget.onAdded?.call();
      },
      '« ${s.label} » ajouté à la liste',
      undo: () async {
        await _service.removeItem(added.itemId);
        widget.onAdded?.call();
        await _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text('Suggestions', style: theme.textTheme.titleMedium)),
              ],
            ),
            for (final s in _items)
              _SuggestionTile(
                s,
                onAdd: () => _add(s),
                onLater: () =>
                    _act(s, () => _service.snoozeSuggestion(s), 'D\'accord, je te le reproposerai plus tard.'),
                onNever: () => _act(s, () => _service.neverSuggest(s), '« ${s.label} » ne sera plus proposé.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile(this.s, {required this.onAdd, required this.onLater, required this.onNever});
  final Suggestion s;
  final VoidCallback onAdd;
  final VoidCallback onLater;
  final VoidCallback onNever;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.sentence, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(s.detail, style: theme.textTheme.bodySmall),
              ConfidenceChip(s.level),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Ajouter')),
              TextButton(onPressed: onLater, child: const Text('Pas maintenant')),
              TextButton(onPressed: onNever, child: const Text('Ne plus proposer')),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Confiance élevée » (vert), « moyenne » (orange), « faible » (gris).
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.level, {super.key});
  final ConfidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = switch (level) {
      ConfidenceLevel.high => dark ? Colors.green.shade300 : Colors.green.shade800,
      ConfidenceLevel.medium => dark ? Colors.orange.shade300 : Colors.orange.shade800,
      ConfidenceLevel.low => dark ? Colors.grey.shade400 : Colors.grey.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Confiance ${level.label}',
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}
