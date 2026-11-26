/// Tri et recherche des articles d'une liste.
library;

import '../models/shopping_list.dart';
import 'categories.dart';
import 'text_similarity.dart';

enum ItemSort {
  added('Ordre d\'ajout'),
  aisle('Par rayon');

  const ItemSort(this.label);
  final String label;
}

/// Rayon d'un article : celui saisi, sinon la catégorie devinée.
String aisleOf(ShoppingItem item) => (item.aisle == null || item.aisle!.isEmpty) ? guessCategory(item.label) : item.aisle!;

/// Place d'un rayon : son rang dans [aisleOrder] (ordre du magasin), sinon
/// après, dans l'ordre des catégories par défaut.
int aisleRank(String aisle, List<String> aisleOrder) {
  final a = normalize(aisle);
  for (var i = 0; i < aisleOrder.length; i++) {
    if (normalize(aisleOrder[i]) == a) return i;
  }
  // Rayon du magasin dont le nom contient la catégorie (« Laitiers » / « Produits laitiers »).
  for (var i = 0; i < aisleOrder.length; i++) {
    final k = normalize(aisleOrder[i]);
    if (k.contains(a) || a.contains(k)) return i;
  }
  final cat = kCategories.indexWhere((c) => normalize(c) == a);
  return aisleOrder.length + (cat < 0 ? kCategories.length : cat);
}

/// Trie les articles. Par rayon, l'ordre est celui du magasin choisi
/// ([aisleOrder], fourni par la gestion 4) ; les rayons inconnus du magasin
/// passent après, dans l'ordre des catégories par défaut. Les articles cochés
/// vont toujours en bas.
List<ShoppingItem> sortItems(List<ShoppingItem> items, ItemSort sort, {List<String> aisleOrder = const []}) {
  final copy = [...items];
  copy.sort((x, y) {
    if (x.checked != y.checked) return x.checked ? 1 : -1;
    if (sort == ItemSort.aisle) {
      final c = aisleRank(aisleOf(x), aisleOrder).compareTo(aisleRank(aisleOf(y), aisleOrder));
      if (c != 0) return c;
    }
    return x.position.compareTo(y.position);
  });
  return copy;
}

/// Recherche d'un article par libellé (sans accents ni majuscules).
List<ShoppingItem> searchItems(List<ShoppingItem> items, String query) {
  final q = normalize(query);
  if (q.isEmpty) return items;
  return items.where((i) => normalize(i.label).contains(q)).toList();
}
