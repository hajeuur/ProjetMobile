/// Contrats de la gestion 5 avec les autres gestions.
///
/// Règle commune du cahier des charges : la gestion Courses ne lit ni
/// n'écrit directement les tables des autres gestions. Elle passe par leur
/// service, représenté ici par une interface. Chaque coéquipier fournira
/// l'implémentation réelle ; en attendant, [demo_gateways.dart] en fournit
/// une en mémoire pour que la gestion fonctionne seule.
///
/// Dans l'autre sens, les autres gestions appellent `ShoppingService` :
/// - gestion 2 → `addRequests` (ruptures prévues) ;
/// - gestion 3 → `addRequests` (ingrédients manquants), via `RecipesShoppingBridge` ;
/// - gestion 4 → `pendingItemCount` (notification de géofencing) et
///   `activeListLabels` (magasin optimal).
library;

/// Gestion 1 — Utilisateurs et Foyer.
abstract interface class UserGateway {
  int get currentUserId;
}

/// Produit tel que la gestion 2 l'expose (lecture seule).
class ProductRef {
  const ProductRef({required this.id, required this.name, this.barcode, this.category});

  final int id;
  final String name;
  final String? barcode;
  final String? category;
}

/// Rupture prévue par la gestion 2 (consommation moyenne → date d'épuisement).
class ShortageForecast {
  const ShortageForecast({
    required this.productId,
    required this.label,
    required this.expectedDate,
    this.quantity,
    this.unit,
    this.category,
  });

  final int productId;
  final String label;
  final DateTime expectedDate;
  final double? quantity;
  final String? unit;
  final String? category;
}

/// Gestion 2 — Produits et Stock.
abstract interface class ProductGateway {
  /// Produit dont le nom ressemble le plus au libellé lu, ou null.
  Future<ProductRef?> findByLabel(String label);

  Future<ProductRef?> byId(int id);

  /// Produits dont l'épuisement est prévu dans les [withinDays] jours.
  Future<List<ShortageForecast>> upcomingShortages({int withinDays = 2});

  /// Entrée en stock d'un article acheté (après validation du ticket).
  Future<void> registerPurchase({int? productId, required String label, required double quantity});
}

/// Magasin tel que la gestion 4 l'expose (lecture seule).
class StoreRef {
  const StoreRef({
    required this.id,
    required this.name,
    this.type,
    this.aisles = const [],
    this.osmId,
    this.osmType,
  });

  final int id;
  final String name;

  /// supermarché, épicerie, marché.
  final String? type;

  /// Noms des rayons dans l'ordre de passage (table store_aisles).
  final List<String> aisles;

  /// Identifiant OpenStreetMap (Overpass), utile au partage Open Prices.
  final int? osmId;
  final String? osmType;
}

/// Prix payé transmis à la gestion 4 (table store_prices).
class PaidPrice {
  const PaidPrice({required this.label, this.productId, required this.unitPrice});

  final String label;
  final int? productId;
  final double unitPrice;
}

/// Gestion 4 — Magasins.
abstract interface class StoreGateway {
  Future<List<StoreRef>> stores();

  /// Enregistre les prix relevés sur un ticket validé (« prix payés »).
  Future<void> recordPaidPrices(int storeId, DateTime date, List<PaidPrice> prices);
}
