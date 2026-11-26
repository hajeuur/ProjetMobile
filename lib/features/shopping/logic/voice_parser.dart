/// Découpage d'une phrase dictée en articles de courses.
///
/// « Ajoute lait, pain et 6 œufs » → Lait · Pain · 6 Œufs.
/// « Mets deux litres de lait et une douzaine d'œufs » → 2 L Lait · 12 Œufs.
///
/// Étapes :
/// 1. minuscules, apostrophes et virgules décimales normalisées (« 1,5 kg ») ;
/// 2. suppression des formules d'introduction (« ajoute », « mets », « je
///    veux », « il me faut »…) et de politesse (« s'il te plaît ») ;
/// 3. découpage aux virgules, points-virgules, « et », « puis », « plus » ;
/// 4. pour chaque morceau : quantité en chiffres ou en lettres (« deux »,
///    « une douzaine », « un demi »), unité éventuelle (kilo, litre, paquet…),
///    puis « de / d' / du / des » et les articles retirés.
library;

class VoiceItem {
  const VoiceItem({required this.label, this.quantity, this.unit});

  final String label;
  final double? quantity;
  final String? unit;

  @override
  String toString() => [if (quantity != null) '$quantity', ?unit, label].join(' ');

  @override
  bool operator ==(Object other) =>
      other is VoiceItem && other.label == label && other.quantity == quantity && other.unit == unit;

  @override
  int get hashCode => Object.hash(label, quantity, unit);
}

class VoiceItemParser {
  const VoiceItemParser();

  static const _numbers = <String, double>{
    'zero': 0, 'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5, 'six': 6, 'sept': 7,
    'huit': 8, 'neuf': 9, 'dix': 10, 'onze': 11, 'douze': 12, 'treize': 13, 'quatorze': 14, 'quinze': 15,
    'seize': 16, 'vingt': 20, 'trente': 30, 'quarante': 40, 'cinquante': 50, 'soixante': 60, 'cent': 100,
  };

  /// Unité dite → unité enregistrée (singulier).
  static const _units = <String, String>{
    'kilo': 'kg', 'kilos': 'kg', 'kilogramme': 'kg', 'kilogrammes': 'kg', 'kg': 'kg',
    'gramme': 'g', 'grammes': 'g', 'g': 'g', 'gr': 'g',
    'litre': 'L', 'litres': 'L', 'l': 'L',
    'centilitre': 'cl', 'centilitres': 'cl', 'cl': 'cl', 'millilitre': 'ml', 'millilitres': 'ml', 'ml': 'ml',
    'paquet': 'paquet', 'paquets': 'paquet', 'bouteille': 'bouteille', 'bouteilles': 'bouteille',
    'boite': 'boîte', 'boites': 'boîte', 'boîte': 'boîte', 'boîtes': 'boîte', 'pot': 'pot', 'pots': 'pot',
    'sachet': 'sachet', 'sachets': 'sachet', 'pack': 'pack', 'packs': 'pack', 'tranche': 'tranche',
    'tranches': 'tranche', 'botte': 'botte', 'bottes': 'botte', 'barquette': 'barquette',
    'barquettes': 'barquette', 'canette': 'canette', 'canettes': 'canette', 'rouleau': 'rouleau',
    'rouleaux': 'rouleau', 'pièce': 'pièce', 'pièces': 'pièce', 'piece': 'pièce', 'pieces': 'pièce',
  };

  static final _intro = RegExp(
    r"^(?:(?:est-ce que|est ce que|tu peux|peux-tu|peux tu|pourrais-tu|pourrais tu|ajoute[rz]?|rajoute[rz]?|"
    r"mets|mettez|mettre|met|note[rz]?|ach[eè]te[rz]?|prends|prend|prendre|il me faut|il nous faut|il faut|"
    r"il manque|j'ai besoin de|on a besoin de|je veux|je voudrais|j'aimerais|il faudrait|n'oublie pas|pense à)"
    r"(?:\s+|$)|(?:j'ai besoin d'|on a besoin d'))+",
  );
  static final _polite = RegExp(r"(?:^|\s)(?:s'il te pla[iî]t|s'il vous pla[iî]t|stp|svp|merci)(?=\s|$|[,.;!])");
  static final _listRef =
      RegExp(r"(?:^|\s)(?:à|a|dans|sur|pour) (?:la|ma|notre) liste(?: de courses)?(?=\s|$|[,.;!])");
  static final _fillers = RegExp(r"(?:^|\s)(?:euh|heu|hum|bon|alors|voilà|voila|ben|bah)(?=\s|$|[,.;!])");
  static final _separators = RegExp(r"\s*(?:,|;|\.(?=\s|$)|!|\bet\b|\bpuis\b|\bplus\b|\bainsi que\b|\baussi\b)\s*");
  static final _digits = RegExp(r'^(\d+(?:\.\d+)?)\s*(kg|g|gr|l|cl|ml)?$');
  static final _leadingArticles =
      RegExp(r"^(?:(?:un peu de|de la|du|des|de|le|la|les|quelques)\s+|(?:un peu d'|de l'|d'|l'))+");
  static final _ofWords = RegExp(r"^(?:(?:de la|du|des|de)\s+|(?:de l'|d'))");

