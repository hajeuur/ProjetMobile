import 'dates.dart';

/// Budget d'un mois (table budgets) : montant en DT et seuil d'alerte en %.
class Budget {
  const Budget({
    this.id,
    required this.userId,
    required this.month,
    required this.amount,
    this.alertThreshold = 80,
  });

  final int? id;
  final int userId;

  /// Premier jour du mois concerné.
  final DateTime month;
  final double amount;

  /// Pourcentage du budget à partir duquel on prévient (vibration).
  final int alertThreshold;

  double get thresholdAmount => amount * alertThreshold / 100;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'month': monthKey(month),
        'amount': amount,
        'alert_threshold': alertThreshold,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        month: parseMonthKey(m['month'] as String),
        amount: (m['amount'] as num).toDouble(),
        alertThreshold: m['alert_threshold'] as int,
      );
}
