/// Similarité entre un libellé de liste (« Lait ») et un libellé de ticket
/// (« LAIT DELICE DEMI-ECR 1L »).
///
/// Les tickets sont en majuscules, abrégés et bourrés de marques et de
/// contenances : on normalise, on retire les mots vides et les quantités,
/// on développe les abréviations courantes, puis on compare mot à mot en
/// acceptant les préfixes (« YAOU » ≈ « yaourt ») et les fautes de lecture
/// (trigrammes).
library;

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules, sans accents, ponctuation remplacée par des espaces.
String normalize(String input) {
  final b = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final c = String.fromCharCode(rune);
    b.write(_accents[c] ?? c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _stopWords = {
  'de', 'du', 'des', 'la', 'le', 'les', 'l', 'd', 'au', 'aux', 'et', 'a', 'en', 'un', 'une',
  'x', 'pc', 'pcs', 'piece', 'kg', 'g', 'gr', 'lt', 'ml', 'cl', 'dl', 'boite', 'bte', 'pqt', 'paquet',
  'sachet', 'sac', 'bt', 'btl', 'bouteille', 'pot', 'lot', 'promo', 'pack',
};

/// Abréviations fréquentes sur les tickets tunisiens et français.
const _abbreviations = {
  'yaou': 'yaourt', 'yt': 'yaourt', 'yog': 'yaourt', 'yogourt': 'yaourt',
  'from': 'fromage', 'frmg': 'fromage', 'fro': 'fromage',
  'ecr': 'ecreme', 'dem': 'demi',
  'tom': 'tomate', 'conc': 'concentre', 'dbl': 'double',
  'pdt': 'pomme', 'pdter': 'pomme',
  'hle': 'huile', 'hui': 'huile', 'hl': 'huile', 'ol': 'olive',
  'choc': 'chocolat', 'bisc': 'biscuit',
  'poul': 'poulet', 'vde': 'viande', 'bf': 'boeuf',
  'spag': 'spaghetti', 'spagh': 'spaghetti', 'mac': 'macaroni',
  'sem': 'semoule', 'suc': 'sucre', 'caf': 'cafe',
  'oeu': 'oeuf', 'eau min': 'eau', 'min': 'minerale',
  'sav': 'savon', 'deterg': 'detergent', 'lessiv': 'lessive',
  'pap': 'papier', 'hyg': 'hygienique',
  'baguet': 'baguette', 'bag': 'baguette',
};

String _singular(String w) {
  if (w.length > 4 && w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (w.length > 3 && (w.endsWith('s') || w.endsWith('x'))) return w.substring(0, w.length - 1);
  return w;
}

/// Mots significatifs d'un libellé, dans l'ordre.
List<String> significantTokens(String label) {
  final out = <String>[];
  for (final raw in normalize(label).split(' ')) {
    if (raw.isEmpty) continue;
    // Contenances et nombres : « 1l », « 500g », « 4x125g », « 2 ».
    if (RegExp(r'\d').hasMatch(raw)) continue;
    if (_stopWords.contains(raw)) continue;
    final w = _singular(_abbreviations[raw] ?? raw);
    if (w.length < 2) continue;
    out.add(w);
  }
  return out;
}

Set<String> _trigrams(String s) {
  final p = '  $s ';
  return {for (var i = 0; i < p.length - 2; i++) p.substring(i, i + 3)};
}

/// Coefficient de Dice sur les trigrammes de caractères, entre 0 et 1.
double trigramSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final ta = _trigrams(a);
  final tb = _trigrams(b);
  final common = ta.intersection(tb).length;
  return 2 * common / (ta.length + tb.length);
}

/// Ressemblance de deux mots déjà normalisés.
double wordSimilarity(String a, String b) {
  if (a == b) return 1;
  final short = a.length <= b.length ? a : b;
  final long = a.length <= b.length ? b : a;
  // Abréviation par préfixe : « yaou » / « yaourt », « tomat » / « tomate ».
  if (short.length >= 3 && long.startsWith(short)) return 0.9;
  final t = trigramSimilarity(a, b);
  return t >= 0.6 ? t : 0;
}

/// Part des mots de [query] retrouvés dans [target] (0 à 1).
double coverage(List<String> query, List<String> target) {
  if (query.isEmpty || target.isEmpty) return 0;
  var sum = 0.0;
  for (final q in query) {
    var best = 0.0;
    for (final t in target) {
      final s = wordSimilarity(q, t);
      if (s > best) best = s;
      if (best == 1) break;
    }
    sum += best;
  }
  return sum / query.length;
}

/// Similarité d'un article de liste avec une ligne de ticket, entre 0 et 1.
///
/// Asymétrique : ce qui compte, c'est de retrouver les mots de l'article dans
/// la ligne (la ligne contient en plus la marque et la contenance). Un léger
/// bonus quand le premier mot correspond départage « lait » entre « LAIT
/// DELICE » et « CHOCOLAT AU LAIT ».
double labelSimilarity(String itemLabel, String receiptLabel) {
  final a = significantTokens(itemLabel);
  final b = significantTokens(receiptLabel);
  if (a.isEmpty || b.isEmpty) return 0;
  final forward = coverage(a, b);
  if (forward == 0) return 0;
  final backward = coverage(b, a);
  final first = wordSimilarity(a.first, b.first) > 0 ? 1.0 : 0.0;
  return (0.75 * forward + 0.15 * backward + 0.10 * first).clamp(0, 1).toDouble();
}

/// Clé stable d'un produit à partir de son libellé (pour l'historique des prix
/// quand aucun produit n'est rapproché).
String labelKey(String label) {
  final t = significantTokens(label);
  return t.isEmpty ? normalize(label) : t.join(' ');
}

/// Libellé de ticket lisible : « HUILE OLIVE 1L » → « Huile olive 1L ».
String displayLabel(String label) {
  final t = label.trim().toLowerCase();
  if (t.isEmpty) return label;
  return t[0].toUpperCase() + t.substring(1).replaceAllMapped(RegExp(r'(\d)l\b'), (m) => '${m[1]}L');
}