  List<VoiceItem> parse(String sentence) {
    var t = sentence.toLowerCase().replaceAll('’', "'");
    // « 1,5 kg » : virgule décimale, pas un séparateur.
    t = t.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
    t = t
        .replaceAll(_polite, ' ')
        .replaceAll(_listRef, ' ')
        .replaceAll(_fillers, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final out = <VoiceItem>[];
    for (var part in t.split(_separators)) {
      part = part.trim().replaceFirst(_intro, '').trim();
      if (part.isEmpty) continue;
      final item = _parseItem(part);
      if (item != null) out.add(item);
    }
    return out;
  }

  VoiceItem? _parseItem(String part) {
    var words = part.split(' ').where((w) => w.isNotEmpty).toList();
    double? qty;
    String? unit;

    // « une douzaine », « une demi-douzaine », « un demi ».
    if (words.length >= 2 && (words[0] == 'une' || words[0] == 'un')) {
      final w = words[1];
      if (w.startsWith('douzaine')) {
        qty = 12;
        words = words.sublist(2);
      } else if (w.startsWith('demi-douzaine') || (w == 'demi' && words.length > 2 && words[2].startsWith('douzaine'))) {
        qty = 6;
        words = words.sublist(w == 'demi' ? 3 : 2);
      } else if (w == 'demi' || w == 'demie') {
        qty = 0.5;
        words = words.sublist(2);
      } else if (w == 'peu') {
        words = words.sublist(2); // « un peu de sel » : pas de quantité
      }
    } else if (words.isNotEmpty && (words[0].startsWith('douzaine') || words[0] == 'demi-douzaine')) {
      qty = words[0] == 'demi-douzaine' ? 6 : 12;
      words = words.sublist(1);
    }

    // Quantité en chiffres (« 6 », « 1.5 », « 2kg »).
    if (qty == null && words.isNotEmpty) {
      final m = _digits.firstMatch(words[0]);
      if (m != null) {
        qty = double.parse(m[1]!);
        if (m[2] != null) unit = _units[m[2]!];
        words = words.sublist(1);
      }
    }

    // Quantité en lettres (« deux », « vingt-quatre », « trois cents »).
    if (qty == null && words.isNotEmpty) {
      final n = _wordNumber(words[0]);
      // « un » / « une » seul devant un nom compte pour 1 (« une baguette »).
      if (n != null && words.length > 1) {
        qty = n;
        words = words.sublist(1);
      }
    }

    // « deux douzaines d'œufs ».
    if (words.length > 1 && words[0].startsWith('douzaine')) {
      qty = (qty ?? 1) * 12;
      words = words.sublist(1);
    }

    // Unité (« deux litres de lait », « un paquet de pâtes »).
    if (unit == null && words.length > 1) {
      final u = _units[words[0]];
      if (u != null) {
        unit = u;
        words = words.sublist(1);
      }
    }

    var label = words.join(' ');
    label = label.replaceFirst(_ofWords, '').replaceFirst(_leadingArticles, '').trim();
    if (label.isEmpty || !RegExp(r'[a-zà-ÿœ]').hasMatch(label)) return null;
    // Un nombre seul (« et deux ») n'est pas un article.
    if (_wordNumber(label) != null) return null;
    // Quantité seule sans unité ni nom (« et deux ») : rien à ajouter.
    if (qty == 0) qty = null;
    return VoiceItem(label: _capitalize(label), quantity: qty, unit: _plural(unit, qty));
  }

  static double? _wordNumber(String w) {
    final direct = _numbers[w];
    if (direct != null) return direct;
    // « vingt-quatre », « dix-huit », « soixante-dix ».
    if (w.contains('-')) {
      var sum = 0.0;
      for (final p in w.split('-')) {
        if (p == 'et') continue;
        final v = _numbers[p];
        if (v == null) return null;
        sum += v;
      }
      return sum;
    }
    return null;
  }

  static String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

  /// Unités comptables au pluriel quand il y en a plusieurs (« 2 paquets »).
  static String? _plural(String? unit, double? qty) {
    if (unit == null || qty == null || qty <= 1) return unit;
    if (const {'kg', 'g', 'L', 'cl', 'ml'}.contains(unit)) return unit;
    return unit.endsWith('eau') ? '${unit}x' : '${unit}s';
  }
}

/// Unité comparable : « paquets » = « paquet », « l » = « L ».
String unitKey(String? unit) {
  if (unit == null || unit.isEmpty) return '';
  var u = unit.toLowerCase();
  if (u.endsWith('x') && u.length > 3) u = u.substring(0, u.length - 1);
  if (u.endsWith('s') && u.length > 3) u = u.substring(0, u.length - 1);
  return u;
}

/// Nouvelle quantité si l'on ajoute ([quantity], [unit]) à un article qui a
/// déjà ([existingQty], [existingUnit]). Sans quantité dite, on ajoute une
/// unité. Renvoie null si les unités sont incompatibles (1 kg + 3 pièces).
({double? quantity, String? unit})? mergedQuantity(
  double? existingQty,
  String? existingUnit,
  double? quantity,
  String? unit,
) {
  if (existingQty == null) return (quantity: quantity, unit: unit ?? existingUnit);
  if (quantity == null) return (quantity: existingQty + 1, unit: existingUnit);
  if (unitKey(existingUnit) == unitKey(unit)) return (quantity: existingQty + quantity, unit: existingUnit ?? unit);
  return null;
}
