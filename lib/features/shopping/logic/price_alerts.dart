/// Détection des hausses de prix (métier avancé n° 2).
///
/// Pour chaque produit, le dernier prix unitaire payé est comparé à la
/// moyenne des prix payés pendant les trois mois qui précèdent cet achat.
/// Au-delà de +10 %, une alerte est produite avec le pourcentage.
library;

class PricePoint {
  const PricePoint({
    required this.key,
    required this.label,
    required this.date,
    required this.unitPrice,
    this.storeName,
    this.receiptId,
    this.quantity = 1,
  });

  /// Identifiant du produit : « p:12 » (produit rapproché) ou « l:lait delice ».
  final String key;
  final String label;
  final DateTime date;
  final double unitPrice;
  final String? storeName;
  final int? receiptId;

  /// Quantité achetée sur la ligne du ticket (articles ou kg).
  final double quantity;
}

class PriceAlert {
  const PriceAlert({
    required this.key,
    required this.label,
    required this.lastPrice,
    required this.average,
    required this.lastDate,
    required this.sampleCount,
    this.storeName,
  });

  final String key;
  final String label;
  final double lastPrice;

  /// Moyenne des trois mois précédant le dernier achat.
  final double average;
  final DateTime lastDate;

  /// Nombre d'achats ayant servi à la moyenne.
  final int sampleCount;
  final String? storeName;

  /// Hausse relative : 0,15 pour +15 %.
  double get increase => average == 0 ? 0 : (lastPrice - average) / average;

  /// Plus la moyenne repose sur des achats nombreux, plus l'alerte est fiable.
  AlertReliability get reliability => sampleCount >= 4
      ? AlertReliability.high
      : sampleCount >= 2
          ? AlertReliability.medium
          : AlertReliability.low;

  /// Produit de la gestion 2 quand la clé est de la forme `p:12`.
  int? get productId => key.startsWith('p:') ? int.tryParse(key.substring(2)) : null;
}

enum AlertReliability {
  low('Fiabilité faible', 'Basée sur un seul achat précédent : à confirmer au prochain ticket.'),
  medium('Fiabilité moyenne', 'Basée sur 2 ou 3 achats précédents.'),
  high('Fiabilité bonne', 'Basée sur au moins 4 achats précédents.');

  const AlertReliability(this.label, this.explanation);
  final String label;
  final String explanation;
}

const defaultIncreaseThreshold = 0.10;
const defaultHistoryWindow = Duration(days: 90);

List<PriceAlert> detectPriceIncreases(
  List<PricePoint> points, {
  double threshold = defaultIncreaseThreshold,
  Duration window = defaultHistoryWindow,
}) {
  final byKey = <String, List<PricePoint>>{};
  for (final p in points) {
    if (p.unitPrice <= 0) continue;
    byKey.putIfAbsent(p.key, () => []).add(p);
  }

  final alerts = <PriceAlert>[];
  for (final entry in byKey.entries) {
    final history = entry.value..sort((a, b) => a.date.compareTo(b.date));
    final last = history.last;
    final from = last.date.subtract(window);
    bool sameReceipt(PricePoint p) =>
        identical(p, last) || (p.receiptId != null && p.receiptId == last.receiptId);
    final previous = history.where((p) => !sameReceipt(p) && !p.date.isBefore(from)).toList();
    if (previous.isEmpty) continue;
    final avg = previous.fold<double>(0, (s, p) => s + p.unitPrice) / previous.length;
    final alert = PriceAlert(
      key: entry.key,
      label: last.label,
      lastPrice: last.unitPrice,
      average: avg,
      lastDate: last.date,
      sampleCount: previous.length,
      storeName: last.storeName,
    );
    if (alert.increase > threshold) alerts.add(alert);
  }
  alerts.sort((a, b) => b.increase.compareTo(a.increase));
  return alerts;
}
