import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/advice.dart';
import '../logic/badges.dart';
import '../logic/budget_forecast.dart';
import '../logic/price_alerts.dart';
import '../models/dates.dart';
import '../services/shopping_service.dart';

/// Écran « Budget du mois » et statistiques.
class BudgetViewModel extends ChangeNotifier {
  BudgetViewModel(this.service) : month = monthStart(service.now) {
    // Ticket enregistré, corrigé ou supprimé : la jauge s'anime vers la
    // nouvelle dépense (l'alerte elle-même vient du service, une seule fois).
    _sub = service.receiptsChanged.listen((_) => load());
  }
  final ShoppingService service;
  late final StreamSubscription<void> _sub;

  DateTime month;
  bool loading = false;
  String? error;
  BudgetSnapshot? snapshot;
  List<MonthSpending> monthly = [];
  Map<String, double> categories = {};
  double averageBasket = 0;
  (int, int) respect = (0, 0);
  Advice? advice;
  List<Achievement> badges = [];

  bool get isCurrentMonth => monthKey(month) == monthKey(service.now);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      snapshot = await service.snapshot(month);
      monthly = await service.monthlySpending(count: 6, until: month);
      categories = await service.categorySpending(month);
      averageBasket = await service.averageBasket();
      respect = await service.budgetRespect();
      advice = await service.advice(month);
      badges = await service.badges();
    } catch (e) {
      error = 'Budget indisponible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> goToMonth(int offset) {
    month = offset == 0 ? monthStart(service.now) : addMonths(month, offset);
    return load();
  }

  Future<void> setBudget(double amount, int threshold) async {
    await service.setBudget(month, amount, alertThreshold: threshold);
    await load();
  }

  Future<void> deleteBudget() async {
    final b = snapshot?.budget;
    if (b == null) return;
    await service.deleteBudget(b);
    await load();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Écran « Alertes de prix ».
class PriceAlertsViewModel extends ChangeNotifier {
  PriceAlertsViewModel(this.service);
  final ShoppingService service;

  bool loading = false;
  String? error;
  List<PriceAlert> alerts = [];

  /// Alerte intelligente : remettre le produit sur la liste en cours.
  Future<int> addToList(PriceAlert a) => service.addAlertToList(a);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      alerts = await service.priceAlerts();
    } catch (e) {
      error = 'Alertes indisponibles : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
