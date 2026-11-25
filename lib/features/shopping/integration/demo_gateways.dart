import 'package:flutter/foundation.dart';

import '../logic/text_similarity.dart';
import 'gateways.dart';

/// Implémentations en mémoire, utilisées tant que les gestions 1, 2 et 4 ne
/// sont pas branchées. À remplacer dans `main.dart` par les vrais services.

class DemoUserGateway implements UserGateway {
  @override
  int get currentUserId => 1;
}

class DemoProductGateway implements ProductGateway {
  DemoProductGateway({DateTime? today}) : _today = today ?? DateTime.now();

  final DateTime _today;

  /// Quelques produits courants. Les deux derniers ont des codes-barres
  /// internationaux présents dans Open Prices, pour la démonstration.
  static const products = [
    ProductRef(id: 1, name: 'Lait demi-écrémé 1L', category: 'Produits laitiers'),
    ProductRef(id: 2, name: 'Pain baguette', category: 'Boulangerie'),
    ProductRef(id: 3, name: 'Yaourt nature', category: 'Produits laitiers'),
    ProductRef(id: 4, name: 'Huile d\'olive 1L', category: 'Épicerie salée'),
    ProductRef(id: 5, name: 'Pâtes spaghetti 500g', category: 'Épicerie salée'),
    ProductRef(id: 6, name: 'Café moulu 250g', category: 'Épicerie sucrée'),
    ProductRef(id: 7, name: 'Tomates', category: 'Fruits et légumes'),
    ProductRef(id: 8, name: 'Oeufs x10', category: 'Viandes et poissons'),
    ProductRef(id: 9, name: 'Harissa 380g', category: 'Épicerie salée'),
    ProductRef(id: 10, name: 'Eau minérale 1,5L', category: 'Boissons'),
    ProductRef(id: 11, name: 'Sucre 1kg', category: 'Épicerie sucrée'),
    ProductRef(id: 12, name: 'Poulet entier', category: 'Viandes et poissons'),
    ProductRef(id: 13, name: 'Nutella 400g', barcode: '3017620422003', category: 'Épicerie sucrée'),
    ProductRef(id: 14, name: 'Coca-Cola 33cl', barcode: '5449000000996', category: 'Boissons'),
  ];

  final List<String> purchases = [];

  @override
  Future<ProductRef?> findByLabel(String label) async {
    ProductRef? best;
    var bestScore = 0.0;
    for (final p in products) {
      final s = labelSimilarity(p.name, label);
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return bestScore >= 0.7 ? best : null;
  }

  @override
  Future<ProductRef?> byId(int id) async {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<ShortageForecast>> upcomingShortages({int withinDays = 2}) async => [
        ShortageForecast(
          productId: 1,
          label: 'Lait demi-écrémé 1L',
          quantity: 2,
          unit: 'l',
          expectedDate: _today.add(const Duration(days: 1)),
          category: 'Produits laitiers',
        ),
        ShortageForecast(
          productId: 11,
          label: 'Sucre 1kg',
          quantity: 1,
          unit: 'kg',
          expectedDate: _today.add(const Duration(days: 2)),
          category: 'Épicerie sucrée',
        ),
      ];

  @override
  Future<void> registerPurchase({int? productId, required String label, required double quantity}) async {
    purchases.add(label);
    debugPrint('[Stock démo] entrée $quantity × $label');
  }
}

class DemoStoreGateway implements StoreGateway {
  static const _stores = [
    StoreRef(
      id: 1,
      name: 'Carrefour La Marsa',
      type: 'supermarché',
      aisles: [
        'Fruits et légumes', 'Boulangerie', 'Produits laitiers', 'Viandes et poissons',
        'Épicerie salée', 'Épicerie sucrée', 'Boissons', 'Surgelés', 'Hygiène et entretien',
      ],
      osmId: 1234567890,
      osmType: 'NODE',
    ),
    StoreRef(
      id: 2,
      name: 'Monoprix Lafayette',
      type: 'supermarché',
      aisles: [
        'Boissons', 'Épicerie sucrée', 'Épicerie salée', 'Produits laitiers', 'Viandes et poissons',
        'Fruits et légumes', 'Boulangerie', 'Hygiène et entretien',
      ],
    ),
    StoreRef(
      id: 3,
      name: 'Aziza Ennasr',
      type: 'épicerie',
      aisles: ['Épicerie salée', 'Épicerie sucrée', 'Produits laitiers', 'Boissons', 'Hygiène et entretien'],
    ),
    StoreRef(id: 4, name: 'Marché central', type: 'marché', aisles: ['Fruits et légumes', 'Viandes et poissons']),
  ];

  final List<String> recorded = [];

  @override
  Future<List<StoreRef>> stores() async => _stores;

  @override
  Future<void> recordPaidPrices(int storeId, DateTime date, List<PaidPrice> prices) async {
    for (final p in prices) {
      recorded.add('$storeId:${p.label}:${p.unitPrice}');
    }
    debugPrint('[Magasins démo] ${prices.length} prix relevés pour le magasin $storeId');
  }
}
