/// État du budget du mois et prévision de fin de mois (métier avancé n° 3).
///
/// La dépense finale est projetée au rythme des jours écoulés :
/// `prévision = dépensé ÷ jours écoulés × jours du mois`. Si la prévision
/// dépasse le budget alors que le budget n'est pas encore atteint, l'app
/// avertit avant que le dépassement arrive, et indique combien on peut encore
/// dépenser par jour pour rester dans le budget.
library;

import '../models/budget.dart';
import '../models/dates.dart' as dates;

/// Niveau d'alerte du budget, du plus calme au plus grave.
enum BudgetLevel {
  none('Pas de budget'),
  ok('Dans le budget'),
  threshold('Seuil d\'alerte atteint'),
  exceeded('Budget dépassé');

  const BudgetLevel(this.label);
  final String label;
}

class BudgetSnapshot {
  const BudgetSnapshot({
    required this.month,
    required this.budget,
    required this.spent,
    required this.projected,
    required this.daysElapsed,
    required this.daysInMonth,
  });

  /// Calcule l'état du mois [month] à la date [today].
  factory BudgetSnapshot.compute({
    required DateTime month,
    required Budget? budget,
    required double spent,
    required DateTime today,
  }) {
    final start = dates.monthStart(month);
    final days = dates.daysInMonth(start);
    final current = dates.monthStart(today);
    int elapsed;
    if (start.isBefore(current)) {
      elapsed = days; // mois terminé
    } else if (start.isAfter(current)) {
      elapsed = 0; // mois à venir
    } else {
      elapsed = today.day;
    }
    final projected = elapsed == 0 ? spent : spent / elapsed * days;
    return BudgetSnapshot(
      month: start,
      budget: budget,
      spent: spent,
      projected: elapsed >= days ? spent : projected,
      daysElapsed: elapsed,
      daysInMonth: days,
    );
  }

  final DateTime month;
  final Budget? budget;
  final double spent;

  /// Dépense prévue en fin de mois.
  final double projected;
  final int daysElapsed;
  final int daysInMonth;

  int get daysLeft => daysInMonth - daysElapsed;

  double? get amount => budget?.amount;

  /// Part du budget consommée (0 à 1 et plus).
  double get ratio => (amount == null || amount == 0) ? 0 : spent / amount!;

  double get remaining => (amount ?? 0) - spent;

  BudgetLevel get level {
    final b = budget;
    if (b == null) return BudgetLevel.none;
    if (spent >= b.amount) return BudgetLevel.exceeded;
    if (spent >= b.thresholdAmount) return BudgetLevel.threshold;
    return BudgetLevel.ok;
  }

  /// Dépassement prévu : le budget n'est pas atteint mais le rythme actuel y
  /// mène avant la fin du mois.
  bool get forecastOverrun =>
      budget != null && level != BudgetLevel.exceeded && daysLeft > 0 && projected > budget!.amount;

  double get projectedOverrun => projected - (amount ?? projected);

  /// Dépense quotidienne possible jusqu'à la fin du mois sans dépasser.
  double? get dailyAllowance {
    if (budget == null || daysLeft <= 0) return null;
    final r = remaining;
    return r <= 0 ? 0 : r / daysLeft;
  }

  /// Jour du mois où le budget sera atteint au rythme actuel.
  int? get forecastOverrunDay {
    if (!forecastOverrun || spent <= 0 || daysElapsed == 0) return null;
    final perDay = spent / daysElapsed;
    final day = (amount! / perDay).ceil();
    return day.clamp(daysElapsed, daysInMonth);
  }
}

/// Montant court pour une phrase : « 4,6 DT », « 0,35 DT », « 12 DT ».
String shortDt(double amount) {
  final a = amount.abs();
  final digits = a >= 100 ? 0 : (a >= 1 ? 1 : 2);
  var s = a.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '${amount < 0 ? '-' : ''}${s.replaceAll('.', ',')} DT';
}

/// Phrase intelligente sous la jauge :
/// « À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour. »
String budgetSentence(BudgetSnapshot s) {
  final b = s.budget;
  if (b == null) return 'Définis un budget pour suivre tes dépenses du mois.';
  if (s.level == BudgetLevel.exceeded) {
    return 'Budget dépassé de ${shortDt(s.spent - b.amount)}. '
        '${s.daysLeft > 0 ? 'Évite les achats non essentiels jusqu\'à la fin du mois.' : 'Le mois est terminé.'}';
  }
  if (s.forecastOverrun) {
    return 'À ce rythme, tu dépasseras de ${shortDt(s.projectedOverrun)}. '
        'Limite-toi à ${shortDt(s.dailyAllowance ?? 0)}/jour.';
  }
  if (s.daysLeft <= 0) return 'Mois terminé dans le budget, bravo !';
  if (s.level == BudgetLevel.threshold) {
    return 'Il te reste ${shortDt(s.remaining)}, soit ${shortDt(s.dailyAllowance ?? 0)}/jour '
        'pour finir le mois dans le budget.';
  }
  return 'À ce rythme, tu finiras le mois à ${shortDt(s.projected)}, sous ton budget de ${shortDt(b.amount)}.';
}
