/// Lecture d'UNE image du flux caméra : quelles rangées de texte sont des
/// lignes d'article (libellé + prix), lequel est le total, avec un score de
/// confiance pour chacune.
///
/// Formats tunisiens pris en charge :
/// - virgule ou point décimal, 3 décimales (millimes) : `1,350` `1.350` ;
/// - devise collée ou séparée, avant ou après : `1,350 DT` `1,350DT` `DT 1,350`
///   `1.350 TND` `1,350 D` ;
/// - milliers séparés par une espace : `1 250,000` ;
/// - quantité : `2 x 0,900   1,800` (ligne seule ou dans le libellé), `3x YAOURT` ;
/// - remise négative : `REMISE  -0,500` ;
/// - total : `TOTAL`, `TOTAL TTC`, `TTC`, `À PAYER`, `NET À PAYER` (montant sur
///   la même rangée ou la suivante). Sous-total, TVA et HT ne sont pas le total.
///
/// Confusions classiques de la reconnaissance corrigées dans les montants
/// (`O`→0, `l`/`I`→1, `S`→5, `B`→8), au prix d'une confiance plus basse.
library;

import 'dart:ui' show Rect;

import 'text_similarity.dart';

/// Une rangée de texte lue sur l'image, avec sa position (coordonnées
/// relatives 0–1 de l'image droite) et la confiance de la reconnaissance.
class LiveOcrRow {
  const LiveOcrRow(this.text, {this.box = Rect.zero, this.confidence});

  final String text;
  final Rect box;

  /// Confiance de ML Kit (0–1), si la plateforme la fournit (Android).
  final double? confidence;
}

/// Montant lu dans un texte.
class ParsedAmount {
  const ParsedAmount(this.value, {required this.decimals, this.corrected = false});

  final double value;

  /// Nombre de décimales lues (3 = millimes, format tunisien).
  final int decimals;

  /// Des lettres ont été remplacées par des chiffres (`1,3S0` → 1,350).
  final bool corrected;
}

class LiveLine {
  const LiveLine({
    required this.label,
    required this.price,
    this.quantity = 1,
    required this.confidence,
    this.box = Rect.zero,
    this.rowIndex = 0,
  });

  final String label;
  final double quantity;

  /// Prix de la ligne entière (négatif pour une remise).
  final double price;

  /// 0 à 1 : en dessous de [LiveReceiptParser.doubtfulBelow], ligne douteuse.
  final double confidence;
  final Rect box;
  final int rowIndex;

  bool get isDoubtful => confidence < LiveReceiptParser.doubtfulBelow;

  LiveLine copyWith({double? quantity, double? price, double? confidence, Rect? box}) => LiveLine(
        label: label,
        price: price ?? this.price,
        quantity: quantity ?? this.quantity,
        confidence: confidence ?? this.confidence,
        box: box ?? this.box,
        rowIndex: rowIndex,
      );

  @override
  String toString() => '$label ${quantity == 1 ? '' : '$quantity× '}$price (${confidence.toStringAsFixed(2)})';
}

class LiveTotal {
  const LiveTotal(this.value, {required this.confidence, this.box = Rect.zero, required this.priority});

  final double value;
  final double confidence;
  final Rect box;

  /// « net à payer » (le plus explicite) l'emporte sur « total ».
  final int priority;
}

/// Résultat de la lecture d'une image.
class LiveFrameReading {
  const LiveFrameReading({
    required this.lines,
    this.total,
    this.date,
    this.headerLines = const [],
    this.textRows = 0,
  });

  final List<LiveLine> lines;
  final LiveTotal? total;
  final DateTime? date;

  /// Rangées sans prix avant la première ligne : nom du magasin, adresse…
  final List<String> headerLines;

  /// Nombre de rangées de texte vues (même sans prix) : distingue « pas de
  /// ticket » de « ticket illisible ».
  final int textRows;

  double get linesSum => lines.fold(0.0, (s, l) => s + l.price);
}

class LiveReceiptParser {
  const LiveReceiptParser();

