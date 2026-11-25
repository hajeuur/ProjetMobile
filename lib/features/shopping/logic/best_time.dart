/// Meilleur moment pour acheter un produit.
///
/// À partir de mes achats d'un produit (au moins [minPurchases]), on compare
/// le prix moyen selon trois critères :
/// - le **moment du mois** : début (1–10), milieu (11–20), fin (21–31) ;
/// - le **jour de la semaine** ;
/// - le **magasin**.
///
/// Pour chaque critère, le meilleur groupe (au moins 2 achats) est comparé à
/// tous les autres achats. On ne conclut que si l'écart dépasse
/// [minSaving] (5 %) ; sinon on le dit honnêtement. Quand le moment du mois
/// et le magasin sont tous deux significatifs et que leur combinaison
/// compte au moins 2 achats, la phrase les réunit : « Pour les tomates,
/// c'est moins cher en début de mois au Marché central (-13 %) ».
library;

import 'budget_forecast.dart' show shortDt;
import 'price_alerts.dart';

enum MonthPart {
  start('en début de mois', 'Début'),
  middle('en milieu de mois', 'Milieu'),
  end('en fin de mois', 'Fin');

  const MonthPart(this.phrase, this.short);
  final String phrase;
  final String short;

  static MonthPart of(DateTime d) => d.day <= 10
      ? start
      : d.day <= 20
          ? middle
          : end;

  /// Premier jour de cette période.
  int get firstDay => switch (this) { start => 1, middle => 11, end => 21 };
}

const weekdayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const weekdayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

enum Dimension { monthPart, weekday, store }

/// Prix moyen d'un groupe d'achats (une barre du mini-graphique).
class PriceGroup {
  const PriceGroup({required this.key, required this.label, required this.mean, required this.count});
  final String key;
  final String label;
  final double mean;
  final int count;
}

/// Résultat d'un critère : meilleur groupe et économie face aux autres achats.
class DimensionResult {
  const DimensionResult({
    required this.dimension,
    required this.groups,
    required this.best,
    required this.saving,
  });

  final Dimension dimension;

  /// Groupes d'au moins 2 achats (barres), dans l'ordre naturel.
  final List<PriceGroup> groups;
  final PriceGroup best;

  /// (moyenne des autres − moyenne du meilleur) / moyenne des autres.
  final double saving;
}

enum BestTimeStatus {
  /// Moins de [minPurchases] achats.
  notEnoughData,

  /// Assez d'achats, mais aucun écart d'au moins 5 %.
  noDifference,

  ok,
}

class BestTimeInsight {
  const BestTimeInsight({
    required this.key,
    required this.label,
    required this.purchases,
    required this.status,
    this.dimensions = const [],
    this.monthPart,
    this.weekday,
    this.store,
    this.saving = 0,
  });

  final String key;

  /// Libellé lisible (« tomates »).
  final String label;
  final int purchases;
  final BestTimeStatus status;

  /// Critères significatifs (écart ≥ 5 %), du plus avantageux au moins.
  final List<DimensionResult> dimensions;

  /// Conclusion retenue (null si le critère n'en fait pas partie).
  final MonthPart? monthPart;
  final int? weekday; // 1 = lundi
  final String? store;
  final double saving;

  DimensionResult? get main => dimensions.isEmpty ? null : dimensions.first;

  /// « basé sur 8 achats ».
  String get basis => 'basé sur $purchases achat${purchases > 1 ? 's' : ''}';

  String get sentence => switch (status) {
        BestTimeStatus.notEnoughData =>
          'Pas encore assez d\'achats de $label pour conclure ($purchases sur $minPurchases nécessaires).',
        BestTimeStatus.noDifference =>
          'Pour $label, le prix varie peu (moins de 5 % d\'écart) : achète quand ça t\'arrange.',
        BestTimeStatus.ok => 'Pour $label, c\'est moins cher ${[
            if (monthPart != null) monthPart!.phrase,
            if (weekday != null) 'le ${weekdayNames[weekday! - 1]}',
            if (store != null) _at(store!),
          ].join(' ')} (-${(saving * 100).round()} %)',
      };

  /// Texte du rappel (notification).
  String get reminderText => status != BestTimeStatus.ok
      ? ''
      : 'C\'est le bon moment : $label ${(saving * 100).round()} % moins cher'
          '${store == null ? '' : ' ${_at(store!)}'} (prix moyen ${shortDt(dimensions.first.best.mean)}).';

  static String _at(String store) {
    final s = store.toLowerCase();
    if (s.startsWith('marché') || s.startsWith('marche')) return 'au $store';
    return 'chez $store';
  }
}

const minPurchases = 6;
const minSaving = 0.05;

