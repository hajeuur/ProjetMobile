import '../integration/gateways.dart';
import '../models/recipe.dart';
import 'text_matching.dart';

/// Résultat du contrôle d'une recette contre le profil commun du foyer.
class DietaryVerdict {
  const DietaryVerdict(this.reasons);
  final List<String> reasons;
  bool get allowed => reasons.isEmpty;
}

/// Mots-clés (français et anglais, car TheMealDB est en anglais) par allergie.
const Map<String, List<String>> allergenKeywords = {
  'arachide': ['arachide', 'cacahuete', 'peanut'],
  'gluten': _gluten,
  'lait': ['lait', 'milk', 'beurre', 'butter', 'creme', 'cream', 'fromage', 'cheese', 'cheddar', 'parmesan', 'mozzarella', 'feta', 'yaourt', 'yogurt', 'yoghurt', 'ricotta', 'mascarpone'],
  'lactose': ['lait', 'milk', 'beurre', 'butter', 'creme', 'cream', 'fromage', 'cheese', 'yaourt', 'yogurt'],
  'oeuf': ['oeuf', 'egg', 'mayonnaise'],
  'poisson': ['poisson', 'fish', 'thon', 'tuna', 'saumon', 'salmon', 'sardine', 'anchois', 'anchovy', 'cod', 'cabillaud', 'merlu'],
  'fruits a coque': _nuts,
  'noix': _nuts,
  'soja': ['soja', 'soy', 'soya', 'tofu'],
  'crustace': ['crevette', 'shrimp', 'prawn', 'crabe', 'crab', 'homard', 'lobster', 'langouste'],
  'sesame': ['sesame', 'tahini', 'tahina'],
  'moutarde': ['moutarde', 'mustard'],
  'celeri': ['celeri', 'celery'],
};

const _gluten = ['farine', 'flour', 'ble', 'wheat', 'pates', 'pasta', 'spaghetti', 'macaroni', 'noodle', 'pain', 'bread', 'breadcrumb', 'chapelure', 'semoule', 'couscous', 'orge', 'barley', 'seigle', 'rye', 'biscuit', 'malsouka', 'brick', 'lasagne', 'lasagna', 'tortilla', 'baguette'];
const _nuts = ['noix', 'walnut', 'amande', 'almond', 'noisette', 'hazelnut', 'pistache', 'pistachio', 'cajou', 'cashew', 'pecan', 'nut'];

const _meat = ['viande', 'meat', 'boeuf', 'beef', 'poulet', 'chicken', 'porc', 'pork', 'agneau', 'lamb', 'mouton', 'mutton', 'veau', 'veal', 'dinde', 'turkey', 'canard', 'duck', 'bacon', 'jambon', 'ham', 'saucisse', 'sausage', 'merguez', 'chorizo', 'steak', 'mince', 'hache', 'gelatine', 'gelatin', 'lardon', 'pancetta', 'prosciutto', 'salami', 'kefta'];
const _seafood = ['poisson', 'fish', 'thon', 'tuna', 'saumon', 'salmon', 'sardine', 'anchois', 'anchovy', 'crevette', 'shrimp', 'prawn', 'crabe', 'crab', 'calamar', 'squid', 'moule', 'mussel', 'cod'];

/// Ingrédients interdits par régime. Clés normalisées.
const Map<String, List<String>> dietForbidden = {
  'halal': ['porc', 'pork', 'bacon', 'jambon', 'ham', 'lard', 'lardon', 'pancetta', 'prosciutto', 'chorizo', 'salami', 'gelatine', 'gelatin', 'vin', 'wine', 'biere', 'beer', 'rhum', 'rum', 'brandy', 'cognac', 'sherry', 'xeres', 'whisky', 'vodka', 'alcool'],
  'vegetarien': [..._meat, ..._seafood],
  'vegan': [..._meat, ..._seafood, 'lait', 'milk', 'beurre', 'butter', 'creme', 'cream', 'fromage', 'cheese', 'oeuf', 'egg', 'miel', 'honey', 'yaourt', 'yogurt'],
  'sans gluten': _gluten,
  'sans lactose': ['lait', 'milk', 'beurre', 'butter', 'creme', 'cream', 'fromage', 'cheese', 'yaourt', 'yogurt'],
  'pescetarien': _meat,
};

/// Synonymes de régimes, normalisés.
const _dietAliases = {
  'vegetarian': 'vegetarien',
  'vegetarienne': 'vegetarien',
  'gluten free': 'sans gluten',
  'lactose free': 'sans lactose',
  'pescatarian': 'pescetarien',
  'vegetalien': 'vegan',
};

const _allergyAliases = {
  'arachides': 'arachide',
  'cacahuete': 'arachide',
  'cacahuetes': 'arachide',
  'peanut': 'arachide',
  'peanuts': 'arachide',
  'oeufs': 'oeuf',
  'egg': 'oeuf',
  'eggs': 'oeuf',
  'milk': 'lait',
  'produits laitiers': 'lait',
  'fish': 'poisson',
  'crustaces': 'crustace',
  'fruit a coque': 'fruits a coque',
  'nuts': 'fruits a coque',
};

class DietaryChecker {
  const DietaryChecker();

  DietaryVerdict check(Recipe recipe, HouseholdProfile profile) {
    final texts = [
      for (final i in recipe.ingredients) normalize(i.name),
      normalize(recipe.title),
    ];
    final reasons = <String>[];

    for (final allergy in profile.allergies) {
      final key = _allergyAliases[normalize(allergy)] ?? normalize(allergy);
      final keywords = allergenKeywords[key] ?? [key];
      final hit = _firstHit(texts, keywords);
      if (hit != null) reasons.add('Allergie « $allergy » : $hit');
    }

    for (final diet in profile.diets) {
      final key = _dietAliases[normalize(diet)] ?? normalize(diet);
      final forbidden = dietForbidden[key];
      if (forbidden == null) continue;
      final hit = _firstHit(texts, forbidden);
      if (hit != null) reasons.add('Régime « $diet » : $hit');
    }
    return DietaryVerdict(reasons);
  }

  String? _firstHit(List<String> texts, List<String> keywords) {
    for (final t in texts) {
      for (final k in keywords) {
        if (containsWord(t, k)) return k;
      }
    }
    return null;
  }
}