  /// Seuil sous lequel une ligne est affichée en orange.
  static const doubtfulBelow = 0.6;

  // Montant : « 1,350 » « 1.350 » « 1 250,000 » « 12,5 » ; lettres
  // confondues avec des chiffres acceptées (corrigées ensuite).
  static const _d = r'[0-9OoIlSB]';
  static final _amountAtEnd = RegExp(
    // Sensible à la casse : « 1,5L » (contenance) n'est pas « 1,51 ».
    '(-|–)?\\s*(?:(?:DT|dt|Dt|TND|tnd)\\s*)?($_d{1,3}(?: \\d{3})*|$_d{1,5})\\s?[.,]\\s?($_d{2,3})'
    '\\s*(?:DT|dt|Dt|TND|tnd|D|€)?\\s*[A-Za-z*]?\\s*\$',
  );
  static final _qtyRow = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*(?:kg|g|l|pc|pcs|u)?\s*[x×*]\s*(\d{1,5}[.,]\d{2,3})\s*(?:dt|tnd|d)?\s*(?:=\s*)?(?:(\d{1,5}[.,]\d{2,3})\s*(?:dt|tnd|d)?)?\s*$',
    caseSensitive: false,
  );
  static final _inlineQty =
      RegExp(r'^(.*?)\s+(\d+(?:[.,]\d+)?)\s*(?:kg|g|l|pc|pcs|u)?\s*[x×*]\s*(\d{1,5}[.,]\d{2,3})\s*(?:dt|tnd|d)?$', caseSensitive: false);
  static final _leadingQty = RegExp(r'^(\d{1,2})\s*[x×*]\s+(.+)$', caseSensitive: false);
  static final _leadingBarcode = RegExp(r'^\d{8,13}\s+');
  static final _date = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b');

  static const _totalWords = ['net a payer', 'a payer', 'total ttc', 'ttc', 'total', 'montant total', 'montant du'];
  static const _notTotal = ['sous', 'ss', 'tva', 'ht', 'remise', 'article', 'articles'];
  static const _skipWords = [
    'tva', 'ht', 'espece', 'especes', 'rendu', 'monnaie', 'carte', 'cb', 'visa', 'mastercard', 'cheque',
    'ticket', 'caisse', 'caissier', 'caissiere', 'merci', 'tel', 'fax', 'matricule', 'mf', 'sous total',
    'ss total', 'nb article', 'nombre article', 'nbre article', 'client', 'point', 'points', 'bienvenue',
    'www', 'facture', 'avoir', 'solde', 'paiement', 'regle', 'recu', 'heure', 'date', 'timbre',
  ];

  /// Lit un montant en fin de texte. Renvoie (montant, texte avant), ou null.
  static (ParsedAmount, String, bool negative)? amountAtEnd(String text) {
    final m = _amountAtEnd.firstMatch(text);
    if (m == null) return null;
    final before = text.substring(0, m.start);
    // Montant collé à une lettre (« A1,350 ») : code produit, pas un prix.
    if (RegExp(r'[A-Za-z]$').hasMatch(before) && RegExp(r'^[0-9]').hasMatch(m[0]!)) return null;
    var intPart = m[2]!.replaceAll(' ', '');
    var decPart = m[3]!;
    final raw = intPart + decPart;
    intPart = _fixDigits(intPart);
    decPart = _fixDigits(decPart);
    // Au moins la moitié de vrais chiffres (« SOLDES », « BOO » ne sont pas des prix).
    if (RegExp(r'\d').allMatches(raw).length * 2 < raw.length) return null;
    final corrected = intPart + decPart != raw;
    final value = double.parse('$intPart.$decPart');
    return (ParsedAmount(value, decimals: decPart.length, corrected: corrected), before, m[1] != null);
  }

  /// Montant seul (« 1,350 DT » ou « 1.350 »), ou null.
  static ParsedAmount? parseAmount(String text) {
    final r = amountAtEnd(text.trim());
    if (r == null || r.$2.trim().isNotEmpty) return null;
    return r.$1;
  }

  static String _fixDigits(String s) =>
      s.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[Il]'), '1').replaceAll('S', '5').replaceAll('B', '8');

  static double _num(String s) => double.parse(s.replaceAll(',', '.'));
  static bool _hasWord(String n, String w) => RegExp('(^| )${RegExp.escape(w)}( |\$)').hasMatch(n);
  static bool _hasLetters(String s) => RegExp(r'[a-zA-Zéèàùç]{2,}').hasMatch(s);
  static String _clean(String s) => s
      .replaceAll(RegExp(r'[\s.:*_\-|]+$'), '')
      .replaceAll(RegExp(r'^[\s.:*_\-|]+'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  LiveFrameReading parse(List<LiveOcrRow> rows) {
    final lines = <LiveLine>[];
    final header = <String>[];
    LiveTotal? total;
    DateTime? date;
    LiveOcrRow? pending; // libellé sans prix, en attente d'un prix seul
    var pendingIndex = -1;
    var awaitingTotal = -1; // priorité du « TOTAL » sans montant
    LiveOcrRow? awaitingRow;
    var afterTotal = false;
    var textRows = 0;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final text = row.text.trim();
      if (text.isEmpty) continue;
      textRows++;
      final n = normalize(text);
      date ??= _parseDate(text);

      // Montant du total sur la rangée suivant « TOTAL ».
      if (awaitingTotal >= 0) {
        final a = amountAtEnd(text);
        if (a != null && !_hasLetters(a.$2)) {
          if (total == null || awaitingTotal > total.priority) {
            total = LiveTotal(a.$1.value,
                confidence: _amountConfidence(a.$1) - 0.05,
                box: awaitingRow!.box.expandToInclude(row.box),
                priority: awaitingTotal);
          }
          awaitingTotal = -1;
          continue;
        }
        awaitingTotal = -1;
      }

      final totalIndex = _totalWords.indexWhere((w) => _hasWord(n, w));
      if (totalIndex >= 0 && !_notTotal.any((w) => _hasWord(n, w))) {
        final priority = _totalWords.length - totalIndex;
        final a = amountAtEnd(text);
        if (a != null) {
          if (total == null || priority > total.priority) {
            total = LiveTotal(a.$1.value, confidence: _amountConfidence(a.$1), box: row.box, priority: priority);
          }
          afterTotal = true;
          pending = null;
          continue;
        }
        if (!RegExp(r'\d').hasMatch(text)) {
          awaitingTotal = priority;
          awaitingRow = row;
          afterTotal = true;
          pending = null;
          continue;
        }
      }
      if (afterTotal) continue; // paiement, rendu monnaie…
      if (_skipWords.any((w) => _hasWord(n, w))) {
        pending = null;
        continue;
      }

      // « 2 x 0,900   1,800 » : quantité de la ligne précédente (ou du libellé en attente).
      final q = _qtyRow.firstMatch(text);
      if (q != null && (lines.isNotEmpty || pending != null)) {
        final qty = _num(q[1]!);
        final unit = _num(q[2]!);
        final computed = _round(qty * unit);
        final lineTotal = q[3] != null ? _num(q[3]!) : computed;
        final coherent = (computed - lineTotal).abs() < 0.011;
        if (pending != null) {
          if (lines.isEmpty && header.isNotEmpty) header.removeLast();
          lines.add(LiveLine(
            label: _clean(pending.text),
            quantity: qty,
            price: lineTotal,
            confidence: _clamp(_labelConfidence(_clean(pending.text)) * 0.5 + (coherent ? 0.45 : 0.2) + _ocrBonus(row)),
            box: pending.box.expandToInclude(row.box),
            rowIndex: pendingIndex,
          ));
          pending = null;
        } else {
          final prev = lines.removeLast();
          final pricesAgree = (prev.price - lineTotal).abs() < 0.011;
          lines.add(prev.copyWith(
            quantity: qty,
            price: lineTotal,
            // Le prix de la ligne et le calcul « quantité × prix » se confirment.
            confidence: _clamp(prev.confidence + (coherent && pricesAgree ? 0.15 : -0.1)),
            box: prev.box.expandToInclude(row.box),
          ));
        }
        continue;
      }

      final a = amountAtEnd(text);
      if (a == null) {
        if (_hasLetters(text)) {
          if (lines.isEmpty && header.length < 4) header.add(_clean(text));
          pending = row;
          pendingIndex = i;
        }
        continue;
      }

      var label = _clean(a.$2);
      var box = row.box;
      var index = i;
      var priceOnly = false;
      if (!_hasLetters(label)) {
        // Prix seul : il appartient au libellé lu juste avant.
        if (pending == null) continue;
        if (lines.isEmpty && header.isNotEmpty) header.removeLast();
        label = _clean(pending.text);
        box = pending.box.expandToInclude(row.box);
        index = pendingIndex;
        priceOnly = true;
      }
      pending = null;

      var qty = 1.0;
      var qtyCoherent = false;
      final inline = _inlineQty.firstMatch(label);
      if (inline != null && _hasLetters(inline[1]!)) {
        qty = _num(inline[2]!);
        qtyCoherent = (_round(qty * _num(inline[3]!)) - a.$1.value).abs() < 0.011;
        label = _clean(inline[1]!);
      } else {
        final lead = _leadingQty.firstMatch(label);
        if (lead != null) {
          qty = double.parse(lead[1]!);
          label = _clean(lead[2]!);
        }
      }
      label = _clean(label.replaceFirst(_leadingBarcode, ''));
      if (!_hasLetters(label)) continue;

      final nl = normalize(label);
      final negative = a.$3 || _hasWord(nl, 'remise') || _hasWord(nl, 'reduction');
      final price = negative ? -a.$1.value : a.$1.value;

      var conf = 0.5 * _amountConfidence(a.$1) + 0.35 * _labelConfidence(label) + 0.1;
      if (a.$1.corrected) conf -= 0.25; // chiffre deviné : à vérifier
      if (qtyCoherent) conf += 0.1;
      if (priceOnly) conf -= 0.05;
      if (a.$1.value > 500) conf -= 0.3; // prix d'article improbable
      conf += _ocrBonus(row);
      lines.add(LiveLine(label: label, quantity: qty, price: price, confidence: _clamp(conf), box: box, rowIndex: index));
    }

    return LiveFrameReading(lines: lines, total: total, date: date, headerLines: header, textRows: textRows);
  }

  /// Confiance du montant : 3 décimales (millimes) = format attendu.
  static double _amountConfidence(ParsedAmount a) {
    var c = switch (a.decimals) { 3 => 0.95, 2 => 0.75, _ => 0.5 };
    if (a.corrected) c -= 0.5;
    return _clamp(c);
  }

  /// Confiance du libellé : assez de lettres, peu de caractères parasites.
  static double _labelConfidence(String label) {
    final letters = RegExp(r'[a-zA-ZÀ-ÿ]').allMatches(label).length;
    final odd = RegExp(r'[^a-zA-ZÀ-ÿ0-9 %.,/\x27-]').allMatches(label).length;
    if (letters < 3) return 0.2;
    final ratio = letters / label.replaceAll(' ', '').length;
    var c = 0.4 + 0.6 * ratio - 0.15 * odd;
    if (letters < 4) c -= 0.15;
    return _clamp(c);
  }

  /// La confiance de ML Kit, quand elle existe, nuance le score.
  static double _ocrBonus(LiveOcrRow row) {
    final c = row.confidence;
    if (c == null) return 0;
    return (c - 0.8) * 0.5; // 0,8 = neutre
  }

  static double _clamp(double v) => v.clamp(0.0, 1.0).toDouble();
  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  static DateTime? _parseDate(String row) {
    final m = _date.firstMatch(row);
    if (m == null) return null;
    final d = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 2000 || y > 2100) return null;
    return DateTime(y, mo, d);
  }
}
