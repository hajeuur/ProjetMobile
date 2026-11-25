import '../../recipes/integration/gateways.dart' as recipes;
import '../models/shopping_list.dart';
import '../services/shopping_service.dart';

/// Implémentation réelle du `ShoppingGateway` attendu par la gestion 3 :
/// les ingrédients manquants d'une recette arrivent dans la liste en cours
/// avec l'origine « recette ».
class RecipesShoppingBridge implements recipes.ShoppingGateway {
  RecipesShoppingBridge(this.service);
  final ShoppingService service;

  @override
  Future<int> addItems(List<recipes.ShoppingRequest> items) => service.addRequests([
        for (final i in items)
          ShoppingRequestData(
            label: i.label,
            quantity: i.quantity,
            unit: i.unit,
            productId: i.productId,
            origin: ItemOrigin.fromLabel(i.origin),
          ),
      ]);
}
