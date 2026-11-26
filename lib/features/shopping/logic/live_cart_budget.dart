/// Budget en temps réel pendant les courses (panier en direct) : dépense du
/// mois + contenu du panier, comme si l'on passait en caisse maintenant.
library;

import '../models/budget.dart';
import 'budget_forecast.dart' show BudgetLevel, shortDt;

class CartBudget {
  const CartBudget({required this.spentMonth, required this.cartTotal, this.budget});

  /// Déjà dépensé ce mois-ci (tickets enregistrés).
  final double spentMonth;

  /// Contenu actuel du panier.
  final double cartTotal;
  final Budget? budget;

  double get projected => spentMonth + cartTotal;
  double? get amount => budget?.amount;

  /// Part du budget après passage en caisse.
  double get ratio => (amount == null || amount == 0) ? 0 : projected / amount!;

  /// Ce qu'il resterait (négatif : dépassement).
  double? get remaining => amount == null ? null : amount! - projected;

  BudgetLevel get level {
    final b = budget;
    if (b == null) return BudgetLevel.none;
    if (projected >= b.amount) return BudgetLevel.exceeded;
    if (projected >= b.thresholdAmount) return BudgetLevel.threshold;
    return BudgetLevel.ok;
  }

  /// « Si tu passes en caisse, il te restera 8,4 DT ».
  String get sentence {
    final r = remaining;
    if (r == null) return 'Panier : ${shortDt(cartTotal)} (pas de budget défini ce mois-ci)';
    if (r >= 0) return 'Si tu passes en caisse, il te restera ${shortDt(r)}';
    return 'Si tu passes en caisse, tu dépasseras ton budget de ${shortDt(-r)}';
  }
}

/// Niveau franchi en ajoutant un article (seuil ou budget), sinon null.
/// Retirer un article ne déclenche jamais d'alerte.
BudgetLevel? crossedLevel(CartBudget before, CartBudget after) {
  if (after.level.index <= before.level.index) return null;
  if (after.level == BudgetLevel.threshold || after.level == BudgetLevel.exceeded) return after.level;
  return null;
}
