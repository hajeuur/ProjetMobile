/// Outils de comparaison de libellés (français / anglais, accents, pluriels).
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
  final lower = input.toLowerCase();
  final b = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    b.write(_accents[c] ?? c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Traductions courantes pour rapprocher les ingrédients TheMealDB (anglais)
/// du stock (souvent saisi en français). Clés et valeurs normalisées.
const Map<String, String> _frToEn = {
  'tomate': 'tomato',
  'oeuf': 'egg',
  'oignon': 'onion',
  'poulet': 'chicken',
  'riz': 'rice',
  'lait': 'milk',
  'pomme de terre': 'potato',
  'ail': 'garlic',
  'farine': 'flour',
  'beurre': 'butter',
  'fromage': 'cheese',
  'carotte': 'carrot',
  'poivron': 'pepper',
  'citron': 'lemon',
  'huile d olive': 'olive oil',
  'sel': 'salt',
  'sucre': 'sugar',
  'boeuf': 'beef',
  'agneau': 'lamb',
  'poisson': 'fish',
  'thon': 'tuna',
  'pates': 'pasta',
  'pois chiche': 'chickpea',
  'semoule': 'couscous',
  'creme': 'cream',
  'champignon': 'mushroom',
  'epinard': 'spinach',
  'courgette': 'zucchini',
  'aubergine': 'eggplant',
  'persil': 'parsley',
  'coriandre': 'coriander',
  'cumin': 'cumin',
  'pain': 'bread',
  'yaourt': 'yogurt',
  'lentille': 'lentil',
  'haricot': 'bean',
  'concentre de tomate': 'tomato puree',
};

String _singular(String word) {
  // Pluriels anglais en -oes (tomatoes, potatoes).
  if (word.length > 4 && word.endsWith('oes')) return word.substring(0, word.length - 2);
  if (word.length > 3 && (word.endsWith('s') || word.endsWith('x'))) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// Forme canonique : normalisée, au singulier, traduite en anglais si connue.
String canonicalIngredient(String name) {
  final n = normalize(name).split(' ').map(_singular).join(' ');
  return _frToEn[n] ?? n;
}

/// Vrai si deux libellés désignent vraisemblablement le même ingrédient.
/// « Tomates cerises » correspond à « tomate », « Chicken breast » à « poulet ».
bool sameIngredient(String a, String b) {
  final ca = canonicalIngredient(a);
  final cb = canonicalIngredient(b);
  if (ca.isEmpty || cb.isEmpty) return false;
  if (ca == cb) return true;
  final wa = ca.split(' ').toSet();
  final wb = cb.split(' ').toSet();
  // L'un est contenu mot pour mot dans l'autre (« chicken » ⊂ « chicken breast »).
  if (wa.length <= wb.length ? wb.containsAll(wa) : wa.containsAll(wb)) {
    return true;
  }
  // Mot à mot avec traduction (« tomates cerises » -> « tomato cerise »).
  final ta = wa.map((w) => _frToEn[w] ?? w).toSet();
  final tb = wb.map((w) => _frToEn[w] ?? w).toSet();
  return ta.length <= tb.length ? tb.containsAll(ta) : ta.containsAll(tb);
}

/// Recherche d'un mot entier (avec pluriel facultatif) dans un texte normalisé.
bool containsWord(String normalizedText, String keyword) {
  final k = RegExp.escape(normalize(keyword));
  return RegExp('(^| )${k}s?( |\$)').hasMatch(normalizedText);
}