BestTimeInsight analyseBestTime(String key, String label, List<PricePoint> points) {
  final pts = [for (final p in points) if (p.unitPrice > 0) p];
  if (pts.length < minPurchases) {
    return BestTimeInsight(key: key, label: label, purchases: pts.length, status: BestTimeStatus.notEnoughData);
  }
  String monthKey(PricePoint p) => MonthPart.of(p.date).name;
  String dayKey(PricePoint p) => '${p.date.weekday}';
  String storeKey(PricePoint p) => p.storeName ?? '?';

  final results = <DimensionResult>[
    ?_dimension(Dimension.monthPart, pts, monthKey, (k) => MonthPart.values.byName(k).short,
        order: [for (final m in MonthPart.values) m.name]),
    ?_dimension(Dimension.weekday, pts, dayKey, (k) => weekdayShort[int.parse(k) - 1],
        order: [for (var d = 1; d <= 7; d++) '$d']),
    ?_dimension(Dimension.store, pts.where((p) => p.storeName != null).toList(), storeKey, (k) => k),
  ]..sort((a, b) => b.saving.compareTo(a.saving));

  if (results.isEmpty) {
    return BestTimeInsight(key: key, label: label, purchases: pts.length, status: BestTimeStatus.noDifference);
  }

  // Phrase : le meilleur critère, combiné au moment du mois et au magasin
  // quand les deux sont significatifs et que la combinaison tient.
  final main = results.first;
  final byDim = {for (final r in results) r.dimension: r};
  final month = byDim[Dimension.monthPart];
  final store = byDim[Dimension.store];
  if (month != null && store != null && main.dimension != Dimension.weekday) {
    final inBoth = pts.where((p) => monthKey(p) == month.best.key && storeKey(p) == store.best.key).toList();
    final rest = pts.where((p) => !inBoth.contains(p)).toList();
    if (inBoth.length >= 2 && rest.length >= 2) {
      final saving = _saving(_mean(inBoth), _mean(rest));
      if (saving >= minSaving) {
        return BestTimeInsight(
          key: key,
          label: label,
          purchases: pts.length,
          status: BestTimeStatus.ok,
          dimensions: results,
          monthPart: MonthPart.values.byName(month.best.key),
          store: store.best.key,
          saving: saving,
        );
      }
    }
  }
  return BestTimeInsight(
    key: key,
    label: label,
    purchases: pts.length,
    status: BestTimeStatus.ok,
    dimensions: results,
    monthPart: main.dimension == Dimension.monthPart ? MonthPart.values.byName(main.best.key) : null,
    weekday: main.dimension == Dimension.weekday ? int.parse(main.best.key) : null,
    store: main.dimension == Dimension.store ? main.best.key : null,
    saving: main.saving,
  );
}

DimensionResult? _dimension(
  Dimension dim,
  List<PricePoint> pts,
  String Function(PricePoint) keyOf,
  String Function(String) labelOf, {
  List<String>? order,
}) {
  final groups = <String, List<PricePoint>>{};
  for (final p in pts) {
    groups.putIfAbsent(keyOf(p), () => []).add(p);
  }
  // Seuls les groupes d'au moins 2 achats peuvent être « le meilleur ».
  final valid = {for (final e in groups.entries) if (e.value.length >= 2) e.key: e.value};
  if (valid.isEmpty || groups.length < 2) return null;
  final bars = [
    for (final e in valid.entries) PriceGroup(key: e.key, label: labelOf(e.key), mean: _mean(e.value), count: e.value.length),
  ];
  if (order != null) bars.sort((a, b) => order.indexOf(a.key).compareTo(order.indexOf(b.key)));
  final best = bars.reduce((a, b) => a.mean <= b.mean ? a : b);
  final others = [for (final p in pts) if (keyOf(p) != best.key) p];
  if (others.length < 2) return null;
  final saving = _saving(best.mean, _mean(others));
  if (saving < minSaving) return null;
  return DimensionResult(dimension: dim, groups: bars, best: best, saving: saving);
}

double _mean(List<PricePoint> pts) => pts.fold(0.0, (s, p) => s + p.unitPrice) / pts.length;
double _saving(double best, double others) => others <= 0 ? 0 : (others - best) / others;

/// Prochain moment favorable (rappel) : début de la période du mois, ou
/// prochain jour de la semaine, à 9 h ; demain 9 h pour un conseil de magasin.
DateTime nextReminder(BestTimeInsight i, DateTime now) {
  DateTime at9(DateTime d) => DateTime(d.year, d.month, d.day, 9);
  if (i.monthPart != null) {
    final first = i.monthPart!.firstDay;
    var d = at9(DateTime(now.year, now.month, first));
    if (!d.isAfter(now)) d = at9(DateTime(now.year, now.month + 1, first));
    return d;
  }
  if (i.weekday != null) {
    var d = at9(now);
    while (d.weekday != i.weekday || !d.isAfter(now)) {
      d = at9(d.add(const Duration(days: 1)));
    }
    return d;
  }
  return at9(now.add(const Duration(days: 1)));
}
