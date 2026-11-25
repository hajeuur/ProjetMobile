import 'dates.dart';

/// Statut d'une liste de courses (cahier des charges : « en cours, terminée »).
enum ListStatus {
  active('active', 'En cours'),
  done('done', 'Terminée');

  const ListStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ListStatus fromDb(String v) => values.firstWhere((s) => s.dbValue == v, orElse: () => active);
}

/// Origine d'un article : saisi à la main, rupture prévue (gestion 2) ou
/// ingrédient manquant d'une recette (gestion 3).
enum ItemOrigin {
  manual('manual', 'Manuel'),
  shortage('shortage', 'Rupture prévue'),
  recipe('recipe', 'Recette'),
  voice('voice', 'Voix'),

  /// Oublié lors des courses précédentes (rapprochement du ticket).
  forgotten('forgotten', 'Oublié');

  const ItemOrigin(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ItemOrigin fromDb(String v) => values.firstWhere((o) => o.dbValue == v, orElse: () => manual);

  /// Valeurs utilisées par les autres gestions (« manuel », « rupture prévue », « recette »).
  static ItemOrigin fromLabel(String v) {
    final l = v.toLowerCase();
    if (l.startsWith('rupture') || l == 'shortage') return shortage;
    if (l.startsWith('recette') || l == 'recipe') return recipe;
    if (l.startsWith('voix') || l == 'voice') return voice;
    if (l.startsWith('oubli') || l == 'forgotten') return forgotten;
    return manual;
  }
}

class ShoppingList {
  const ShoppingList({
    this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    this.storeId,
    this.status = ListStatus.active,
    this.itemCount = 0,
    this.checkedCount = 0,
  });

  final int? id;
  final int userId;
  final String name;
  final DateTime createdAt;

  /// Magasin visé (gestion 4), facultatif.
  final int? storeId;
  final ListStatus status;

  /// Rempli par les requêtes de liste (non stocké).
  final int itemCount;
  final int checkedCount;

  double get progress => itemCount == 0 ? 0 : checkedCount / itemCount;

  ShoppingList copyWith({String? name, int? storeId, bool clearStore = false, ListStatus? status}) => ShoppingList(
        id: id,
        userId: userId,
        name: name ?? this.name,
        createdAt: createdAt,
        storeId: clearStore ? null : (storeId ?? this.storeId),
        status: status ?? this.status,
        itemCount: itemCount,
        checkedCount: checkedCount,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'store_id': storeId,
        'status': status.dbValue,
      };

  factory ShoppingList.fromMap(Map<String, Object?> m) => ShoppingList(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        name: m['name'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        storeId: m['store_id'] as int?,
        status: ListStatus.fromDb(m['status'] as String),
        itemCount: (m['item_count'] as int?) ?? 0,
        checkedCount: (m['checked_count'] as int?) ?? 0,
      );
}

class ShoppingItem {
  const ShoppingItem({
    this.id,
    required this.listId,
    required this.label,
    this.productId,
    this.quantity,
    this.unit,
    this.checked = false,
    this.origin = ItemOrigin.manual,
    this.aisle,
    this.position = 0,
    this.createdAt,
  });

  final int? id;
  final int listId;
  final String label;

  /// Produit de la gestion 2, facultatif.
  final int? productId;
  final double? quantity;
  final String? unit;
  final bool checked;
  final ItemOrigin origin;

  /// Rayon (catégorie) utilisé pour trier la liste selon le magasin.
  final String? aisle;

  /// Ordre d'ajout.
  final int position;
  final DateTime? createdAt;

  String get quantityText => formatQuantity(quantity, unit);

  ShoppingItem copyWith({
    String? label,
    double? quantity,
    bool clearQuantity = false,
    String? unit,
    bool? checked,
    String? aisle,
    int? productId,
    ItemOrigin? origin,
  }) =>
      ShoppingItem(
        id: id,
        listId: listId,
        label: label ?? this.label,
        productId: productId ?? this.productId,
        quantity: clearQuantity ? null : (quantity ?? this.quantity),
        unit: clearQuantity ? null : (unit ?? this.unit),
        checked: checked ?? this.checked,
        origin: origin ?? this.origin,
        aisle: aisle ?? this.aisle,
        position: position,
        createdAt: createdAt,
      );

  /// Même article sous un nouvel identifiant (après réinsertion).
  ShoppingItem withId(int newId) => ShoppingItem(
        id: newId,
        listId: listId,
        label: label,
        productId: productId,
        quantity: quantity,
        unit: unit,
        checked: checked,
        origin: origin,
        aisle: aisle,
        position: position,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'list_id': listId,
        'label': label,
        'product_id': productId,
        'quantity': quantity,
        'unit': unit,
        'checked': checked ? 1 : 0,
        'origin': origin.dbValue,
        'aisle': aisle,
        'position': position,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };

  factory ShoppingItem.fromMap(Map<String, Object?> m) => ShoppingItem(
        id: m['id'] as int,
        listId: m['list_id'] as int,
        label: m['label'] as String,
        productId: m['product_id'] as int?,
        quantity: (m['quantity'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        checked: (m['checked'] as int) == 1,
        origin: ItemOrigin.fromDb(m['origin'] as String),
        aisle: m['aisle'] as String?,
        position: m['position'] as int,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? ''),
      );
}
