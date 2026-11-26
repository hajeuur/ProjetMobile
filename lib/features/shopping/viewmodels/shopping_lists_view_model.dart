import 'package:flutter/foundation.dart';

import '../integration/gateways.dart';
import '../logic/item_sorting.dart';
import '../logic/undo_history.dart';
import '../logic/voice_parser.dart';
import '../models/dates.dart';
import '../models/shopping_list.dart';
import '../services/shopping_service.dart';

/// Écran « Listes de courses » : listes en cours et terminées.
class ShoppingListsViewModel extends ChangeNotifier {
  ShoppingListsViewModel(this.service);
  final ShoppingService service;

  bool loading = false;
  String? error;
  List<ShoppingList> active = [];
  List<ShoppingList> done = [];
  Map<int, StoreRef> stores = {};

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      active = await service.lists(status: ListStatus.active);
      done = await service.lists(status: ListStatus.done);
      stores = {for (final s in await service.storeList()) s.id: s};
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<int> create(String name, {int? storeId}) async {
    final id = await service.createList(name, storeId: storeId);
    await load();
    return id;
  }

  Future<void> rename(ShoppingList l, String name) async {
    await service.renameList(l, name);
    await load();
  }

  Future<void> archive(ShoppingList l) async {
    await service.archiveList(l);
    await load();
  }

  Future<void> reopen(ShoppingList l) async {
    await service.reopenList(l);
    await load();
  }

  Future<void> delete(ShoppingList l) async {
    await service.deleteList(l.id!);
    await load();
  }

  /// Ruptures prévues (gestion 2) → liste en cours.
  Future<int> importShortages() async {
    final n = await service.importShortages();
    await load();
    return n;
  }
}

/// Écran « Détail d'une liste ».
class ListDetailViewModel extends ChangeNotifier {
  ListDetailViewModel(this.service, this.listId);
  final ShoppingService service;
  final int listId;

  bool loading = false;
  String? error;
  ShoppingList? list;
  List<ShoppingItem> items = [];
  List<StoreRef> stores = [];
  ItemSort sort = ItemSort.added;
  String query = '';

  StoreRef? get store {
    for (final s in stores) {
      if (s.id == list?.storeId) return s;
    }
    return null;
  }

  List<ShoppingItem> get visibleItems =>
      sortItems(searchItems(items, query), sort, aisleOrder: store?.aisles ?? const []);

  int get checkedCount => items.where((i) => i.checked).length;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      list = await service.list(listId);
      items = await service.items(listId);
      if (stores.isEmpty) stores = await service.storeList();
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSort(ItemSort s) {
    sort = s;
    notifyListeners();
  }

  void search(String q) {
    query = q;
    notifyListeners();
  }

  // ------------------------------------------------- Actions annulables

  /// Historique pour « Secouer pour annuler » (10 dernières actions).
  final history = ItemUndoHistory();

  bool get canUndo => history.canUndo;

  Future<void> add(String label, {double? quantity, String? unit}) async {
    final before = {for (final i in items) i.id: i};
    final id = await service.addItem(listId, label: label, quantity: quantity, unit: unit);
    await load();
    final after = items.where((i) => i.id == id).firstOrNull;
    // Article existant complété (fusion) : on garde son état d'avant.
    if (after != null) history.record(ItemAction(type: ItemActionType.add, before: before[id], after: after));
    notifyListeners();
  }

  Future<void> toggle(ShoppingItem item) async {
    final after = item.copyWith(checked: !item.checked);
    // Mise à jour immédiate de l'écran, puis enregistrement.
    items = [for (final i in items) i.id == item.id ? after : i];
    history.record(ItemAction(type: ItemActionType.toggle, before: item, after: after));
    notifyListeners();
    await service.setChecked(item, !item.checked);
  }

  Future<void> update(ShoppingItem item) async {
    await service.updateItem(item);
    await load();
  }

  Future<void> remove(ShoppingItem item) async {
    await service.removeItem(item.id!);
    history.record(ItemAction(type: ItemActionType.delete, before: item));
    await load();
  }

  // ------------------------------------------------------- Ajout vocal

  final _voiceParser = const VoiceItemParser();

  /// Découpe la phrase dictée et repère les articles déjà dans la liste.
  Future<List<VoiceDraft>> prepareVoice(String sentence) async => [
        for (final v in _voiceParser.parse(sentence))
          VoiceDraft(label: v.label, quantity: v.quantity, unit: v.unit, existing: await findExisting(v.label)),
      ];

