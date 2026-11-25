/// Ticket de caisse et ses lignes (tables receipts et receipt_lines).
class Receipt {
  const Receipt({
    this.id,
    required this.userId,
    this.storeId,
    this.storeName,
    required this.date,
    required this.total,
    this.photo,
    this.listId,
    this.lines = const [],
    this.lineCount = 0,
  });

  final int? id;
  final int userId;

  /// Magasin (gestion 4). Le nom est recopié pour la recherche hors ligne.
  final int? storeId;
  final String? storeName;
  final DateTime date;
  final double total;

  /// Chemin local de la photo du ticket.
  final String? photo;

  /// Liste de courses rapprochée avec ce ticket.
  final int? listId;
  final List<ReceiptLine> lines;

  /// Rempli par les requêtes de liste (non stocké).
  final int lineCount;

  double get linesTotal => lines.fold(0, (s, l) => s + l.price);

  Receipt copyWith({
    int? storeId,
    String? storeName,
    DateTime? date,
    double? total,
    String? photo,
    int? listId,
    List<ReceiptLine>? lines,
  }) =>
      Receipt(
        id: id,
        userId: userId,
        storeId: storeId ?? this.storeId,
        storeName: storeName ?? this.storeName,
        date: date ?? this.date,
        total: total ?? this.total,
        photo: photo ?? this.photo,
        listId: listId ?? this.listId,
        lines: lines ?? this.lines,
        lineCount: lineCount,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'store_id': storeId,
        'store_name': storeName,
        'date': date.toIso8601String(),
        'total': total,
        'photo': photo,
        'list_id': listId,
      };

  factory Receipt.fromMap(Map<String, Object?> m, {List<ReceiptLine> lines = const []}) => Receipt(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        storeId: m['store_id'] as int?,
        storeName: m['store_name'] as String?,
        date: DateTime.parse(m['date'] as String),
        total: (m['total'] as num).toDouble(),
        photo: m['photo'] as String?,
        listId: m['list_id'] as int?,
        lines: lines,
        lineCount: (m['line_count'] as int?) ?? lines.length,
      );
}

class ReceiptLine {
  const ReceiptLine({
    this.id,
    this.receiptId,
    required this.label,
    this.productId,
    this.barcode,
    this.quantity = 1,
    required this.price,
    this.category,
  });

  final int? id;
  final int? receiptId;

  /// Libellé tel que lu sur le ticket (corrigeable).
  final String label;

  /// Produit rapproché (gestion 2), facultatif.
  final int? productId;

  /// Code-barres du produit, utile pour Open Prices.
  final String? barcode;
  final double quantity;

  /// Prix payé pour la ligne entière (quantité comprise).
  final double price;
  final String? category;

  double get unitPrice => quantity <= 0 ? price : price / quantity;

  ReceiptLine copyWith({
    String? label,
    int? productId,
    String? barcode,
    double? quantity,
    double? price,
    String? category,
  }) =>
      ReceiptLine(
        id: id,
        receiptId: receiptId,
        label: label ?? this.label,
        productId: productId ?? this.productId,
        barcode: barcode ?? this.barcode,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        category: category ?? this.category,
      );

  Map<String, Object?> toMap(int receiptId) => {
        if (id != null) 'id': id,
        'receipt_id': receiptId,
        'label': label,
        'product_id': productId,
        'barcode': barcode,
        'quantity': quantity,
        'price': price,
        'category': category,
      };

  factory ReceiptLine.fromMap(Map<String, Object?> m) => ReceiptLine(
        id: m['id'] as int,
        receiptId: m['receipt_id'] as int,
        label: m['label'] as String,
        productId: m['product_id'] as int?,
        barcode: m['barcode'] as String?,
        quantity: (m['quantity'] as num).toDouble(),
        price: (m['price'] as num).toDouble(),
        category: m['category'] as String?,
      );
}
