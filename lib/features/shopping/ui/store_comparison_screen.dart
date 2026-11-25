import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/store_comparison.dart';
import '../logic/text_similarity.dart';
import '../models/dates.dart';
import '../models/shopping_list.dart';
import '../services/shopping_service.dart';
import 'widgets.dart';

/// Comparateur de magasins : où la liste en cours coûte le moins cher, et où
/// chaque produit a été payé le moins cher, d'après vos tickets.
class StoreComparisonScreen extends StatefulWidget {
  const StoreComparisonScreen({super.key, this.listId, this.focusKey});

  /// Liste à chiffrer (sinon la liste en cours la plus récente).
  final int? listId;

  /// Produit à mettre en avant (depuis une alerte de prix).
  final String? focusKey;

  @override
  State<StoreComparisonScreen> createState() => _StoreComparisonScreenState();
}

class _Data {
  const _Data(this.list, this.basket, this.prices);
  final ShoppingList? list;
  final BasketComparison? basket;
  final Map<String, ProductPrices> prices;
}

class _StoreComparisonScreenState extends State<StoreComparisonScreen> {
  late final Future<_Data> _future = _load();

  Future<_Data> _load() async {
    final service = context.read<ShoppingService>();
    ShoppingList? list;
    if (widget.listId != null) {
      list = await service.list(widget.listId!);
    } else {
      final active = await service.lists(status: ListStatus.active);
      list = active.isEmpty ? null : active.first;
    }
    final basket = list == null ? null : await service.compareListStores(list.id!);
    return _Data(list, basket, await service.storePrices());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Comparateur de magasins')),
        body: FutureBuilder<_Data>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return EmptyState(icon: Icons.error_outline, title: 'Comparaison impossible : ${snap.error}');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final d = snap.data!;
            final products = comparableProducts(d.prices);
            final focus = widget.focusKey == null ? null : d.prices[widget.focusKey];
            return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
              Text(
                'D\'après les prix que vous avez payés ces 3 derniers mois (vos tickets). '
                'Un prix jamais relevé dans un magasin est estimé par la moyenne des autres.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (focus != null) ...[
                const SizedBox(height: 12),
                _ProductCard(product: focus, highlighted: true),
              ],
              if (d.basket != null && d.list != null) ...[
                const SizedBox(height: 16),
                Text('« ${d.list!.name} » dans chaque magasin', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                _BasketSection(basket: d.basket!),
              ],
              const SizedBox(height: 16),
              Text('Produit par produit', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Pas encore de produit acheté dans au moins deux magasins.'),
                )
              else
                for (final p in products)
                  if (p.key != widget.focusKey) _ProductCard(product: p),
            ]);
          },
        ),
      );
}

class _BasketSection extends StatelessWidget {
  const _BasketSection({required this.basket});
  final BasketComparison basket;

  @override
  Widget build(BuildContext context) {
    if (basket.stores.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Aucun article de la liste n\'a encore de prix connu.'),
        ),
      );
    }
    final best = basket.best!;
    final worst = basket.stores.last;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        color: Colors.green.withValues(alpha: 0.12),
        child: ListTile(
          leading: Icon(Icons.emoji_events, color: Colors.green.shade700),
          title: Text('Le moins cher pour vous : ${best.storeName}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${formatDt(best.total)} pour ${plural(basket.matched.length, 'article')} chiffrés'
            '${basket.stores.length > 1 ? ' · ${formatDt(worst.total - best.total)} d\'économie par rapport à ${worst.storeName}' : ''}',
          ),
        ),
      ),
      for (final s in basket.stores)
        Card(
          child: ListTile(
            dense: true,
            leading: StoreAvatar(name: s.storeName),
            title: Text(s.storeName),
            subtitle: Text(
              '${plural(s.known, 'prix connu', 'prix connus')}'
              '${s.estimated > 0 ? ' · ${plural(s.estimated, 'prix estimé', 'prix estimés')}' : ''}',
            ),
            trailing: Text(formatDt(s.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      if (basket.unknownLabels.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            'Jamais achetés, donc non chiffrés : ${basket.unknownLabels.join(', ')}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ]);
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, this.highlighted = false});
  final ProductPrices product;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final single = p.prices.length < 2;
    return Card(
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(displayLabel(p.label), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(p.prices.map((x) => '${x.storeName} ${formatDt(x.unitPrice)}').join('  ·  ')),
          const SizedBox(height: 4),
          Text(
            single
                ? 'Acheté seulement chez ${p.cheapest.storeName} : pas encore de comparaison possible.'
                : 'Le moins cher pour vous : ${p.cheapest.storeName} (${formatDt(p.saving)} de moins qu\'à ${p.dearest.storeName}).',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: single ? Theme.of(context).colorScheme.outline : Colors.green.shade700,
            ),
          ),
        ]),
      ),
    );
  }
}
