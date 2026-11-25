/// Represents a row in the `store_prices` table.
///
/// [price] is in TND (DT) with 3 decimal precision, stored as REAL.
/// [recordedAt] is an ISO-8601 string (e.g. '2026-11-25T20:00:00.000').
class StorePrice {
  const StorePrice({
    this.id,
    required this.storeId,
    required this.productId,
    required this.price,
    required this.recordedAt,
  });

  final int? id;
  final int storeId;
  final int productId;
  final double price; // DT — 3 decimal places
  final String recordedAt; // ISO-8601

  // ── Serialization ──────────────────────────────────────────────────────────

  factory StorePrice.fromMap(Map<String, dynamic> m) => StorePrice(
        id: m['id'] as int?,
        storeId: m['store_id'] as int,
        productId: m['product_id'] as int,
        price: (m['price'] as num).toDouble(),
        recordedAt: m['recorded_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'store_id': storeId,
        'product_id': productId,
        'price': price,
        'recorded_at': recordedAt,
      };

  // ── copyWith ───────────────────────────────────────────────────────────────

  StorePrice copyWith({
    int? id,
    int? storeId,
    int? productId,
    double? price,
    String? recordedAt,
  }) =>
      StorePrice(
        id: id ?? this.id,
        storeId: storeId ?? this.storeId,
        productId: productId ?? this.productId,
        price: price ?? this.price,
        recordedAt: recordedAt ?? this.recordedAt,
      );

  @override
  String toString() =>
      'StorePrice(id: $id, storeId: $storeId, productId: $productId, '
      'price: $price DT, recordedAt: $recordedAt)';
}
