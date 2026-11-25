/// Badges et défis : de petites récompenses calculées à partir des données
/// de la gestion (budgets tenus, courses sans oubli, tickets scannés…).
library;

import '../models/dates.dart';

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.current,
    required this.goal,
  });

  final String id;
  final String title;
  final String description;
  final int current;
  final int goal;

  bool get unlocked => current >= goal;
  double get progress => goal == 0 ? 1 : (current / goal).clamp(0, 1).toDouble();
  String get progressText => unlocked ? 'Obtenu' : '$current / $goal';
}

/// Nombre de mois terminés consécutifs (en partant du plus récent) où la
/// dépense est restée dans le budget.
int budgetStreak(List<({DateTime month, double spent, double? budget})> months, DateTime now) {
  final current = monthStart(now);
  final past = months.where((m) => m.month.isBefore(current)).toList()..sort((a, b) => b.month.compareTo(a.month));
  var streak = 0;
  for (final m in past) {
    if (m.budget == null || m.spent > m.budget!) break;
    streak++;
  }
  return streak;
}

List<Achievement> computeBadges({
  required int budgetStreakMonths,
  required int perfectTrips,
  required int receiptCount,
  required int completedLists,
  required int priceComparisons,
}) =>
    [
      Achievement(
        id: 'budget3',
        title: 'Budget tenu 3 mois',
        description: 'Rester dans son budget 3 mois de suite.',
        current: budgetStreakMonths,
        goal: 3,
      ),
      Achievement(
        id: 'zero_oubli',
        title: 'Zéro oubli',
        description: 'Un ticket rapproché d\'une liste sans aucun article oublié.',
        current: perfectTrips,
        goal: 1,
      ),
      Achievement(
        id: 'scanner',
        title: 'Archiviste',
        description: 'Enregistrer 10 tickets de caisse.',
        current: receiptCount,
        goal: 10,
      ),
      Achievement(
        id: 'liste_bouclee',
        title: 'Liste bouclée',
        description: 'Terminer une liste avec tous ses articles cochés.',
        current: completedLists,
        goal: 1,
      ),
      Achievement(
        id: 'comparateur',
        title: 'Chasseur de prix',
        description: 'Comparer 3 prix sur Open Prices.',
        current: priceComparisons,
        goal: 3,
      ),
    ];
