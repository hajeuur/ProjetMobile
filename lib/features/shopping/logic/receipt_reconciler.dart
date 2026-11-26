/// Rapprochement automatique ticket ↔ liste de courses.
///
/// 1. **Normalisation** ([significantTokens]) : minuscules, sans accents,
///    contenances et mots vides retirés, abréviations de caisse développées
///    (« LAIT DEMI ECR 1L » → lait · demi · ecreme).
/// 2. **Similarité de deux mots** ([wordScore]) : identiques = 1 ; abréviation
///    par préfixe (« yaou » / « yaourt ») = 0,9 ; sinon le meilleur de
///    Jaro-Winkler (bon pour les débuts de mots identiques) et de Levenshtein
///    (bon pour une lettre mal lue : « frmage » / « fromage »).
/// 3. **Score article ↔ ligne** ([labelScore]) : part des mots de l'article
///    retrouvés dans la ligne (75 %), part des mots de la ligne retrouvés dans
///    l'article (15 %), premier mot identique (10 %).
/// 4. **Décision** : même produit (gestion 2) ou correction déjà faite par
///    l'utilisateur = sûr ; score ≥ [sureMatchScore] = coché tout seul ;
///    entre [askMatchScore] et [sureMatchScore] = on demande « oui / non » ;
///    en dessous = pas de rapprochement.
/// 5. **Affectation** : du couple le plus sûr au moins sûr, chaque article et
///    chaque ligne ne servant qu'une fois (« LAIT » va à « LAIT DELICE »
///    plutôt qu'à « CHOCOLAT AU LAIT »).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'receipt_matcher.dart' show LineCandidate, MatchCandidate;
import 'text_similarity.dart';

export 'receipt_matcher.dart' show LineCandidate, MatchCandidate;

/// Au-dessus : l'article est coché sans rien demander. Constante réglable.
const sureMatchScore = 0.75;

/// Entre ce seuil et [sureMatchScore] : rapprochement proposé, à confirmer.
const askMatchScore = 0.5;

// ------------------------------------------------------------ Distances

/// Distance d'édition (insertions, suppressions, substitutions).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 1 − distance / longueur du plus long (0 à 1).
double levenshteinRatio(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  return 1 - levenshtein(a, b) / math.max(a.length, b.length);
}

/// Similarité de Jaro-Winkler (0 à 1) : favorise les mots qui commencent
/// pareil, fréquent avec les libellés tronqués des tickets.
double jaroWinkler(String a, String b, {double prefixScale = 0.1}) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final window = math.max(0, math.max(a.length, b.length) ~/ 2 - 1);
  final aFlags = List<bool>.filled(a.length, false);
  final bFlags = List<bool>.filled(b.length, false);
  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final from = math.max(0, i - window);
    final to = math.min(b.length - 1, i + window);
    for (var j = from; j <= to; j++) {
      if (bFlags[j] || a.codeUnitAt(i) != b.codeUnitAt(j)) continue;
      aFlags[i] = bFlags[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;
  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!aFlags[i]) continue;
    while (!bFlags[k]) {
      k++;
    }
    if (a.codeUnitAt(i) != b.codeUnitAt(k)) transpositions++;
    k++;
  }
  final m = matches.toDouble();
  final jaro = (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
  var prefix = 0;
  while (prefix < math.min(4, math.min(a.length, b.length)) && a[prefix] == b[prefix]) {
    prefix++;
  }
  return jaro + prefix * prefixScale * (1 - jaro);
}

/// Ressemblance de deux mots normalisés (0 à 1).
double wordScore(String a, String b) {
  if (a == b) return 1;
  final short = a.length <= b.length ? a : b;
  final long = a.length <= b.length ? b : a;
  if (short.length >= 3 && long.startsWith(short)) return 0.9; // abréviation
  if (short.length < 3) return 0;
  final jw = jaroWinkler(a, b);
  final lev = levenshteinRatio(a, b);
  // Seuils hauts : « lait » et « laid » ne doivent pas se confondre.
  final best = math.max(jw >= 0.9 ? jw : 0.0, lev >= 0.8 ? lev : 0.0);
  return best;
}

double _coverage(List<String> query, List<String> target) {
  if (query.isEmpty || target.isEmpty) return 0;
  var sum = 0.0;
  for (final q in query) {
    var best = 0.0;
    for (final t in target) {
      best = math.max(best, wordScore(q, t));
      if (best == 1) break;
    }
    sum += best;
  }
  return sum / query.length;
}

/// Score d'un article de liste face à une ligne de ticket (0 à 1).
double labelScore(String itemLabel, String receiptLabel) {
  final a = significantTokens(itemLabel);
  final b = significantTokens(receiptLabel);
  if (a.isEmpty || b.isEmpty) return 0;
  final forward = _coverage(a, b);
  if (forward == 0) return 0;
  final backward = _coverage(b, a);
  final first = wordScore(a.first, b.first) > 0 ? 1.0 : 0.0;
  return (0.75 * forward + 0.15 * backward + 0.10 * first).clamp(0.0, 1.0);
}

