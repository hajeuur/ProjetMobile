/// Contrats avec les autres gestions.
///
/// Règle commune du cahier des charges : la gestion Recettes ne lit ni n'écrit
/// directement les tables des autres gestions. Elle passe par leur service,
/// représenté ici par une interface. Chaque coéquipier fournira
/// l'implémentation réelle ; en attendant, [demo_gateways.dart] en fournit une
/// en mémoire pour que la gestion fonctionne seule.
library;

/// Une ligne de stock telle que la gestion 2 l'expose (lecture seule).
class StockSnapshot {
  const StockSnapshot({
    this.productId,
    required this.name,
    required this.quantity,
    this.unit,
    this.expiryDate,
  });

  final int? productId;
  final String name;
  final double quantity;
  final String? unit;
  final DateTime? expiryDate;
}

/// Service de la gestion 2 — Produits et Stock.
abstract interface class StockGateway {
  Future<List<StockSnapshot>> currentStock();

  /// Enregistre une sortie (consommé) dans le stock.
  Future<void> consume({
    int? productId,
    required String name,
    required double quantity,
    String? unit,
    required String reason,
  });
}

/// Profil commun du foyer, calculé par la gestion 1 (union des allergies,
/// intersection des régimes, besoins caloriques).
class HouseholdProfile {
  const HouseholdProfile({
    required this.allergies,
    required this.diets,
    required this.dailyCaloriesPerPerson,
    required this.memberCount,
  });

  final Set<String> allergies;
  final Set<String> diets;

  /// Objectif calorique moyen par personne et par jour. La gestion 6 peut
  /// l'ajuster de ±10 % selon le bilan de la veille.
  final double dailyCaloriesPerPerson;
  final int memberCount;
}

/// Service de la gestion 1 — Utilisateurs et Foyer.
abstract interface class HouseholdGateway {
  int get currentUserId;
  Future<HouseholdProfile> commonProfile();
}

/// Article à ajouter dans la liste de courses en cours (gestion 5).
class ShoppingRequest {
  const ShoppingRequest({
    required this.label,
    this.quantity,
    this.unit,
    this.productId,
    this.origin = 'recette',
  });

  final String label;
  final double? quantity;
  final String? unit;
  final int? productId;

  /// « manuel », « rupture prévue » ou « recette ».
  final String origin;
}

/// Service de la gestion 5 — Courses et Budget.
abstract interface class ShoppingGateway {
  /// Ajoute les articles à la liste en cours et renvoie le nombre ajouté.
  Future<int> addItems(List<ShoppingRequest> items);
}
