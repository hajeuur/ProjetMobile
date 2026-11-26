/// Mode magasin : articles groupés par rayon, filtre « restants »,
/// progression, et ordre des rayons appris au fil des courses.
library;

import '../models/shopping_list.dart';
import 'item_sorting.dart';
import 'text_similarity.dart';

enum StoreSort {
  /// Ordre du magasin : appris (ou réorganisé à la main), puis celui de la gestion 4.
  store('Ordre du magasin'),

  /// Ordre des rayons par défaut (catégories).
  category('Rayons par défaut'),

  /// Sans regroupement, dans l'ordre d'ajout.
  added('Ordre d\'ajout');

  const StoreSort(this.label);
  final String label;

  static StoreSort fromName(String? n) => values.firstWhere((s) => s.name == n, orElse: () => store);
}

class AisleGroup {
  const AisleGroup(this.aisle, this.items);

  /// Nom du rayon (« Tous les articles » sans regroupement).
  final String aisle;
  final List<ShoppingItem> items;

  int get done => items.where((i) => i.checked).length;
  bool get complete => done == items.length;
}

const allItemsTitle = 'Tous les articles';

/// Ordre effectif des rayons : celui mémorisé pour ce magasin d'abord, puis
/// les rayons connus de la gestion 4 qui n'y sont pas encore.
List<String> effectiveAisleOrder(List<String> saved, List<String> storeAisles) {
  final seen = {for (final a in saved) normalize(a)};
  return [
    ...saved,
    for (final a in storeAisles)
      if (seen.add(normalize(a))) a,
  ];
}

/// Groupes affichés. Les articles cochés restent à leur place (grisés) pour
/// que rien ne saute sous le doigt ; [remainingOnly] les masque.
List<AisleGroup> groupForStore(
  List<ShoppingItem> items,
  StoreSort sort, {
  List<String> aisleOrder = const [],
  bool remainingOnly = false,
}) {
  final visible = [
    for (final i in [...items]..sort((a, b) => a.position.compareTo(b.position)))
      if (!remainingOnly || !i.checked) i,
  ];
  if (visible.isEmpty) return const [];
  if (sort == StoreSort.added) return [AisleGroup(allItemsTitle, visible)];
  final order = sort == StoreSort.store ? aisleOrder : const <String>[];
  final groups = <String, List<ShoppingItem>>{};
  final names = <String, String>{};
  for (final i in visible) {
    final a = aisleOf(i);
    groups.putIfAbsent(normalize(a), () => []).add(i);
    names.putIfAbsent(normalize(a), () => a);
  }
  final keys = groups.keys.toList()
    ..sort((x, y) {
      final c = aisleRank(names[x]!, order).compareTo(aisleRank(names[y]!, order));
      return c != 0 ? c : x.compareTo(y);
    });
  return [for (final k in keys) AisleGroup(names[k]!, groups[k]!)];
}

/// « 12/18 articles », « 0/1 article ».
String storeProgressLabel(int done, int total) => '$done/$total article${total > 1 ? 's' : ''}';

/// Apprend l'ordre des rayons d'après celui dans lequel ils ont été visités
/// (premier article coché de chaque rayon). Chaque rayon a un score entre 0
/// et 1 (sa place) ; les rayons visités prennent la moyenne de l'ancien et
/// du nouveau score, les autres gardent le leur. Une seule visite ne
/// bouleverse donc pas un ordre déjà appris.
List<String> mergeAisleOrder(List<String> previous, List<String> visited) {
  final v = <String>[];
  final seen = <String>{};
  for (final a in visited) {
    if (seen.add(normalize(a))) v.add(a);
  }
  if (v.length < 2) return previous; // rien à apprendre d'un seul rayon
  if (previous.isEmpty) return v;
  double place(int i, int n) => n <= 1 ? 0 : i / (n - 1);
  final score = <String, double>{};
  final name = <String, String>{};
  for (var i = 0; i < previous.length; i++) {
    score[normalize(previous[i])] = place(i, previous.length);
    name[normalize(previous[i])] = previous[i];
  }
  for (var i = 0; i < v.length; i++) {
    final k = normalize(v[i]);
    final now = place(i, v.length);
    score[k] = score.containsKey(k) ? (score[k]! + now) / 2 : now;
    name.putIfAbsent(k, () => v[i]);
  }
  final keys = score.keys.toList()
    ..sort((a, b) {
      final c = score[a]!.compareTo(score[b]!);
      if (c != 0) return c;
      // Égalité : l'ordre de la dernière visite l'emporte.
      final ia = v.indexWhere((x) => normalize(x) == a);
      final ib = v.indexWhere((x) => normalize(x) == b);
      return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
    });
  return [for (final k in keys) name[k]!];
}
