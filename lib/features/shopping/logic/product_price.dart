/// Fiche produit scannée : validation du code-barres, verdict de prix et
/// recherche d'une alternative moins chère. Logique pure, testée seule.
library;

import '../data/open_prices_api.dart' show OpenPrice;

// ---------------------------------------------------------- Code-barres

/// Code EAN-8, UPC-A (12), EAN-13 ou GTIN-14 dont la clé de contrôle est
/// juste. Les autres longueurs (8 à 14 chiffres) sont acceptées sans clé.
bool isValidBarcode(String code) {
  final c = code.trim();
  if (!RegExp(r'^\d{8,14}$').hasMatch(c)) return false;
  if (![8, 12, 13, 14].contains(c.length)) return true;
  final digits = c.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  // Pondération 3/1 en partant de la droite (hors clé).
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - 1 - i;
    sum += digits[i] * (fromRight.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}

// -------------------------------------------------------------- Verdict

enum VerdictKind {
  /// Plus cher que la moyenne (rouge).
  expensive,

  /// Bon prix : dans la moyenne ou en dessous (vert).
  good,

  /// Pas de comparaison possible.
  unknown,
}

class PriceVerdict {
  const PriceVerdict(this.kind, this.text, {this.difference});
  final VerdictKind kind;
  final String text;

  /// (mon prix − moyenne) / moyenne.
  final double? difference;
}

/// Tolérance : jusqu'à +5 % au-dessus de la moyenne, c'est encore un bon prix.
const fairPriceTolerance = 0.05;

PriceVerdict priceVerdict({required double? myPrice, required double? communityMean}) {
  if (communityMean == null || communityMean <= 0) {
    return const PriceVerdict(VerdictKind.unknown, 'Pas de prix de la communauté pour comparer.');
  }
  if (myPrice == null) {
    return const PriceVerdict(VerdictKind.unknown, 'Vous n\'avez pas encore acheté ce produit.');
  }
  final d = (myPrice - communityMean) / communityMean;
  final pct = (d.abs() * 100).round();
  if (d > fairPriceTolerance) {
    return PriceVerdict(VerdictKind.expensive, 'Tu paies $pct % de plus que la moyenne', difference: d);
  }
  if (d < -fairPriceTolerance) {
    return PriceVerdict(VerdictKind.good, 'Bon prix : $pct % de moins que la moyenne', difference: d);
  }
  return PriceVerdict(VerdictKind.good, 'Bon prix (dans la moyenne)', difference: d);
}

double? meanOf(Iterable<double> values) {
  final v = values.toList();
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

// ----------------------------------------------------------- Alternative

class PricePoint {
  const PricePoint({required this.date, required this.unitPrice, this.store});
  final DateTime date;
  final double unitPrice;
  final String? store;
}

enum AlternativeSource { community, myHistory }

class CheaperAlternative {
  const CheaperAlternative({
    required this.name,
    required this.price,
    required this.source,
    required this.saving,
    this.code,
    this.where,
    this.priceCount = 1,
  });

  final String name;
  final String? code;

  /// Prix moyen (communauté) ou prix payé (historique).
  final double price;
  final AlternativeSource source;

  /// Économie relative par rapport au prix de référence (0,3 = 30 %).
  final double saving;

  /// Magasin (historique).
  final String? where;
  final int priceCount;
}

/// Alternative de même catégorie au meilleur prix moyen communautaire,
/// au moins 5 % moins chère que [reference].
CheaperAlternative? communityAlternative({
  required String code,
  required double? reference,
  required List<OpenPrice> categoryPrices,
}) {
  if (reference == null || reference <= 0) return null;
  final byProduct = <String, List<OpenPrice>>{};
  for (final p in categoryPrices) {
    final c = p.productCode;
    if (c == null || c == code) continue;
    byProduct.putIfAbsent(c, () => []).add(p);
  }
  CheaperAlternative? best;
  for (final e in byProduct.entries) {
    final mean = meanOf(e.value.map((p) => p.price))!;
    final saving = (reference - mean) / reference;
    if (saving < fairPriceTolerance) continue;
    final name = e.value.map((p) => p.productName).whereType<String>().firstOrNull ?? 'Produit ${e.key}';
    if (best == null || mean < best.price) {
      best = CheaperAlternative(
        name: name,
        code: e.key,
        price: mean,
        source: AlternativeSource.community,
        saving: saving,
        priceCount: e.value.length,
      );
    }
  }
  return best;
}

/// À défaut : le même produit, payé moins cher dans un autre magasin.
CheaperAlternative? historyAlternative({required String name, required List<PricePoint> history}) {
  if (history.length < 2) return null;
  final last = history.last;
  PricePoint? best;
  for (final p in history) {
    if (p.store == null || p.store == last.store) continue;
    if (best == null || p.unitPrice < best.unitPrice) best = p;
  }
  if (best == null) return null;
  final saving = (last.unitPrice - best.unitPrice) / last.unitPrice;
  if (saving < fairPriceTolerance) return null;
  return CheaperAlternative(
    name: name,
    price: best.unitPrice,
    source: AlternativeSource.myHistory,
    saving: saving,
    where: best.store,
  );
}
