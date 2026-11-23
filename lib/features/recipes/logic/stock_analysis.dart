import '../integration/gateways.dart';
import '../models/recipe.dart';
import 'text_matching.dart';
import 'units.dart';

/// Nombre de jours sous lequel un produit est considéré « bientôt périmé ».
const expiringSoonDays = 3;

enum IngredientAvailability { missing, inStock, expiringSoon }

class IngredientStatus {
  const IngredientStatus(this.ingredient, this.availability, this.matches);
  final RecipeIngredient ingredient;
  final IngredientAvailability availability;
  final List<StockSnapshot> matches;
}

/// Lignes de stock utilisables (non périmées) correspondant à l'ingrédient.
List<StockSnapshot> matchingStock(RecipeIngredient ing, List<StockSnapshot> stock, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return stock.where((s) {
    if (s.quantity <= 0) return false;
    if (s.expiryDate != null && s.expiryDate!.isBefore(today)) return false;
    if (ing.productId != null && s.productId != null) return ing.productId == s.productId;
    return sameIngredient(ing.name, s.name);
  }).toList();
}

bool isExpiringSoon(StockSnapshot s, DateTime now) {
  if (s.expiryDate == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  final days = s.expiryDate!.difference(today).inDays;
  return days >= 0 && days <= expiringSoonDays;
}

IngredientStatus ingredientStatus(RecipeIngredient ing, List<StockSnapshot> stock, DateTime now) {
  final m = matchingStock(ing, stock, now);
  if (m.isEmpty) return IngredientStatus(ing, IngredientAvailability.missing, m);
  final expiring = m.any((s) => isExpiringSoon(s, now));
  return IngredientStatus(
    ing,
    expiring ? IngredientAvailability.expiringSoon : IngredientAvailability.inStock,
    m,
  );
}

class AntiGaspiScore {
  const AntiGaspiScore({required this.score, required this.inStock, required this.expiringSoon, required this.total});

  /// De 0 à 100.
  final double score;
  final int inStock;
  final int expiringSoon;
  final int total;
}

/// Score anti-gaspi : part des ingrédients déjà en stock, avec un poids double
/// pour ceux qui périment dans les [expiringSoonDays] jours.
///
/// score = 100 × (en stock + bientôt périmés) / (total + bientôt périmés)
///
/// Une recette dont tous les ingrédients sont en stock et périment bientôt
/// obtient 100 ; tous en stock mais aucun urgent : 50 à 100 selon le cas ; rien
/// en stock : 0. [claimedStock] contient les noms de lignes déjà « réservées »
/// par une autre recette du menu : elles comptent comme en stock mais plus comme
/// urgentes, pour ne pas privilégier deux fois le même produit.
AntiGaspiScore antiGaspiScore(
  List<RecipeIngredient> ingredients,
  List<StockSnapshot> stock,
  DateTime now, {
  Set<String> claimedStock = const {},
}) {
  var inStock = 0;
  var expiring = 0;
  for (final ing in ingredients) {
    final m = matchingStock(ing, stock, now);
    if (m.isEmpty) continue;
    inStock++;
    if (m.any((s) => isExpiringSoon(s, now) && !claimedStock.contains(s.name))) {
      expiring++;
    }
  }
  final total = ingredients.length;
  final score = total == 0 ? 0.0 : 100.0 * (inStock + expiring) / (total + expiring);
  return AntiGaspiScore(score: score, inStock: inStock, expiringSoon: expiring, total: total);
}

/// Ingrédient manquant (ou en quantité insuffisante) pour une recette.
class MissingIngredient {
  const MissingIngredient(this.ingredient, this.missingQuantity);
  final RecipeIngredient ingredient;

  /// Quantité à acheter, dans l'unité de l'ingrédient. Null si non chiffrée.
  final double? missingQuantity;

  ShoppingRequest toShoppingRequest() => ShoppingRequest(
        label: ingredient.name,
        quantity: missingQuantity,
        unit: ingredient.unit,
        productId: ingredient.productId,
        origin: 'recette',
      );
}

/// Compare les ingrédients (déjà ajustés aux portions) au stock.
List<MissingIngredient> missingIngredients(
  List<RecipeIngredient> ingredients,
  List<StockSnapshot> stock,
  DateTime now,
) {
  final result = <MissingIngredient>[];
  for (final ing in ingredients) {
    final m = matchingStock(ing, stock, now);
    if (m.isEmpty) {
      result.add(MissingIngredient(ing, ing.quantity));
      continue;
    }
    if (ing.quantity == null) continue; // « sel à volonté » : présent suffit.
    final need = toBase(ing.quantity!, ing.unit);
    var have = 0.0;
    var comparable = false;
    for (final s in m) {
      final b = toBase(s.quantity, s.unit);
      if (b.unit == need.unit) {
        have += b.value;
        comparable = true;
      }
    }
    // Unités incomparables (ex. « 2 gousses » contre « 100 g ») : on
    // considère l'ingrédient disponible plutôt que d'acheter en double.
    if (!comparable || have >= need.value) continue;
    final ratio = (need.value - have) / need.value;
    result.add(MissingIngredient(ing, ing.quantity! * ratio));
  }
  return result;
}
