/// Détecteur de shrinkflation : même produit, format plus petit, prix
/// identique ou en hausse.
///
/// Pour chaque produit, les achats sont triés par date et comparés deux à
/// deux. Alerte quand le format baisse d'au moins [minDrop] (3 %) alors que
/// le prix payé ne baisse pas (tolérance [priceTolerance], 2 %) : le prix au
/// kilo / au litre a augmenté sans que l'étiquette change.
///
/// Un achat sans format lisible n'est jamais comparé : si le même produit
/// a un format connu sur d'autres achats, on demande confirmation à
/// l'utilisateur plutôt que d'affirmer quoi que ce soit.
library;

import 'pack_format.dart';

class PackPurchase {
  const PackPurchase({
    required this.lineId,
    required this.date,
    required this.label,
    required this.price,
    this.format,
    this.store,
  });

  final int? lineId;
  final DateTime date;
  final String label;

  /// Prix payé pour une unité (un paquet, une bouteille).
  final double price;
  final PackFormat? format;
  final String? store;

  double? get pricePerBig => format?.pricePerBig(price);
}

class ShrinkAlert {
  const ShrinkAlert({required this.key, required this.name, required this.before, required this.after});
  final String key;

  /// Nom du produit sans le format (« café en grains »).
  final String name;
  final PackPurchase before;
  final PackPurchase after;

  /// Part du contenu perdue (0,2 = 20 %).
  double get sizeDrop => 1 - after.format!.amount / before.format!.amount;

  /// Variation du prix payé.
  double get priceChange => after.price / before.price - 1;

  /// Hausse du prix au kilo / au litre.
  double get perBigIncrease => after.pricePerBig! / before.pricePerBig! - 1;

  bool get samePrice => priceChange.abs() <= priceTolerance;

  /// « Même prix, 20 % de café en grains en moins ».
  String get sentence {
    final drop = (sizeDrop * 100).round();
    final what = '$drop % ${_de(name)} en moins';
    if (samePrice) return 'Même prix, $what';
    return 'Prix en hausse de ${(priceChange * 100).round()} % et $what';
  }

  static String _de(String noun) {
    final n = noun.trim();
    if (n.isEmpty) return 'de produit';
    return RegExp(r'^[aeiouyhâàéèêëîïôûù]', caseSensitive: false).hasMatch(n) ? "d'$n" : 'de $n';
  }
}

/// Achats d'un produit au format inconnu, alors que d'autres achats du même
/// produit en ont un : à confirmer par l'utilisateur.
class FormatToConfirm {
  const FormatToConfirm({required this.key, required this.name, required this.purchase, required this.known});
  final String key;
  final String name;
  final PackPurchase purchase;

  /// Format connu sur un autre achat (proposition « même format »).
  final PackFormat known;
}

const minDrop = 0.03;
const priceTolerance = 0.02;

/// Nom du produit sans format ni quantité : « CAFE EN GRAINS 200G » → « café en grains ».
String productNoun(String label) {
  final t = label
      .toLowerCase()
      .replaceAll(RegExp(r'\d+([.,]\d+)?\s*[x×*]\s*\d+([.,]\d+)?\s*(kgs?|grs?|g|l|lt|ltr|cl|ml)\b'), '')
      .replaceAll(RegExp(r'\d+([.,]\d+)?\s*(kgs?|kilo|grs?|g|l|lt|ltr|cl|ml)\b(\s*[x×*]\s*\d+)?'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const accents = {'cafe': 'café', 'the': 'thé', 'pates': 'pâtes', 'creme': 'crème', 'puree': 'purée'};
  return t.split(' ').map((w) => accents[w] ?? w).join(' ');
}

({List<ShrinkAlert> alerts, List<FormatToConfirm> toConfirm}) detectShrinkflation(
  Map<String, List<PackPurchase>> byProduct,
) {
  final alerts = <ShrinkAlert>[];
  final confirm = <FormatToConfirm>[];
  for (final e in byProduct.entries) {
    final purchases = [...e.value]..sort((a, b) => a.date.compareTo(b.date));
    final known = [for (final p in purchases) if (p.format != null) p];
    if (known.isEmpty) continue; // aucun format : rien à dire

    // Achats sans format au milieu d'achats avec format : demander.
    for (final p in purchases.where((p) => p.format == null)) {
      final nearest = known.reduce(
        (a, b) => (a.date.difference(p.date).abs() <= b.date.difference(p.date).abs()) ? a : b,
      );
      confirm.add(FormatToConfirm(key: e.key, name: productNoun(nearest.label), purchase: p, known: nearest.format!));
    }

    // Comparaisons successives entre achats au format connu (même mesure).
    ShrinkAlert? latest;
    for (var i = 1; i < known.length; i++) {
      final before = known[i - 1];
      final after = known[i];
      if (before.format!.measure != after.format!.measure) continue;
      final drop = 1 - after.format!.amount / before.format!.amount;
      final priceChange = after.price / before.price - 1;
      if (drop >= minDrop && priceChange >= -priceTolerance) {
        latest = ShrinkAlert(key: e.key, name: productNoun(after.label), before: before, after: after);
      }
    }
    if (latest != null) alerts.add(latest);
  }
  alerts.sort((a, b) => b.perBigIncrease.compareTo(a.perBigIncrease));
  confirm.sort((a, b) => b.purchase.date.compareTo(a.purchase.date));
  return (alerts: alerts, toConfirm: confirm);
}
