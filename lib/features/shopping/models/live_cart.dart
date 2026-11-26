import 'dart:convert';

/// Article du panier en direct (mode magasin) : ajouté depuis une étiquette
/// ou un code-barres, avec le prix lu en rayon.
class LiveCartItem {
  const LiveCartItem({
    required this.label,
    required this.unitPrice,
    this.quantity = 1,
    this.barcode,
    this.perKilo = false,
    this.listItemId,
    this.priceSource,
  });

  final String label;
  final double unitPrice;
  final double quantity;
  final String? barcode;

  /// Prix au kilo (produit au poids) : la quantité est en kg.
  final bool perKilo;

  /// Article de la liste en cours coché en l'ajoutant (décoché si on le retire).
  final int? listItemId;

  /// D'où vient le prix : « ton dernier achat », « Open Prices », « étiquette »…
  final String? priceSource;

  double get total => unitPrice * quantity;

  bool sameProduct(LiveCartItem o) =>
      barcode != null && o.barcode != null ? barcode == o.barcode : label.toLowerCase() == o.label.toLowerCase();

  LiveCartItem copyWith({double? quantity, double? unitPrice, int? listItemId}) => LiveCartItem(
        label: label,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        barcode: barcode,
        perKilo: perKilo,
        listItemId: listItemId ?? this.listItemId,
        priceSource: priceSource,
      );

  Map<String, Object?> toJson() =>
      {
        'label': label,
        'price': unitPrice,
        'qty': quantity,
        'barcode': barcode,
        'perKilo': perKilo,
        'listItemId': listItemId,
        'source': priceSource,
      };

  static LiveCartItem fromJson(Map<String, dynamic> j) => LiveCartItem(
        label: j['label'] as String,
        unitPrice: (j['price'] as num).toDouble(),
        quantity: (j['qty'] as num).toDouble(),
        barcode: j['barcode'] as String?,
        perKilo: j['perKilo'] as bool? ?? false,
        listItemId: j['listItemId'] as int?,
        priceSource: j['source'] as String?,
      );

  static List<LiveCartItem> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<LiveCartItem> items) => jsonEncode([for (final i in items) i.toJson()]);
}
