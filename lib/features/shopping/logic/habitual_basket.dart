/// Panier type par magasin.
///
/// 1. **Panier habituel** : produits achetés au moins [minPurchases] fois
///    (tickets différents) sur les [window] derniers jours, avec leur
///    quantité moyenne par achat.
/// 2. **Coût dans chaque magasin** : quantité moyenne × dernier prix payé
///    dans ce magasin ; sinon prix moyen des autres magasins, marqué
///    « estimation ».
/// 3. **Classement** du moins cher au plus cher. Un magasin dont moins de
///    [minCoverage] des prix sont connus n'est pas classé (son total serait
///    surtout fait d'estimations) : il est listé à part.
library;

import 'budget_forecast.dart' show shortDt;
import 'price_alerts.dart';
import 'store_comparison.dart';

class HabitualItem {
  const HabitualItem({required this.key, required this.label, required this.purchases, required this.avgQuantity});
  final String key;
  final String label;

  /// Nombre d'achats (tickets) sur la période.
  final int purchases;

  /// Quantité moyenne par achat.
  final double avgQuantity;
}

class BasketLine {
  const BasketLine({required this.item, required this.unitPrice, required this.estimated});
  final HabitualItem item;
  final double unitPrice;

  /// Prix jamais payé dans ce magasin : moyenne des autres magasins.
  final bool estimated;

  double get cost => unitPrice * item.avgQuantity;
}

class StoreBasketCost {
  const StoreBasketCost({required this.storeName, required this.lines});
  final String storeName;
  final List<BasketLine> lines;

  double get total => lines.fold(0.0, (s, l) => s + l.cost);
  int get knownCount => lines.where((l) => !l.estimated).length;
  int get estimatedCount => lines.where((l) => l.estimated).length;

  /// Part des prix réellement payés dans ce magasin.
  double get coverage => lines.isEmpty ? 0 : knownCount / lines.length;
}

enum BasketStatus {
  ok,

  /// Aucun produit acheté assez souvent.
  notEnoughPurchases,

  /// Un seul magasin comparable : pas de classement possible.
  notEnoughStores,
}

class HabitualBasket {
  const HabitualBasket({
    required this.status,
    this.items = const [],
    this.stores = const [],
    this.excludedStores = const [],
  });

  final BasketStatus status;
  final List<HabitualItem> items;

  /// Magasins classés, du moins cher au plus cher.
  final List<StoreBasketCost> stores;

  /// Magasins avec trop peu de prix connus pour être classés.
  final List<String> excludedStores;

  StoreBasketCost? get cheapest => stores.isEmpty ? null : stores.first;
  StoreBasketCost? get dearest => stores.length < 2 ? null : stores.last;

  /// Économie en allant au moins cher plutôt qu'au plus cher.
  double get saving => dearest == null ? 0 : dearest!.total - cheapest!.total;

  /// « Ton panier habituel coûte 46 DT chez Carrefour, 51 DT chez Monoprix ».
  String get sentence {
    if (status != BasketStatus.ok) return '';
    final parts = [for (final s in stores.take(3)) '${shortDt(s.total)} chez ${s.storeName}'];
    return 'Ton panier habituel coûte ${parts.join(', ')}';
  }

  /// « Tu économises 5 DT par rapport à Monoprix ».
  String get savingSentence {
    if (dearest == null || saving < 0.05) return 'Les prix sont équivalents dans ces magasins.';
    return 'Tu économises ${shortDt(saving)} par rapport à ${dearest!.storeName}';
  }
}

HabitualBasket buildHabitualBasket(
  List<PricePoint> points, {
  required DateTime now,
  int minPurchases = 3,
  Duration window = const Duration(days: 90),
  double minCoverage = 0.4,
}) {
  final from = now.subtract(window);
  final recent = [for (final p in points) if (!p.date.isBefore(from) && p.unitPrice > 0) p];

  // 1. Produits achetés assez souvent (un achat = un ticket).
  final byKey = <String, List<PricePoint>>{};
  for (final p in recent) {
    byKey.putIfAbsent(p.key, () => []).add(p);
  }
  final items = <HabitualItem>[];
  for (final e in byKey.entries) {
    final perReceipt = <Object, double>{};
    for (final p in e.value) {
      final id = p.receiptId ?? '${p.date.toIso8601String()}|${p.storeName}';
      perReceipt[id] = (perReceipt[id] ?? 0) + (p.quantity <= 0 ? 1 : p.quantity);
    }
    if (perReceipt.length < minPurchases) continue;
    final latest = e.value.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    items.add(HabitualItem(
      key: e.key,
      label: latest.label,
      purchases: perReceipt.length,
      avgQuantity: perReceipt.values.reduce((a, b) => a + b) / perReceipt.length,
    ));
  }
  if (items.isEmpty) return const HabitualBasket(status: BasketStatus.notEnoughPurchases);
  items.sort((a, b) => b.purchases.compareTo(a.purchases));

  // 2. Dernier prix connu de chaque produit dans chaque magasin.
  final prices = latestPricesByStore(recent, now: now, window: window);
  final storeNames = {for (final i in items) ...?prices[i.key]?.prices.map((x) => x.storeName)};

  final ranked = <StoreBasketCost>[];
  final excluded = <String>[];
  for (final store in storeNames) {
    final lines = <BasketLine>[];
    for (final item in items) {
      final pp = prices[item.key]!;
      final here = pp.prices.where((x) => x.storeName == store).firstOrNull;
      if (here != null) {
        lines.add(BasketLine(item: item, unitPrice: here.unitPrice, estimated: false));
      } else {
        final avg = pp.prices.fold<double>(0, (s, x) => s + x.unitPrice) / pp.prices.length;
        lines.add(BasketLine(item: item, unitPrice: avg, estimated: true));
      }
    }
    final cost = StoreBasketCost(storeName: store, lines: lines);
    if (cost.coverage >= minCoverage) {
      ranked.add(cost);
    } else {
      excluded.add(store);
    }
  }
  ranked.sort((a, b) {
    final c = a.total.compareTo(b.total);
    return c != 0 ? c : b.knownCount.compareTo(a.knownCount);
  });
  excluded.sort();
  if (ranked.length < 2) {
    return HabitualBasket(status: BasketStatus.notEnoughStores, items: items, stores: ranked, excludedStores: excluded);
  }
  return HabitualBasket(status: BasketStatus.ok, items: items, stores: ranked, excludedStores: excluded);
}
