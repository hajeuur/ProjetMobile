/// Comparateur de magasins à partir des tickets de l'utilisateur.
///
/// Pour chaque produit, on garde le dernier prix unitaire payé dans chaque
/// magasin (sur les 90 derniers jours). On peut alors dire où un produit a
/// été le moins cher, et estimer le coût de la liste en cours dans chaque
/// magasin. Un prix jamais relevé dans un magasin est estimé par la moyenne
/// des autres magasins et signalé comme estimation.
///
/// Remarque : la gestion 4 (Magasins) calcule le « magasin optimal » avec ses
/// relevés de prix et le coût du trajet ; ici on ne s'appuie que sur les prix
/// réellement payés (tickets de la gestion 5).
library;

import 'price_alerts.dart';
import 'text_similarity.dart';

class StorePrice {
  const StorePrice({required this.storeName, required this.unitPrice, required this.date});
  final String storeName;
  final double unitPrice;
  final DateTime date;
}

class ProductPrices {
  const ProductPrices({required this.key, required this.label, required this.prices});
  final String key;
  final String label;

  /// Un prix par magasin, du moins cher au plus cher.
  final List<StorePrice> prices;

  StorePrice get cheapest => prices.first;
  StorePrice get dearest => prices.last;

  /// Économie possible en achetant au moins cher plutôt qu'au plus cher.
  double get saving => dearest.unitPrice - cheapest.unitPrice;
}

/// Derniers prix par magasin et par produit.
Map<String, ProductPrices> latestPricesByStore(
  List<PricePoint> points, {
  required DateTime now,
  Duration window = const Duration(days: 90),
}) {
  final from = now.subtract(window);
  final byKey = <String, Map<String, PricePoint>>{};
  for (final p in points) {
    if (p.storeName == null || p.unitPrice <= 0 || p.date.isBefore(from)) continue;
    final stores = byKey.putIfAbsent(p.key, () => {});
    final previous = stores[p.storeName!];
    if (previous == null || p.date.isAfter(previous.date)) stores[p.storeName!] = p;
  }
  return {
    for (final e in byKey.entries)
      e.key: ProductPrices(
        key: e.key,
        label: (e.value.values.toList()..sort((a, b) => b.date.compareTo(a.date))).first.label,
        prices: [
          for (final p in e.value.values) StorePrice(storeName: p.storeName!, unitPrice: p.unitPrice, date: p.date),
        ]..sort((a, b) => a.unitPrice.compareTo(b.unitPrice)),
      ),
  };
}

/// Produits vendus dans au moins deux magasins, du plus gros écart au plus petit.
List<ProductPrices> comparableProducts(Map<String, ProductPrices> prices) =>
    prices.values.where((p) => p.prices.length >= 2).toList()..sort((a, b) => b.saving.compareTo(a.saving));

/// Article à chercher : libellé et produit (gestion 2) éventuel.
class BasketEntry {
  const BasketEntry({required this.label, this.productId, this.quantity = 1});
  final String label;
  final int? productId;
  final double quantity;
}

/// Retrouve l'historique de prix d'un article de liste (même produit, sinon
/// libellé ressemblant).
ProductPrices? pricesFor(BasketEntry e, Map<String, ProductPrices> prices) {
  if (e.productId != null) {
    final p = prices['p:${e.productId}'];
    if (p != null) return p;
  }
  ProductPrices? best;
  var bestScore = 0.6;
  for (final p in prices.values) {
    final s = labelSimilarity(e.label, p.label);
    if (s > bestScore) {
      bestScore = s;
      best = p;
    }
  }
  return best;
}

class StoreBasket {
  const StoreBasket({required this.storeName, required this.total, required this.known, required this.estimated});
  final String storeName;

  /// Coût estimé de la liste dans ce magasin.
  final double total;

  /// Articles dont le prix a été payé dans ce magasin.
  final int known;

  /// Articles dont le prix est estimé (moyenne des autres magasins).
  final int estimated;
}

class BasketComparison {
  const BasketComparison({required this.stores, required this.matched, required this.unknownLabels});

  /// Du moins cher au plus cher.
  final List<StoreBasket> stores;

  /// Articles de la liste avec leurs prix par magasin.
  final List<(BasketEntry, ProductPrices)> matched;

  /// Articles jamais achetés : pas de prix.
  final List<String> unknownLabels;

  StoreBasket? get best => stores.isEmpty ? null : stores.first;
}

BasketComparison compareBasket(List<BasketEntry> entries, Map<String, ProductPrices> prices) {
  final matched = <(BasketEntry, ProductPrices)>[];
  final unknown = <String>[];
  for (final e in entries) {
    final p = pricesFor(e, prices);
    if (p == null) {
      unknown.add(e.label);
    } else {
      matched.add((e, p));
    }
  }
  final storeNames = {for (final (_, p) in matched) ...p.prices.map((x) => x.storeName)};
  final baskets = <StoreBasket>[];
  for (final store in storeNames) {
    var total = 0.0;
    var known = 0;
    var estimated = 0;
    for (final (e, p) in matched) {
      final here = p.prices.where((x) => x.storeName == store);
      final qty = e.quantity <= 0 ? 1 : e.quantity;
      if (here.isNotEmpty) {
        total += here.first.unitPrice * qty;
        known++;
      } else {
        final avg = p.prices.fold<double>(0, (s, x) => s + x.unitPrice) / p.prices.length;
        total += avg * qty;
        estimated++;
      }
    }
    baskets.add(StoreBasket(storeName: store, total: total, known: known, estimated: estimated));
  }
  // Le moins cher d'abord ; à égalité, celui où l'on connaît le plus de prix.
  baskets.sort((a, b) {
    final c = a.total.compareTo(b.total);
    return c != 0 ? c : b.known.compareTo(a.known);
  });
  return BasketComparison(stores: baskets, matched: matched, unknownLabels: unknown);
}
