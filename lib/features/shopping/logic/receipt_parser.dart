/// Lecture du texte d'un ticket de caisse : lignes (libellé, quantité, prix),
/// total, date et en-tête (nom du magasin).
///
/// Formats pris en charge (tickets tunisiens et français) :
/// - `LAIT DELICE 1L          1,350` (prix en fin de ligne, 2 ou 3 décimales) ;
/// - `2 x 0,900               1,800` sur la ligne suivante (quantité × prix unitaire) ;
/// - `YAOURT VITALAIT 4 x 0,600  2,400` (quantité dans la ligne) ;
/// - `0,750 kg x 2,800        2,100` (pesée) ;
/// - libellé sur une ligne et prix seul sur la suivante (lecture découpée) ;
/// - `REMISE                 -0,500` (ligne négative) ;
/// - `TOTAL`, `TOTAL TTC`, `NET A PAYER` : total ; les lignes de paiement qui
///   suivent (espèces, rendu…) sont ignorées.
library;

import 'text_similarity.dart';

class ParsedLine {
  const ParsedLine({required this.label, this.quantity = 1, required this.price, this.barcode});

  final String label;
  final double quantity;

  /// Prix de la ligne entière.
  final double price;
  final String? barcode;

  ParsedLine copyWith({String? label, double? quantity, double? price}) => ParsedLine(
        label: label ?? this.label,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        barcode: barcode,
      );
}

class ParsedReceipt {
  const ParsedReceipt({required this.lines, this.total, this.date, this.headerLines = const []});

  final List<ParsedLine> lines;

  /// Total lu sur le ticket, s'il a été trouvé.
  final double? total;
  final DateTime? date;

  /// Premières lignes sans prix : nom du magasin, adresse…
  final List<String> headerLines;

  double get linesSum => lines.fold(0.0, (s, l) => s + l.price);

  /// Total à retenir : celui du ticket, sinon la somme des lignes.
  double get effectiveTotal => total ?? linesSum;

  /// Vrai si la somme des lignes correspond au total lu (à 10 millimes près).
  bool get isConsistent => total == null || (total! - linesSum).abs() < 0.011;
}

const _amount = r'(\d{1,5}[.,]\d{2,3})';
const _currency = r'(?:dt|tnd|d|eur|€)?';

final _trailingPrice = RegExp('^(.*?)\\s*(-?)\\s*$_amount\\s*$_currency\\s*[a-z*]?\\s*\$', caseSensitive: false);
final _qtyRow = RegExp(
  '^\\s*(\\d+(?:[.,]\\d+)?)\\s*(?:kg|g|l|pc|pcs)?\\s*[x*]\\s*$_amount\\s*$_currency\\s*(?:=\\s*)?(?:$_amount)?\\s*$_currency\\s*[a-z*]?\\s*\$',
  caseSensitive: false,
);
final _inlineQty = RegExp('^(.*?)\\s+(\\d+(?:[.,]\\d+)?)\\s*(?:kg|g|l|pc|pcs)?\\s*[x*]\\s*$_amount\\s*\$', caseSensitive: false);
final _leadingQty = RegExp(r'^(\d{1,2})\s*[x*]\s+(.+)$', caseSensitive: false);
final _leadingBarcode = RegExp(r'^(\d{8,13})\s+(.+)$');
final _date = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b');

const _skipWords = [
  'tva', 'ht', 'espece', 'especes', 'rendu', 'monnaie', 'carte', 'cb', 'visa', 'mastercard', 'cheque',
  'ticket', 'caisse', 'caissier', 'caissiere', 'merci', 'tel', 'fax', 'matricule', 'mf', 'sous total',
  'ss total', 'nb article', 'nombre article', 'nbre article', 'client', 'point', 'points', 'bienvenue',
  'www', 'facture', 'avoir', 'solde', 'paiement', 'regle', 'recu', 'heure', 'date',
];

const _totalWords = ['net a payer', 'a payer', 'total ttc', 'total', 'montant du', 'montant total'];

double _num(String s) => double.parse(s.replaceAll(',', '.'));

bool _hasWord(String normalized, String word) => RegExp('(^| )${RegExp.escape(word)}( |\$)').hasMatch(normalized);

bool _hasLetters(String s) => RegExp(r'[a-zA-Zéèàùç]{2,}').hasMatch(s);

