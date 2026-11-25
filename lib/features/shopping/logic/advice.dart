/// « Conseil du jour » : une phrase simple, calculée par règles à partir de
/// l'état du budget, du premier poste de dépense et de la plus forte hausse
/// de prix.
library;

import '../models/dates.dart';
import 'budget_forecast.dart';
import 'price_alerts.dart';
import 'text_similarity.dart';

enum AdviceTone { good, warning, danger, neutral }

class Advice {
  const Advice(this.tone, this.title, this.message);
  final AdviceTone tone;
  final String title;
  final String message;
}

Advice dailyAdvice(
  BudgetSnapshot s, {
  MapEntry<String, double>? topCategory,
  PriceAlert? topAlert,
}) {
  final extras = <String>[
    if (topCategory != null && topCategory.value > 0)
      'Premier poste ce mois-ci : ${topCategory.key} (${formatDt(topCategory.value)}).',
    if (topAlert != null)
      '${displayLabel(topAlert.label)} a augmenté de ${formatPct(topAlert.increase, sign: false)} : comparez les magasins avant de le racheter.',
  ];
  String withExtras(String m) => [m, ...extras].join(' ');

  final b = s.budget;
  if (b == null) {
    return Advice(
      AdviceTone.neutral,
      'Fixez un budget',
      withExtras('Définissez un budget pour ${monthLabel(s.month)} : l\'app vous préviendra avant de le dépasser.'),
    );
  }
  if (s.daysLeft == 0) {
    return s.spent <= b.amount
        ? Advice(AdviceTone.good, 'Mois réussi', 'Budget tenu : ${formatDt(b.amount - s.spent)} économisés.')
        : Advice(AdviceTone.danger, 'Mois dépassé', 'Budget dépassé de ${formatDt(s.spent - b.amount)}.');
  }
  switch (s.level) {
    case BudgetLevel.exceeded:
      return Advice(
        AdviceTone.danger,
        'Budget dépassé',
        withExtras('Dépassement de ${formatDt(s.spent - b.amount)}. Reportez les achats non essentiels '
            'au mois prochain et videz d\'abord le placard.'),
      );
    case BudgetLevel.threshold:
    case BudgetLevel.ok:
      final perDay = formatDt(s.dailyAllowance ?? 0);
      if (s.forecastOverrun) {
        return Advice(
          AdviceTone.warning,
          'Ralentissez',
          withExtras('Vous pouvez dépenser $perDay par jour jusqu\'à la fin du mois. '
              'Évitez les achats non essentiels cette semaine.'),
        );
      }
      return Advice(
        s.level == BudgetLevel.threshold ? AdviceTone.warning : AdviceTone.good,
        s.level == BudgetLevel.threshold ? 'Prudence' : 'Bien parti',
        withExtras('Vous pouvez dépenser $perDay par jour et rester dans le budget.'),
      );
    case BudgetLevel.none:
      return const Advice(AdviceTone.neutral, '', '');
  }
}
