import 'text_similarity.dart';

/// Catégories de dépenses, qui servent aussi de rayons par défaut pour trier
/// une liste quand le magasin n'a pas défini les siens (gestion 4).
const kCategories = [
  'Fruits et légumes',
  'Boulangerie',
  'Viandes et poissons',
  'Produits laitiers',
  'Épicerie salée',
  'Épicerie sucrée',
  'Boissons',
  'Surgelés',
  'Hygiène et entretien',
  'Autre',
];

const _keywords = <String, List<String>>{
  'Fruits et légumes': [
    'tomate', 'pomme', 'banane', 'orange', 'citron', 'oignon', 'ail', 'carotte', 'poivron', 'piment',
    'salade', 'laitue', 'courgette', 'aubergine', 'concombre', 'persil', 'coriandre', 'menthe', 'fraise',
    'raisin', 'datte', 'poire', 'peche', 'melon', 'pasteque', 'epinard', 'champignon', 'legume', 'fruit',
    'clementine', 'mandarine', 'kiwi', 'navet', 'fenouil', 'artichaut', 'haricot vert', 'petit pois',
  ],
  'Boulangerie': ['pain', 'baguette', 'croissant', 'brioche', 'tabouna', 'mie', 'viennoiserie', 'biscotte'],
  'Viandes et poissons': [
    'poulet', 'dinde', 'viande', 'boeuf', 'veau', 'agneau', 'mouton', 'merguez', 'escalope', 'hache',
    'poisson', 'thon', 'sardine', 'crevette', 'calamar', 'saumon', 'dorade', 'loup', 'jambon', 'salami',
    'cachir', 'charcuterie', 'oeuf',
  ],
  'Produits laitiers': [
    'lait', 'yaourt', 'fromage', 'beurre', 'creme', 'lben', 'rayeb', 'ricotta', 'mozzarella', 'emmental',
    'gruyere', 'danone', 'vitalait', 'delice', 'jben',
  ],
  'Épicerie salée': [
    'pate', 'spaghetti', 'macaroni', 'riz', 'semoule', 'couscous', 'farine', 'huile', 'olive', 'harissa',
    'concentre', 'sel', 'poivre', 'epice', 'cumin', 'lentille', 'pois chiche', 'conserve', 'mayonnaise',
    'ketchup', 'moutarde', 'vinaigre', 'sauce', 'bouillon', 'chips', 'olive', 'mais', 'thon',
  ],
  'Épicerie sucrée': [
    'sucre', 'cafe', 'the', 'chocolat', 'biscuit', 'gateau', 'confiture', 'miel', 'nutella', 'cereale',
    'bonbon', 'halwa', 'gaufrette', 'chamia', 'pate a tartiner', 'madeleine',
  ],
  'Boissons': ['eau', 'jus', 'soda', 'coca', 'boisson', 'limonade', 'sirop', 'boga', 'fanta', 'minerale'],
  'Surgelés': ['surgele', 'glace', 'congele', 'frite', 'pizza'],
  'Hygiène et entretien': [
    'savon', 'shampooing', 'dentifrice', 'brosse', 'lessive', 'detergent', 'javel', 'papier', 'mouchoir',
    'couche', 'gel', 'deodorant', 'eponge', 'sac poubelle', 'liquide vaisselle', 'hygienique', 'adoucissant',
  ],
};

/// Devine la catégorie d'un libellé (« Autre » si rien ne correspond).
String guessCategory(String label) {
  final tokens = significantTokens(label);
  if (tokens.isEmpty) return 'Autre';
  final text = ' ${tokens.join(' ')} ';
  String? best;
  var bestPos = 1 << 30;
  // Le mot clé qui apparaît le plus tôt l'emporte : « CHOCOLAT AU LAIT » est
  // de l'épicerie sucrée, « LAIT CHOCOLATE » un produit laitier.
  for (final entry in _keywords.entries) {
    for (final k in entry.value) {
      final kw = significantTokens(k).join(' ');
      if (kw.isEmpty) continue;
      var pos = text.indexOf(' $kw ');
      if (pos < 0) {
        // Préfixe (« yaou » déjà développé, « tomat »…).
        final m = RegExp(' ${RegExp.escape(kw)}[a-z]*').firstMatch(text);
        pos = m?.start ?? -1;
      }
      if (pos >= 0 && pos < bestPos) {
        bestPos = pos;
        best = entry.key;
      }
    }
  }
  return best ?? 'Autre';
}