String _cleanLabel(String s) =>
    s.replaceAll(RegExp(r'[\s.:*_\-]+$'), '').replaceAll(RegExp(r'^[\s.:*_\-]+'), '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

ParsedReceipt parseReceiptText(String text) {
  final rows = text.split(RegExp(r'\r?\n')).map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
  final lines = <ParsedLine>[];
  final header = <String>[];
  double? total;
  var totalPriority = -1;
  DateTime? date;
  String? pendingLabel;
  var afterTotal = false;
  var awaitingTotalPriority = -1;

  for (final row in rows) {
    final n = normalize(row);
    date ??= _parseDate(row);

    // Montant du total lu seul sur la ligne qui suit « TOTAL ».
    if (awaitingTotalPriority >= 0) {
      final m = _trailingPrice.firstMatch(row);
      if (m != null && !_hasLetters(m.group(1)!)) {
        if (awaitingTotalPriority > totalPriority) {
          total = _num(m.group(3)!);
          totalPriority = awaitingTotalPriority;
        }
        awaitingTotalPriority = -1;
        continue;
      }
      awaitingTotalPriority = -1;
    }

    // Total (le plus explicite l'emporte : « net à payer » > « total »).
    final totalIndex = _totalWords.indexWhere((w) => _hasWord(n, w));
    if (totalIndex >= 0 && !_hasWord(n, 'sous') && !_hasWord(n, 'ss') && !_hasWord(n, 'tva') && !_hasWord(n, 'ht')) {
      final m = _trailingPrice.firstMatch(row);
      if (m != null) {
        final priority = _totalWords.length - totalIndex;
        if (priority > totalPriority) {
          total = _num(m.group(3)!);
          totalPriority = priority;
        }
        afterTotal = true;
        pendingLabel = null;
        continue;
      }
      if (!RegExp(r'\d').hasMatch(row)) {
        awaitingTotalPriority = _totalWords.length - totalIndex;
        afterTotal = true;
        pendingLabel = null;
        continue;
      }
    }
    if (afterTotal) continue;
    if (_skipWords.any((w) => _hasWord(n, w))) {
      pendingLabel = null;
      continue;
    }

    // « 2 x 0,900   1,800 » : précise la ligne précédente.
    final q = _qtyRow.firstMatch(row);
    if (q != null && (lines.isNotEmpty || pendingLabel != null)) {
      final qty = _num(q.group(1)!);
      final unit = _num(q.group(2)!);
      final lineTotal = q.group(3) != null ? _num(q.group(3)!) : _round(qty * unit);
      if (pendingLabel != null) {
        // « LAIT » puis « 2 x 0,900  1,800 » : nouvelle ligne.
        if (lines.isEmpty && header.isNotEmpty && header.last == pendingLabel) header.removeLast();
        lines.add(ParsedLine(label: pendingLabel, quantity: qty, price: lineTotal));
        pendingLabel = null;
      } else {
        // « LAIT  1,800 » puis « 2 x 0,900 » : précise la ligne précédente.
        final prev = lines.removeLast();
        lines.add(prev.copyWith(quantity: qty, price: lineTotal));
      }
      continue;
    }

    final m = _trailingPrice.firstMatch(row);
    if (m == null) {
      if (_hasLetters(row)) {
        if (lines.isEmpty && header.length < 4) header.add(_cleanLabel(row));
        pendingLabel = _cleanLabel(row);
      }
      continue;
    }

    var label = _cleanLabel(m.group(1)!);
    final negative = m.group(2) == '-';
    var price = _num(m.group(3)!) * (negative ? -1 : 1);
    var qty = 1.0;

    if (!_hasLetters(label)) {
      // Prix seul : il appartient au libellé lu juste avant.
      if (pendingLabel == null) continue;
      if (lines.isEmpty && header.isNotEmpty && header.last == pendingLabel) header.removeLast();
      label = pendingLabel;
    }
    pendingLabel = null;

    final inline = _inlineQty.firstMatch(label);
    if (inline != null && _hasLetters(inline.group(1)!)) {
      label = _cleanLabel(inline.group(1)!);
      qty = _num(inline.group(2)!);
    } else {
      final lead = _leadingQty.firstMatch(label);
      if (lead != null) {
        qty = double.parse(lead.group(1)!);
        label = _cleanLabel(lead.group(2)!);
      }
    }

    String? barcode;
    final bc = _leadingBarcode.firstMatch(label);
    if (bc != null) {
      barcode = bc.group(1);
      label = _cleanLabel(bc.group(2)!);
    }
    if (_hasWord(normalize(label), 'remise') || _hasWord(normalize(label), 'reduction')) {
      price = -price.abs();
    }
    lines.add(ParsedLine(label: label, quantity: qty, price: price, barcode: barcode));
  }

  return ParsedReceipt(lines: lines, total: total, date: date, headerLines: header);
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;

DateTime? _parseDate(String row) {
  final m = _date.firstMatch(row);
  if (m == null) return null;
  final d = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  var y = int.parse(m.group(3)!);
  if (y < 100) y += 2000;
  if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 2000 || y > 2100) return null;
  return DateTime(y, mo, d);
}
