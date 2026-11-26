/// Lecture d'une étiquette de prix en rayon (OCR d'une image).
///
/// - **Prix** : « 7,900 DT », « 7.9 », « 7 900 » (dinars en gros, millimes en
///   petit), « 7DT900 », « 8 DT ». Quand plusieurs montants sont lus, on
///   retient celui écrit le plus gros (hauteur de la rangée), en écartant le
///   prix au kilo / au litre (« LE KG 34,750 », « 1,5 DT/KG »).
/// - **Prix au kilo** : gardé à part ; s'il est le seul prix (fruits,
///   légumes au poids), c'est lui le prix, signalé « au kilo ».
/// - **Code-barres** : 8 ou 13 chiffres avec une clé de contrôle juste,
///   prioritaire pour retrouver le produit.
/// - **Nom** : rangées avec des lettres, hors mots de service (PRIX, PROMO,
///   TTC, LE KG…), dans l'ordre de l'étiquette.
library;

import 'dart:ui' show Rect;

import 'budget_forecast.dart' show shortDt;
import 'live_receipt_parser.dart' show LiveOcrRow;
import 'product_price.dart' show PricePoint, isValidBarcode;

class ShelfLabelReading {
  const ShelfLabelReading({
    this.name,
    this.price,
    this.perKiloPrice,
    this.priceIsPerKilo = false,
    this.barcode,
    this.priceBox,
  });

  final String? name;

  /// Prix affiché (par article, ou au kilo si [priceIsPerKilo]).
  final double? price;

  /// Prix au kilo / au litre indiqué à côté.
  final double? perKiloPrice;
  final bool priceIsPerKilo;
  final String? barcode;

  /// Position du prix sur l'image (surbrillance).
  final Rect? priceBox;

  bool get hasPrice => price != null;
}

const _serviceWords = {
  'prix', 'promo', 'promotion', 'ttc', 'ht', 'dt', 'tnd', 'le', 'kg', 'l', 'au', 'litre', 'kilo', 'unite',
  'unité', 'offre', 'nouveau', 'soit', 'prix/kg', 'prix/l', 'pce', 'piece', 'pièce', 'x',
};

final _perKilo = RegExp(r'(/\s*(KG|L|LT|LITRE|KILO)\b|\b(LE|AU|PAR)\s+(KG|KILO|LITRE|L)\b|\bPRIX\s*/\s*(KG|L)\b)', caseSensitive: false);
final _eanRun = RegExp(r'(?<!\d)(\d[\d ]{6,16}\d)(?!\d)');
final _dateLike = RegExp(r'\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b');

// Montants, du plus explicite au moins explicite.
final _dtSplit = RegExp(r'(?<![\d.,])(\d{1,3})\s*(?:DT|D|TND)\s*(\d{3})(?!\d)', caseSensitive: false); // 7DT900
final _decimal = RegExp(r'(?<![\d.,])(\d{1,3})\s?[.,]\s?(\d{1,3})(?![\d.,])'); // 7,900 / 7.9
final _spaced = RegExp(r'(?<![\d.,])(\d{1,3}) (\d{3})(?![\d.,])'); // 7 900
final _wholeDt = RegExp(r'(?<![\d.,])(\d{1,3})\s*(?:DT|TND)\b', caseSensitive: false); // 8 DT

class _Candidate {
  _Candidate(this.value, this.row, {required this.perKilo});
  final double value;
  final LiveOcrRow row;
  final bool perKilo;
}

ShelfLabelReading parseShelfLabel(List<LiveOcrRow> rows) {
  String? barcode;
  final candidates = <_Candidate>[];
  final nameRows = <String>[];

  for (final row in rows) {
    var t = row.text.trim();
    if (t.isEmpty) continue;

    // Code-barres : chiffres imprimés sous les barres (espaces tolérés).
    for (final m in _eanRun.allMatches(t)) {
      final digits = m[1]!.replaceAll(' ', '');
      if ((digits.length == 13 || digits.length == 8) && isValidBarcode(digits)) {
        barcode ??= digits;
        t = t.replaceFirst(m[0]!, ' ');
      }
    }
    t = t.replaceAll(_dateLike, ' ');

    final perKilo = _perKilo.hasMatch(t);
    final values = <double>[];
    for (final m in _dtSplit.allMatches(t)) {
      values.add(int.parse(m[1]!) + int.parse(m[2]!) / 1000);
    }
    if (values.isEmpty) {
      for (final m in _decimal.allMatches(t)) {
        final dec = m[2]!;
        // « 7,9 » = 7,900 ; « 7,90 » = 7,900 ; « 7,900 » = 7,900.
        values.add(int.parse(m[1]!) + int.parse(dec.padRight(3, '0')) / 1000);
      }
    }
    if (values.isEmpty) {
      for (final m in _spaced.allMatches(t)) {
        values.add(int.parse(m[1]!) + int.parse(m[2]!) / 1000);
      }
    }
    if (values.isEmpty) {
      for (final m in _wholeDt.allMatches(t)) {
        values.add(double.parse(m[1]!));
      }
    }
    for (final v in values) {
      if (v > 0 && v < 1000) candidates.add(_Candidate(v, row, perKilo: perKilo));
    }

    // Nom : mots de 2 lettres ou plus, hors mots de service et montants.
    final words = [
      for (final w in t.split(RegExp(r'\s+')))
        // Mot d'au moins 2 lettres, ou format (« 1L », « 400G ») qui fait partie du nom.
        if ((RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(w) ||
                RegExp(r'^\d+([.,]\d+)?(G|GR|KG|L|CL|ML)$', caseSensitive: false).hasMatch(w)) &&
            !_serviceWords.contains(w.toLowerCase().replaceAll(RegExp(r'[:.!]'), '')))
          w,
    ];
    if (values.isEmpty && words.isNotEmpty && !perKilo) nameRows.add(words.join(' '));
  }

  final unit = [for (final c in candidates) if (!c.perKilo) c];
  final kilo = [for (final c in candidates) if (c.perKilo) c];
  _Candidate? biggest(List<_Candidate> list) =>
      list.isEmpty ? null : list.reduce((a, b) => b.row.box.height > a.row.box.height ? b : a);
  final main = biggest(unit);
  final perKg = biggest(kilo);
  final name = nameRows.take(2).join(' ').trim();

  if (main == null && perKg != null) {
    // Produit au poids : le seul prix est le prix au kilo.
    return ShelfLabelReading(
      name: name.isEmpty ? null : name,
      price: perKg.value,
      perKiloPrice: perKg.value,
      priceIsPerKilo: true,
      barcode: barcode,
      priceBox: perKg.row.box,
    );
  }
  return ShelfLabelReading(
    name: name.isEmpty ? null : name,
    price: main?.value,
    perKiloPrice: perKg?.value,
    barcode: barcode,
    priceBox: main?.row.box,
  );
}

