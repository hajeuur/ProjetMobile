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

/// Trie les articles. Par rayon, l'ordre est celui du magasin choisi
/// ([aisleOrder], fourni par la gestion 4) ; les rayons inconnus du magasin
/// passent après, dans l'ordre des catégories par défaut. Les articles cochés
/// vont toujours en bas.
List<ShoppingItem> sortItems(List<ShoppingItem> items, ItemSort sort, {List<String> aisleOrder = const []}) {
  final order = <String, int>{};
  for (var i = 0; i < aisleOrder.length; i++) {
    order[normalize(aisleOrder[i])] = i;
  }
  int aisleRank(ShoppingItem it) {
    final a = normalize(aisleOf(it));
    final known = order[a];
    if (known != null) return known;
    // Rayon du magasin dont le nom contient la catégorie (« Laitiers » / « Produits laitiers »).
    for (final e in order.entries) {
      if (e.key.contains(a) || a.contains(e.key)) return e.value;
    }
    final cat = kCategories.indexWhere((c) => normalize(c) == a);
    return aisleOrder.length + (cat < 0 ? kCategories.length : cat);
  }

  final copy = [...items];
  copy.sort((x, y) {
    if (x.checked != y.checked) return x.checked ? 1 : -1;
    if (sort == ItemSort.aisle) {
      final c = aisleRank(x).compareTo(aisleRank(y));
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
