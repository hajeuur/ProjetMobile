import 'package:flutter/foundation.dart';

import 'gateways.dart';

/// Implémentations en mémoire, utilisées tant que les gestions 1, 2 et 5 ne
/// sont pas branchées. À remplacer dans `main.dart` par les vrais services.

class DemoStockGateway implements StockGateway {
  DemoStockGateway({DateTime? today}) {
    final t = today ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    _stock.addAll([
      StockSnapshot(name: 'Tomate', quantity: 6, unit: 'pièce', expiryDate: d.add(const Duration(days: 2))),
      StockSnapshot(name: 'Oeuf', quantity: 10, unit: 'pièce', expiryDate: d.add(const Duration(days: 12))),
      StockSnapshot(name: 'Oignon', quantity: 4, unit: 'pièce', expiryDate: d.add(const Duration(days: 20))),
      StockSnapshot(name: 'Poivron', quantity: 3, unit: 'pièce', expiryDate: d.add(const Duration(days: 1))),
      StockSnapshot(name: 'Pois chiches', quantity: 500, unit: 'g', expiryDate: d.add(const Duration(days: 200))),
      StockSnapshot(name: 'Semoule', quantity: 1000, unit: 'g', expiryDate: d.add(const Duration(days: 300))),
      StockSnapshot(name: 'Huile d\'olive', quantity: 750, unit: 'ml', expiryDate: d.add(const Duration(days: 365))),
      StockSnapshot(name: 'Lait', quantity: 1, unit: 'l', expiryDate: d.add(const Duration(days: 3))),
      StockSnapshot(name: 'Poulet', quantity: 600, unit: 'g', expiryDate: d.add(const Duration(days: 2))),
      StockSnapshot(name: 'Riz', quantity: 1000, unit: 'g', expiryDate: d.add(const Duration(days: 250))),
      StockSnapshot(name: 'Ail', quantity: 5, unit: 'gousse', expiryDate: d.add(const Duration(days: 30))),
    ]);
  }

  final List<StockSnapshot> _stock = [];

  @override
  Future<List<StockSnapshot>> currentStock() async => List.unmodifiable(_stock);

  @override
  Future<void> consume({
    int? productId,
    required String name,
    required double quantity,
    String? unit,
    required String reason,
  }) async {
    final i = _stock.indexWhere((s) => s.name.toLowerCase() == name.toLowerCase());
    if (i < 0) return;
    final s = _stock[i];
    final left = s.quantity - quantity;
    if (left <= 0) {
      _stock.removeAt(i);
    } else {
      _stock[i] = StockSnapshot(
        productId: s.productId,
        name: s.name,
        quantity: left,
        unit: s.unit,
        expiryDate: s.expiryDate,
      );
    }
    debugPrint('[Stock démo] sortie $quantity ${unit ?? ''} $name ($reason)');
  }
}

class DemoHouseholdGateway implements HouseholdGateway {
  @override
  int get currentUserId => 1;

  @override
  Future<HouseholdProfile> commonProfile() async => const HouseholdProfile(
        allergies: {'arachide'},
        diets: {'halal'},
        dailyCaloriesPerPerson: 2200,
        memberCount: 3,
      );
}

class DemoShoppingGateway implements ShoppingGateway {
  final List<ShoppingRequest> items = [];

  @override
  Future<int> addItems(List<ShoppingRequest> newItems) async {
    items.addAll(newItems);
    for (final i in newItems) {
      debugPrint('[Courses démo] + ${i.quantity ?? ''} ${i.unit ?? ''} ${i.label} (${i.origin})');
    }
    return newItems.length;
  }
}
