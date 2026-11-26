/// Suggestions intelligentes : produits à racheter selon leur fréquence
/// d'achat, et articles souvent oubliés.
///
/// **Fréquence** : à partir d'au moins [minSuggestPurchases] achats (jours
/// différents), intervalle moyen entre deux achats. Le produit est proposé
/// quand le délai depuis le dernier achat atteint 80 % de cet intervalle
/// (« bientôt à racheter »), et plus du tout au-delà de 2,5 fois (produit
/// sans doute abandonné).
///
/// **Confiance** (0 à 1) = 60 % régularité (1 − écart-type / moyenne des
/// intervalles) + 40 % nombre d'achats (plein à 6). Sous [minConfidence], on
/// ne propose rien : données insuffisantes.
///
/// **Oublis** : article oublié en magasin (rapprochement ticket ↔ liste) au
/// moins [minForgotten] fois.
library;

import 'dart:math' as math;

enum SuggestionKind { frequency, forgotten }

enum ConfidenceLevel {
  low('faible'),
  medium('moyenne'),
  high('élevée');

  const ConfidenceLevel(this.label);
  final String label;

  static ConfidenceLevel of(double c) => c >= 0.75
      ? high
      : c >= 0.5
          ? medium
          : low;
}

class Suggestion {
  const Suggestion({
    required this.key,
    required this.label,
    required this.kind,
    required this.confidence,
    this.intervalDays,
    this.daysSince,
    this.purchases = 0,
    this.forgottenCount = 0,
  });

  final String key;
  final String label;
  final SuggestionKind kind;
  final double confidence;

  /// Intervalle moyen entre deux achats (jours).
  final double? intervalDays;
  final int? daysSince;
  final int purchases;
  final int forgottenCount;

  ConfidenceLevel get level => ConfidenceLevel.of(confidence);

  /// « tous les 6 jours », « chaque semaine », « toutes les 3 semaines »…
  static String everyLabel(double days) {
    final d = days.round();
    if (d <= 1) return 'chaque jour';
    if (d == 7 || d == 8) return 'chaque semaine';
    if (d >= 27 && d <= 33) return 'chaque mois';
    if (d >= 12 && d <= 25) return 'toutes les ${(d / 7).round()} semaines';
    if (d > 33) return 'environ tous les ${(d / 30).round() <= 1 ? 'mois' : '${(d / 30).round()} mois'}';
    return 'tous les $d jours';
  }

  /// « Tu achètes « Lait » tous les 6 jours, l'ajouter ? »
  String get sentence => switch (kind) {
        SuggestionKind.frequency =>
          'Tu achètes « $label » ${everyLabel(intervalDays!)}, l\'ajouter ?',
        SuggestionKind.forgotten => 'Tu oublies souvent « $label » ($forgottenCount fois), l\'ajouter ?',
      };

  /// Précision affichée sous la phrase.
  String get detail => switch (kind) {
        SuggestionKind.frequency => 'Dernier achat il y a $daysSince jour${daysSince == 1 ? '' : 's'} · $purchases achats',
        SuggestionKind.forgotten => 'Oublié en magasin $forgottenCount fois',
      };
}

const minSuggestPurchases = 3;
const minForgotten = 2;
const minConfidence = 0.35;

/// Produits à racheter bientôt. [purchases] : dates d'achat par produit ;
/// [labels] : nom affiché par produit.
List<Suggestion> frequencySuggestions(
  Map<String, List<DateTime>> purchases,
  Map<String, String> labels, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <Suggestion>[];
  for (final e in purchases.entries) {
    // Un achat par jour au plus (deux lignes du même ticket = un achat).
    final days = {for (final d in e.value) DateTime(d.year, d.month, d.day)}.toList()..sort();
    if (days.length < minSuggestPurchases) continue;
    final intervals = [for (var i = 1; i < days.length; i++) days[i].difference(days[i - 1]).inDays.toDouble()];
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean < 1) continue;
    final variance = intervals.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / intervals.length;
    final regularity = (1 - math.sqrt(variance) / mean).clamp(0.0, 1.0);
    final count = (days.length / 6).clamp(0.0, 1.0);
    final confidence = 0.6 * regularity + 0.4 * count;
    final since = today.difference(days.last).inDays;
    final due = since >= 0.8 * mean && since <= 2.5 * mean;
    if (!due || confidence < minConfidence) continue;
    out.add(Suggestion(
      key: e.key,
      label: labels[e.key] ?? e.key,
      kind: SuggestionKind.frequency,
      confidence: confidence,
      intervalDays: mean,
      daysSince: since,
      purchases: days.length,
    ));
  }
  out.sort((a, b) => b.confidence.compareTo(a.confidence));
  return out;
}

/// Articles souvent oubliés : (libellé, nombre d'oublis) par clé.
List<Suggestion> forgottenSuggestions(Map<String, ({String label, int count})> forgotten) {
  final out = [
    for (final e in forgotten.entries)
      if (e.value.count >= minForgotten)
        Suggestion(
          key: e.key,
          label: e.value.label,
          kind: SuggestionKind.forgotten,
          forgottenCount: e.value.count,
          // 2 oublis : confiance moyenne ; 4 et plus : élevée.
          confidence: (0.35 + 0.15 * e.value.count).clamp(0.0, 1.0),
        ),
  ]..sort((a, b) => b.forgottenCount.compareTo(a.forgottenCount));
  return out;
}