/// Vote sur plusieurs images : une lecture n'est retenue que si le même prix
/// est lu sur au moins [confirmAfter] images (évite les lectures fantaisistes).
class ShelfLabelTracker {
  ShelfLabelTracker({this.confirmAfter = 2});
  final int confirmAfter;

  final _prices = <double, int>{};
  final _names = <String, int>{};
  String? _barcode;
  ShelfLabelReading? _last;
  int frames = 0;
  int framesWithText = 0;

  /// Lecture confirmée (null tant que le prix n'est pas stable).
  ShelfLabelReading? confirmed;

  void add(ShelfLabelReading r, {required bool hadText}) {
    frames++;
    if (hadText) framesWithText++;
    if (r.barcode != null) _barcode = r.barcode;
    if (r.name != null) _names[r.name!] = (_names[r.name!] ?? 0) + 1;
    if (r.price == null) return;
    _last = r;
    final n = (_prices[r.price!] ?? 0) + 1;
    _prices[r.price!] = n;
    if (n >= confirmAfter && confirmed == null) {
      final name = _names.isEmpty ? null : _names.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      confirmed = ShelfLabelReading(
        name: name,
        price: r.price,
        perKiloPrice: r.perKiloPrice,
        priceIsPerKilo: r.priceIsPerKilo,
        barcode: _barcode,
        priceBox: r.priceBox,
      );
    }
  }

  ShelfLabelReading? get last => _last;
}

// ------------------------------------------------------------- Verdict

enum ShelfVerdictKind {
  /// Moins cher que d'habitude (vert).
  cheaper,

  /// Plus cher que le dernier achat (rouge).
  dearer,

  /// Dans la norme : rappel du dernier prix payé.
  usual,

  /// Jamais acheté.
  unknown,
}

class ShelfVerdict {
  const ShelfVerdict(this.kind, this.text);
  final ShelfVerdictKind kind;
  final String text;
}

/// Bulle affichée sur l'étiquette : « 12 % moins cher que d'habitude »,
/// « 8 % plus cher que ton dernier achat » ou « Déjà payé 1,2 DT chez
/// Carrefour ». « D'habitude » = moyenne de mes achats des 3 derniers mois
/// (à défaut, de tous). Écart retenu à partir de 5 %.
ShelfVerdict shelfVerdict({
  required double price,
  required List<PricePoint> history,
  required DateTime now,
}) {
  if (history.isEmpty) return const ShelfVerdict(ShelfVerdictKind.unknown, 'Jamais acheté d\'après tes tickets');
  final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
  final recent = sorted.where((p) => now.difference(p.date).inDays <= 90).toList();
  final base = recent.isEmpty ? sorted : recent;
  final usual = base.fold(0.0, (s, p) => s + p.unitPrice) / base.length;
  final last = sorted.last;
  final belowUsual = (usual - price) / usual;
  if (belowUsual >= 0.05) {
    return ShelfVerdict(ShelfVerdictKind.cheaper, '${(belowUsual * 100).round()} % moins cher que d\'habitude');
  }
  final aboveLast = (price - last.unitPrice) / last.unitPrice;
  if (aboveLast >= 0.05) {
    return ShelfVerdict(ShelfVerdictKind.dearer, '${(aboveLast * 100).round()} % plus cher que ton dernier achat');
  }
  final where = last.store == null ? '' : ' chez ${last.store}';
  return ShelfVerdict(ShelfVerdictKind.usual, 'Déjà payé ${shortDt(last.unitPrice)}$where');
}
