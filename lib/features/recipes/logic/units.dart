import 'text_matching.dart';

/// Quantité exprimée dans une unité de base comparable (g, ml ou autre).
class BaseQuantity {
  const BaseQuantity(this.value, this.unit);
  final double value;

  /// 'g', 'ml', 'piece' ou l'unité normalisée telle quelle.
  final String unit;
}

const _toGram = {'g': 1.0, 'gr': 1.0, 'gramme': 1.0, 'grammes': 1.0, 'kg': 1000.0, 'kilo': 1000.0, 'oz': 28.35, 'lb': 453.6};
const _toMl = {'ml': 1.0, 'cl': 10.0, 'dl': 100.0, 'l': 1000.0, 'litre': 1000.0, 'litres': 1000.0, 'cup': 240.0, 'cups': 240.0, 'tasse': 240.0, 'tbsp': 15.0, 'tbs': 15.0, 'tablespoon': 15.0, 'tablespoons': 15.0, 'cas': 15.0, 'cuillere a soupe': 15.0, 'tsp': 5.0, 'teaspoon': 5.0, 'teaspoons': 5.0, 'cac': 5.0, 'cuillere a cafe': 5.0};
const _piece = {'', 'piece', 'pieces', 'pc', 'pcs', 'unite', 'unites', 'u', 'x'};

BaseQuantity toBase(double value, String? unit) {
  final u = normalize(unit ?? '');
  if (_toGram.containsKey(u)) return BaseQuantity(value * _toGram[u]!, 'g');
  if (_toMl.containsKey(u)) return BaseQuantity(value * _toMl[u]!, 'ml');
  if (_piece.contains(u)) return BaseQuantity(value, 'piece');
  return BaseQuantity(value, u);
}
