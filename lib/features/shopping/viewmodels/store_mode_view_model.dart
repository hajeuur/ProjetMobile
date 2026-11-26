import 'package:flutter/foundation.dart';

import '../integration/gateways.dart';
import '../logic/item_sorting.dart';
import '../logic/store_mode.dart';
import '../models/live_cart.dart';
import '../models/shopping_list.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_service.dart';
import 'live_cart_view_model.dart';

/// Mode magasin d'une liste : rayons, filtre « restants », progression,
/// panier en direct et scan, ordre des rayons appris.
class StoreModeViewModel extends ChangeNotifier {
  StoreModeViewModel(this.service, this.scan, this.listId) : cart = LiveCartViewModel(service, scan, listId: listId);

  final ShoppingService service;
  final ProductScanService scan;
  final int listId;

  /// Panier en direct (phase 12), dont les ajouts cochent cette liste.
  final LiveCartViewModel cart;

  bool loading = true;
  String? error;
  ShoppingList? list;
  List<ShoppingItem> items = [];
  StoreRef? store;
  List<String> savedOrder = const [];
  StoreSort sort = StoreSort.store;
  bool remainingOnly = false;
  bool dark = false;

  /// Panier en direct activé dans les réglages.
  bool liveCart = false;

  /// Retour haptique (interrupteur « Vibreur »).
  bool haptics = true;

  /// Rayons visités, dans l'ordre du premier article coché de chacun.
  final visited = <String>[];

  List<String> get aisleOrder => effectiveAisleOrder(savedOrder, store?.aisles ?? const []);

  List<AisleGroup> get groups => groupForStore(items, sort, aisleOrder: aisleOrder, remainingOnly: remainingOnly);

  int get done => items.where((i) => i.checked).length;
  int get total => items.length;
  bool get finished => total > 0 && done == total;
  String get progressLabel => storeProgressLabel(done, total);

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      list = await service.list(listId);
      items = await service.items(listId);
      try {
        store = await service.store(list?.storeId);
      } catch (_) {
        store = null; // gestion 4 indisponible : rayons par défaut
      }
      savedOrder = await service.savedAisleOrder(list?.storeId);
      final prefs = await service.storeModePrefs();
      sort = prefs.sort;
      dark = prefs.dark;
      final s = await service.settings();
      liveCart = s.liveCartMode;
      haptics = s.vibration;
      if (liveCart) await cart.load();
      error = null;
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Recharge la liste ; les articles cochés entre-temps (scan, panier)
  /// comptent comme des rayons visités.
  Future<void> reloadItems() async {
    final before = {for (final i in items) i.id: i.checked};
    items = await service.items(listId);
    for (final i in items) {
      if (i.checked && before[i.id] == false && !visited.contains(aisleOf(i))) visited.add(aisleOf(i));
    }
    notifyListeners();
  }

  /// Coche / décoche. Mise à jour immédiate de l'écran, puis enregistrement.
  Future<void> toggle(ShoppingItem item) async {
    final checked = !item.checked;
    items = [for (final i in items) i.id == item.id ? i.copyWith(checked: checked) : i];
    if (checked) {
      final a = aisleOf(item);
      if (!visited.contains(a)) visited.add(a);
    }
    notifyListeners();
    await service.setChecked(item, checked);
  }

  void setSort(StoreSort s) {
    sort = s;
    notifyListeners();
    service.saveStoreModePrefs(sort: s);
  }

  void toggleRemaining() {
    remainingOnly = !remainingOnly;
    notifyListeners();
  }

  void toggleDark() {
    dark = !dark;
    notifyListeners();
    service.saveStoreModePrefs(dark: dark);
  }

  /// Rayons de cette liste dans l'ordre actuel du magasin (pour les réorganiser).
  List<String> get listAisles => [
    for (final g in groupForStore(items, StoreSort.store, aisleOrder: aisleOrder)) g.aisle,
  ];

  /// Ordre choisi à la main : les rayons de la liste d'abord, puis les autres
  /// rayons déjà mémorisés. L'affichage passe en « Ordre du magasin ».
  Future<void> reorder(List<String> aisles) async {
    savedOrder = [
      ...aisles,
      for (final a in aisleOrder)
        if (!aisles.contains(a)) a,
    ];
    sort = StoreSort.store;
    notifyListeners();
    await service.saveAisleOrder(list?.storeId, savedOrder);
    await service.saveStoreModePrefs(sort: sort);
  }

  /// Code-barres scanné. Avec le panier en direct : ajouté au panier (si le
  /// prix est connu) et l'article de la liste se coche. Sinon : l'article de
  /// la liste se coche seulement.
  Future<({String name, bool inCart, bool checked})> scanned(String code) async {
    if (liveCart) {
      final r = await cart.addBarcode(code);
      await reloadItems();
      final checked = r.added && cart.items.any((i) => i.barcode == code && i.listItemId != null);
      return (name: r.name, inCart: r.added, checked: checked);
    }
    final r = await scan.resolveBarcode(code);
    final id = await service.checkListItemFor(r.name, listId: listId);
    await reloadItems();
    return (name: r.name, inCart: false, checked: id != null);
  }

  /// Article ajouté au panier avec un prix saisi.
  Future<void> addToCart(LiveCartItem item) async {
    await cart.add(item);
    await reloadItems();
  }

  /// Sortie du mode magasin : l'ordre de visite affine celui du magasin.
  Future<void> finishTrip() async {
    if (visited.length < 2) return;
    final v = [...visited];
    visited.clear();
    try {
      savedOrder = await service.learnAisleOrder(list?.storeId, v);
    } catch (_) {
      // Base fermée (sortie de l'app) : on apprendra la prochaine fois.
    }
  }

  @override
  void dispose() {
    cart.dispose();
    super.dispose();
  }
}