  Future<ShoppingItem?> findExisting(String label) =>
      label.trim().isEmpty ? Future.value(null) : service.findSameItem(listId, label);

  /// Ajoute les articles confirmés (origine « voix »). Un article déjà présent
  /// voit sa quantité augmentée si l'utilisateur l'a choisi et si les unités
  /// le permettent. Chaque ajout reste annulable. Renvoie le nombre traité.
  Future<int> addVoiceItems(List<VoiceDraft> drafts) async {
    var count = 0;
    final added = <int>[];
    for (final d in drafts) {
      final label = d.label.trim();
      if (label.isEmpty) continue;
      final existing = d.existing;
      final merged = d.canMerge ? mergedQuantity(existing!.quantity, existing.unit, d.quantity, d.unit) : null;
      if (d.mergeIntoExisting && merged != null) {
        final after = existing!.copyWith(
          quantity: merged.quantity,
          clearQuantity: merged.quantity == null,
          unit: merged.unit,
        );
        await service.updateItem(after);
        history.record(ItemAction(type: ItemActionType.add, before: existing, after: after));
      } else {
        added.add(await service.addItem(
          listId,
          label: label,
          quantity: d.quantity,
          unit: d.unit,
          origin: ItemOrigin.voice,
          mergeWithExisting: false,
        ));
      }
      count++;
    }
    await load();
    for (final id in added) {
      final item = items.where((i) => i.id == id).firstOrNull;
      if (item != null) history.record(ItemAction(type: ItemActionType.add, after: item));
    }
    notifyListeners();
    return count;
  }

  /// Annule la dernière action ; renvoie null s'il n'y a rien à annuler.
  Future<ItemAction?> undo() async {
    final a = history.popUndo();
    if (a == null) return null;
    switch (a.type) {
      case ItemActionType.toggle:
        await service.setChecked(a.before!, a.before!.checked);
      case ItemActionType.delete:
        // L'article revient à sa place (position, état coché, origine).
        a.before = a.before!.withId(await service.restoreItem(a.before!));
      case ItemActionType.add:
        if (a.isMerge) {
          await service.updateItem(a.before!);
        } else {
          await service.removeItem(a.after!.id!);
        }
    }
    history.undone(a);
    await load();
    return a;
  }

  /// Rétablit la dernière action annulée.
  Future<ItemAction?> redo() async {
    final a = history.popRedo();
    if (a == null) return null;
    switch (a.type) {
      case ItemActionType.toggle:
        await service.setChecked(a.after!, a.after!.checked);
      case ItemActionType.delete:
        await service.removeItem(a.before!.id!);
      case ItemActionType.add:
        if (a.isMerge) {
          await service.updateItem(a.after!);
        } else {
          a.after = a.after!.withId(await service.restoreItem(a.after!));
        }
    }
    history.redone(a);
    await load();
    return a;
  }

  Future<int> removeChecked() async {
    final n = await service.removeCheckedItems(listId);
    // Action groupée non annulable : l'historique ne correspondrait plus.
    history.clear();
    await load();
    return n;
  }

  Future<void> setStore(int? storeId) async {
    if (list == null) return;
    await service.setListStore(list!, storeId);
    if (storeId != null) sort = ItemSort.aisle;
    await load();
  }

  Future<void> rename(String name) async {
    if (list == null) return;
    await service.renameList(list!, name);
    await load();
  }

  Future<void> archive() async {
    if (list == null) return;
    await service.archiveList(list!);
    await load();
  }
}

/// Article détecté dans une phrase dictée, modifiable avant l'ajout.
class VoiceDraft {
  VoiceDraft({required this.label, this.quantity, this.unit, this.existing, bool? mergeIntoExisting})
      : mergeIntoExisting = mergeIntoExisting ?? true;

  String label;
  double? quantity;
  String? unit;

  /// Même article déjà à acheter dans la liste.
  ShoppingItem? existing;

  /// Augmenter la quantité de l'article existant plutôt que l'ajouter à part.
  bool mergeIntoExisting;

  bool get canMerge =>
      existing != null && mergedQuantity(existing!.quantity, existing!.unit, quantity, unit) != null;

  /// « 2 L → 3 L » pour la confirmation.
  String? get mergePreview {
    final e = existing;
    if (e == null) return null;
    final m = mergedQuantity(e.quantity, e.unit, quantity, unit);
    if (m == null) return null;
    final before = e.quantity == null ? 'sans quantité' : e.quantityText;
    final after = m.quantity == null ? 'sans quantité' : formatQuantity(m.quantity, m.unit);
    return '$before → $after';
  }
}
