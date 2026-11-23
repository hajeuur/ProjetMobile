import 'text_matching.dart';

/// Quantité et unité lues dans une mesure libre de TheMealDB
/// (« 1/2 cup », « 200g », « 2 tbs », « 1 1/2 tsp », « Pinch »).
class ParsedMeasure {
  const ParsedMeasure(this.quantity, this.unit);
  final double? quantity;
  final String? unit;
}

const _unicodeFractions = {
  '½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125,
};

/// Unités reconnues -> forme courte affichée.
const _unitAliases = {
  'g': 'g', 'gr': 'g', 'gram': 'g', 'grams': 'g', 'gramme': 'g', 'grammes': 'g',
  'kg': 'kg', 'kilo': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
  'ml': 'ml', 'cl': 'cl', 'dl': 'dl', 'l': 'l', 'litre': 'l', 'litres': 'l', 'liter': 'l', 'liters': 'l',
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz', 'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb',
  'cup': 'cup', 'cups': 'cup', 'tasse': 'cup', 'tasses': 'cup',
  'tbsp': 'tbsp', 'tbs': 'tbsp', 'tblsp': 'tbsp', 'tablespoon': 'tbsp', 'tablespoons': 'tbsp',
  'cas': 'tbsp', 'c a s': 'tbsp',
  'tsp': 'tsp', 'teaspoon': 'tsp', 'teaspoons': 'tsp', 'cac': 'tsp', 'c a c': 'tsp',
  'clove': 'gousse', 'cloves': 'gousse', 'gousse': 'gousse', 'gousses': 'gousse',
  'slice': 'tranche', 'slices': 'tranche', 'tranche': 'tranche', 'tranches': 'tranche',
  'can': 'boîte', 'cans': 'boîte', 'tin': 'boîte', 'tins': 'boîte',
  'piece': 'pièce', 'pieces': 'pièce', 'pc': 'pièce',
  'bunch': 'botte', 'handful': 'poignée', 'sprig': 'brin', 'sprigs': 'brin',
};

// Fraction seule (« 1/2 ») d'abord, sinon nombre suivi d'une fraction facultative (« 1 1/2 »).
final _number = RegExp(r'^(\d+)/(\d+)|^(\d+(?:[.,]\d+)?)(?:\s+(\d+)/(\d+))?');

ParsedMeasure parseMeasure(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return const ParsedMeasure(null, null);

  double? qty;
  // Fractions unicode, éventuellement précédées d'un entier (« 1½ »).
  for (final e in _unicodeFractions.entries) {
    final i = s.indexOf(e.key);
    if (i >= 0) {
      final before = s.substring(0, i).trim();
      final whole = double.tryParse(before) ?? 0;
      if (before.isEmpty || double.tryParse(before) != null) {
        qty = whole + e.value;
        s = s.substring(i + e.key.length).trim();
      }
      break;
    }
  }

  if (qty == null) {
    final m = _number.firstMatch(s);
    if (m != null) {
      if (m.group(1) != null) {
        qty = int.parse(m.group(1)!) / int.parse(m.group(2)!);
      } else {
        qty = double.parse(m.group(3)!.replaceAll(',', '.'));
        if (m.group(4) != null) qty += int.parse(m.group(4)!) / int.parse(m.group(5)!);
      }
      s = s.substring(m.end).trim();
    }
  }

  if (s.isEmpty) return ParsedMeasure(qty, null);
  final norm = normalize(s);
  // L'unité est le premier mot (ou deux pour « c a s »).
  final words = norm.split(' ');
  for (final n in [3, 1]) {
    if (words.length >= n) {
      final key = words.take(n).join(' ');
      final unit = _unitAliases[key];
      if (unit != null) return ParsedMeasure(qty, unit);
    }
  }
  // Sans quantité (« Pinch », « To taste ») : on garde le texte comme unité.
  if (qty == null) return ParsedMeasure(null, s);
  return ParsedMeasure(qty, s.length <= 12 ? s : null);
}
