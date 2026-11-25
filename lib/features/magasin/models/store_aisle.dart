/// Represents a row in the `store_aisles` table.
class StoreAisle {
  const StoreAisle({
    this.id,
    required this.storeId,
    required this.name,
    required this.sortOrder,
  });

  final int? id;
  final int storeId;
  final String name;
  final int sortOrder;

  // ── Serialization ──────────────────────────────────────────────────────────

  factory StoreAisle.fromMap(Map<String, dynamic> m) => StoreAisle(
        id: m['id'] as int?,
        storeId: m['store_id'] as int,
        name: m['name'] as String,
        sortOrder: m['sort_order'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'store_id': storeId,
        'name': name,
        'sort_order': sortOrder,
      };

  // ── copyWith ───────────────────────────────────────────────────────────────

  StoreAisle copyWith({
    int? id,
    int? storeId,
    String? name,
    int? sortOrder,
  }) =>
      StoreAisle(
        id: id ?? this.id,
        storeId: storeId ?? this.storeId,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  @override
  String toString() =>
      'StoreAisle(id: $id, storeId: $storeId, name: $name, sortOrder: $sortOrder)';
}
