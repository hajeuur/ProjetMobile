import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/habitual_basket.dart';
import '../logic/text_similarity.dart';
import '../models/dates.dart';
import '../services/shopping_service.dart';

/// Charge le panier type (et le recharge à chaque ticket), en respectant
/// l'interrupteur « Panier type par magasin ».
class _BasketLoader extends StatefulWidget {
  const _BasketLoader({required this.builder});
  final Widget Function(BuildContext context, HabitualBasket basket) builder;

  @override
  State<_BasketLoader> createState() => _BasketLoaderState();
}

class _BasketLoaderState extends State<_BasketLoader> {
  late final ShoppingService _service = context.read<ShoppingService>();
  HabitualBasket? _basket;
  bool _enabled = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.receiptsChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final enabled = (await _service.settings()).habitualBasket;
    final b = enabled ? await _service.habitualBasket() : null;
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _basket = b;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled || _basket == null) return const SizedBox.shrink();
    return widget.builder(context, _basket!);
  }
}

/// Carte « Panier type » : résumé (accueil Courses) ou barres (écran Prix).
class HabitualBasketCard extends StatelessWidget {
  const HabitualBasketCard({super.key, this.compact = false});

  /// Résumé en deux lignes (accueil Courses).
  final bool compact;

  @override
  Widget build(BuildContext context) => _BasketLoader(
        builder: (context, b) {
          final theme = Theme.of(context);
          void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => const HabitualBasketScreen()));
          if (b.status != BasketStatus.ok) {
            // Accueil : rien tant que le panier n'existe pas ; écran Prix : état vide explicatif.
            if (compact) return const SizedBox.shrink();
            return Card(child: _EmptyBasket(basket: b));
          }
          if (compact) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.shopping_basket_outlined),
                title: Text('${b.sentence}.'),
                subtitle: Text(
                  '${b.savingSentence}.',
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: open,
              ),
            );
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.shopping_basket_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Panier type par magasin', style: theme.textTheme.titleMedium)),
                ]),
                const SizedBox(height: 6),
                Text('${b.sentence}.'),
                const SizedBox(height: 10),
                StoreBars(basket: b),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: open, icon: const Icon(Icons.list_alt), label: const Text('Voir le détail')),
                ),
              ]),
            ),
          );
        },
      );
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket({required this.basket});
  final HabitualBasket basket;

  @override
  Widget build(BuildContext context) {
    final b = basket;
    final (title, message) = switch (b.status) {
      BasketStatus.notEnoughPurchases => (
          'Pas encore de panier habituel',
          'Il se construit tout seul avec les produits achetés au moins 3 fois en 3 mois. '
              'Continuez à enregistrer vos tickets.',
        ),
      _ => (
          'Un seul magasin à comparer',
          'Votre panier habituel (${plural(b.items.length, 'produit')}) a surtout été acheté '
              '${b.stores.isEmpty ? 'dans un seul magasin' : 'chez ${b.stores.first.storeName}'}. '
              'Ses prix ailleurs sont encore inconnus.',
        ),
    };
    return ListTile(
      leading: Icon(Icons.shopping_basket_outlined, color: Theme.of(context).colorScheme.outline),
      title: Text(title),
      subtitle: Text(message),
    );
  }
}

/// Barres horizontales : un magasin par barre, le moins cher en vert.
/// Toucher une barre affiche le détail du panier dans ce magasin.
class StoreBars extends StatefulWidget {
  const StoreBars({super.key, required this.basket, this.initiallyOpen});
  final HabitualBasket basket;
  final String? initiallyOpen;

  @override
  State<StoreBars> createState() => _StoreBarsState();
}

class _StoreBarsState extends State<StoreBars> {
  late String? _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final b = widget.basket;
    final max = b.stores.map((s) => s.total).reduce((a, c) => a > c ? a : c);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, s) in b.stores.indexed) ...[
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = _open == s.storeName ? null : s.storeName),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    s.storeName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: i == 0 ? FontWeight.bold : null),
                  ),
                ),
                Text(formatDt(s.total), style: TextStyle(fontWeight: FontWeight.bold, color: i == 0 ? Colors.green.shade700 : null)),
                Icon(_open == s.storeName ? Icons.expand_less : Icons.expand_more, size: 20),
              ]),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (_, c) => Stack(children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.total / max),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Container(
                      height: 12,
                      width: c.maxWidth * v,
                      decoration: BoxDecoration(
                        color: i == 0 ? Colors.green.shade600 : theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ]),
              ),
              if (i == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    b.savingSentence,
                    style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                  ),
                ),
              if (s.estimatedCount > 0)
                Text(
                  '${plural(s.estimatedCount, 'prix estimé', 'prix estimés')} (jamais payés dans ce magasin)',
                  style: theme.textTheme.bodySmall,
                ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _open == s.storeName ? _StoreDetail(cost: s) : const SizedBox(width: double.infinity),
        ),
      ],
    ]);
  }
}

class _StoreDetail extends StatelessWidget {
  const _StoreDetail({required this.cost});
  final StoreBasketCost cost;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          for (final l in cost.lines)
            ListTile(
              dense: true,
              title: Text(displayLabel(l.item.label)),
              subtitle: Text('${formatQuantity(l.item.avgQuantity, null)} × ${formatDt(l.unitPrice)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (l.estimated)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      'estimation',
                      style: TextStyle(color: Colors.orange.shade800, fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                Text(formatDt(l.cost), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      );
}

/// Écran détaillé : classement, composition du panier, magasins non classés.
class HabitualBasketScreen extends StatelessWidget {
  const HabitualBasketScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Panier type par magasin')),
        body: _BasketLoader(
          builder: (context, b) {
            final theme = Theme.of(context);
            if (b.status != BasketStatus.ok) {
              return ListView(padding: const EdgeInsets.all(12), children: [Card(child: _EmptyBasket(basket: b))]);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
              Text('${b.sentence}.', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: StoreBars(basket: b, initiallyOpen: b.cheapest?.storeName),
                ),
              ),
              const SizedBox(height: 8),
              Text('Mon panier habituel', style: theme.textTheme.titleMedium),
              Text(
                'Produits achetés au moins 3 fois ces 3 derniers mois, avec la quantité moyenne par achat.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Card(
                child: Column(children: [
                  for (final item in b.items)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.repeat),
                      title: Text(displayLabel(item.label)),
                      subtitle: Text('${plural(item.purchases, 'achat')} · ${formatQuantity(item.avgQuantity, null)} en moyenne'),
                    ),
                ]),
              ),
              if (b.excludedStores.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Non classés (trop peu de prix connus) : ${b.excludedStores.join(', ')}.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Coût = quantité moyenne × dernier prix payé dans le magasin. Un prix jamais payé dans un magasin '
                'est remplacé par la moyenne des autres et marqué « estimation ».',
                style: theme.textTheme.bodySmall,
              ),
            ]);
          },
        ),
      );
}