// ------------------------------------------------- Mémoire des corrections

/// Historique des réponses de l'utilisateur (« oui, “JUS POMME” c'est bien
/// mon “jus” » / « non »). Une paire déjà tranchée n'est plus jamais
/// redemandée : oui → sûr, non → jamais rapprochée.
class CorrectionMemory {
  CorrectionMemory([Map<String, bool>? answers]) : _answers = answers ?? {};

  /// Nombre maximum de corrections gardées (les plus anciennes partent).
  static const maxEntries = 300;

  final Map<String, bool> _answers;

  static String keyOf(String itemLabel, String lineLabel) => '${labelKey(lineLabel)}|${labelKey(itemLabel)}';

  /// true = confirmé, false = refusé, null = jamais demandé.
  bool? answerFor(String itemLabel, String lineLabel) => _answers[keyOf(itemLabel, lineLabel)];

  void record(String itemLabel, String lineLabel, bool accepted) {
    final key = keyOf(itemLabel, lineLabel);
    _answers.remove(key); // la plus récente en dernier
    _answers[key] = accepted;
    while (_answers.length > maxEntries) {
      _answers.remove(_answers.keys.first);
    }
  }

  int get length => _answers.length;

  String toJson() => jsonEncode(_answers);

  static CorrectionMemory fromJson(String? json) {
    if (json == null || json.isEmpty) return CorrectionMemory();
    try {
      return CorrectionMemory((jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as bool)));
    } catch (_) {
      return CorrectionMemory();
    }
  }
}

// ------------------------------------------------------------- Résultat

enum MatchReason {
  /// Même produit (gestion 2).
  sameProduct,

  /// L'utilisateur a déjà confirmé cette paire.
  learned,

  /// Ressemblance des libellés.
  label,
}

class ProposedMatch {
  const ProposedMatch({required this.item, required this.line, required this.score, required this.reason});

  final MatchCandidate item;
  final LineCandidate line;
  final double score;
  final MatchReason reason;

  @override
  String toString() => '${item.label} ↔ ${line.label} (${score.toStringAsFixed(2)})';
}

class Reconciliation {
  const Reconciliation({
    required this.sure,
    required this.uncertain,
    required this.forgotten,
    required this.unplanned,
  });

  /// Rapprochements sûrs : les articles se cochent seuls.
  final List<ProposedMatch> sure;

  /// Rapprochements possibles : à confirmer par oui / non.
  final List<ProposedMatch> uncertain;

  /// Articles non cochés de la liste, absents du ticket.
  final List<MatchCandidate> forgotten;

  /// Lignes du ticket sans article dans la liste (achats hors liste).
  final List<LineCandidate> unplanned;
}

class ReceiptReconciler {
  const ReceiptReconciler({
    this.sureThreshold = sureMatchScore,
    this.askThreshold = askMatchScore,
    this.memory,
  }) : assert(askThreshold <= sureThreshold);

  final double sureThreshold;
  final double askThreshold;
  final CorrectionMemory? memory;

  /// Score d'une paire et sa raison.
  (double, MatchReason) score(MatchCandidate item, LineCandidate line) {
    if (item.productId != null && item.productId == line.productId) return (1, MatchReason.sameProduct);
    final answer = memory?.answerFor(item.label, line.label);
    if (answer == true) return (1, MatchReason.learned);
    if (answer == false) return (0, MatchReason.learned);
    return (labelScore(item.label, line.label), MatchReason.label);
  }

  Reconciliation reconcile(List<MatchCandidate> items, List<LineCandidate> lines) {
    final pairs = <ProposedMatch>[];
    for (final item in items) {
      for (final line in lines) {
        final (s, reason) = score(item, line);
        if (s >= askThreshold) pairs.add(ProposedMatch(item: item, line: line, score: s, reason: reason));
      }
    }
    // Du plus sûr au moins sûr ; à égalité, l'ordre de la liste puis du ticket.
    final itemOrder = {for (var i = 0; i < items.length; i++) items[i].id: i};
    pairs.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final i = itemOrder[a.item.id]!.compareTo(itemOrder[b.item.id]!);
      return i != 0 ? i : a.line.index.compareTo(b.line.index);
    });

    final usedItems = <int>{};
    final usedLines = <int>{};
    final sure = <ProposedMatch>[];
    final uncertain = <ProposedMatch>[];
    for (final p in pairs) {
      if (usedItems.contains(p.item.id) || usedLines.contains(p.line.index)) continue;
      usedItems.add(p.item.id);
      usedLines.add(p.line.index);
      (p.score >= sureThreshold ? sure : uncertain).add(p);
    }

    return Reconciliation(
      sure: sure,
      uncertain: uncertain,
      forgotten: [
        for (final i in items)
          if (!i.checked && !usedItems.contains(i.id)) i,
      ],
      unplanned: [
        for (final l in lines)
          if (!usedLines.contains(l.index)) l,
      ],
    );
  }
}
