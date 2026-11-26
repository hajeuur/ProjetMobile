/// Format d'un produit lu dans son libellé : « CAFE MOULU 250G », « LAIT 1L »,
/// « HUILE 500 ML », « EAU 6X1,5L », « YAOURT 4X125G ».
///
/// Normalisé en unité commune : grammes (masse) ou millilitres (volume),
/// multipacks compris (6 × 1,5 L = 9 000 ml). Un format absent ou
/// invraisemblable renvoie null : on n'affirme rien (le détecteur de
/// shrinkflation demande alors confirmation).
library;

enum Measure {
  mass('g', 'kg'),
  volume('ml', 'L');

  const Measure(this.base, this.big);

  /// Unité stockée (g ou ml).
  final String base;

  /// Unité du prix au kilo / au litre.
  final String big;

  static Measure? fromBase(String? unit) => switch (unit) { 'g' => mass, 'ml' => volume, _ => null };
}

class PackFormat {
  const PackFormat({required this.amount, required this.measure, this.count = 1});

  /// Quantité totale en g ou ml (multipack compris).
  final double amount;
  final Measure measure;

  /// Nombre d'unités d'un multipack (6 pour « 6X1,5L »).
  final int count;

  double get each => amount / count;

  /// Quantité en kg ou en L (pour le prix au kilo / au litre).
  double get bigAmount => amount / 1000;

  /// Prix au kilo ou au litre pour un prix donné.
  double pricePerBig(double price) => price / bigAmount;

  /// « 250 g », « 1,5 L », « 6 × 1,5 L ».
  String get label {
    String one(double v) {
      if (measure == Measure.mass) {
        return v >= 1000 ? '${_n(v / 1000)} kg' : '${_n(v)} g';
      }
      return v >= 1000 ? '${_n(v / 1000)} L' : v >= 100 && v % 10 == 0 && v < 1000 ? '${_n(v / 10)} cl' : '${_n(v)} ml';
    }

    return count > 1 ? '$count × ${one(each)}' : one(amount);
  }

  static String _n(double v) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return s.replaceAll('.', ',');
  }

  @override
  bool operator ==(Object other) =>
      other is PackFormat && other.amount == amount && other.measure == measure && other.count == count;

  @override
  int get hashCode => Object.hash(amount, measure, count);

  @override
  String toString() => label;
}

/// Unités reconnues → (mesure, facteur vers g ou ml).
const _units = <String, (Measure, double)>{
  'KG': (Measure.mass, 1000), 'KGS': (Measure.mass, 1000), 'KILO': (Measure.mass, 1000),
  'G': (Measure.mass, 1), 'GR': (Measure.mass, 1), 'GRS': (Measure.mass, 1), 'GRAMMES': (Measure.mass, 1),
  'L': (Measure.volume, 1000), 'LT': (Measure.volume, 1000), 'LTR': (Measure.volume, 1000), 'LITRE': (Measure.volume, 1000),
  'CL': (Measure.volume, 10), 'ML': (Measure.volume, 1),
};

const _unit = r'(KGS?|KILO|GRAMMES|GRS?|G|LTR|LT|LITRE|L|CL|ML)';
const _num = r'(\d+(?:\.\d+)?)';

// « 6X1.5L », « 4 X 125G », « 6*33CL »
final _packFirst = RegExp('(?<![\\d.])(\\d{1,2})\\s*[X×*]\\s*$_num\\s*$_unit(?![A-Z])');
// « 1.5L X6 », « 125G X 4 »
final _packLast = RegExp('(?<![\\d.])$_num\\s*$_unit\\s*[X×*]\\s*(\\d{1,2})(?![\\d.])');
// « 250G », « 500 ML », « 1L »
final _single = RegExp('(?<![\\d.A-Z])$_num\\s*$_unit(?![A-Z])');

PackFormat? parsePackFormat(String label) {
  // Virgule décimale tunisienne : « 1,5L » → « 1.5L ».
  final t = label.toUpperCase().replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');

  PackFormat? make(String n, String unit, int count) {
    final u = _units[unit];
    final v = double.tryParse(n);
    if (u == null || v == null || v <= 0) return null;
    final total = v * u.$2 * count;
    // Invraisemblable : on n'affirme rien.
    if (total < 5 || total > 50000) return null;
    return PackFormat(amount: total, measure: u.$1, count: count);
  }

  final a = _packFirst.firstMatch(t);
  if (a != null) return make(a[2]!, a[3]!, int.parse(a[1]!));
  final b = _packLast.firstMatch(t);
  if (b != null) return make(b[1]!, b[2]!, int.parse(b[3]!));

  final singles = _single.allMatches(t).toList();
  if (singles.isEmpty) return null;
  final formats = [for (final m in singles) ?make(m[1]!, m[2]!, 1)];
  if (formats.isEmpty) return null;
  // Deux formats différents dans le libellé (« 1L 500G ») : ambigu.
  if (formats.toSet().length > 1) return null;
  return formats.first;
}
