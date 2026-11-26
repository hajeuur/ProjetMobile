import 'package:flutter/foundation.dart';

import '../logic/budget_forecast.dart' show BudgetLevel;
import '../logic/live_cart_budget.dart';
import '../models/live_cart.dart';
import '../models/receipt.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_service.dart';

/// « Je fais mes courses » : panier virtuel, budget en temps réel, alerte
/// douce au franchissement du seuil, passage en caisse.
class LiveCartViewModel extends ChangeNotifier {
  LiveCartViewModel(this.service, this.scan, {this.listId});

  final ShoppingService service;
  final ProductScanService scan;

  /// Liste dont les articles se cochent (mode magasin) ; null = liste en cours.
  final int? listId;

  List<LiveCartItem> items = [];
  CartBudget? budget;

  /// Part du budget avant le dernier changement (la jauge s'anime depuis là).
  double previousRatio = 0;

  /// Seuil ou budget franchi par le dernier ajout (alerte douce).
  BudgetLevel? alert;
  bool loading = true;

  double get total => items.fold(0.0, (s, i) => s + i.total);
  int get count => items.length;

  Future<void> load() async {
    items = await service.liveCart();
    budget = await service.cartBudget(items);
    previousRatio = budget!.ratio;
    loading = false;
    notifyListeners();
  }

  Future<void> _save({bool mayAlert = false}) async {
    await service.saveLiveCart(items);
    final before = budget;
    budget = await service.cartBudget(items);
    previousRatio = before?.ratio ?? 0;
    if (mayAlert && before != null) {
      final crossed = crossedLevel(before, budget!);
      if (crossed != null) {
        alert = crossed;
        // Vibration d'alerte (respecte l'interrupteur Vibreur).
        if ((await service.settings()).vibration) await service.vibrator.alert(crossed);
      }
    }
    notifyListeners();
  }

  /// Code-barres scanné : produit et prix connus → ajouté ; sinon renvoie le
  /// nom à compléter par un prix saisi.
  Future<({String name, bool added})> addBarcode(String code) async {
    final r = await scan.resolveBarcode(code);
    if (r.price == null) return (name: r.name, added: false);
    await add(LiveCartItem(label: r.name, unitPrice: r.price!, barcode: code, priceSource: r.source));
    return (name: r.name, added: true);
  }

  /// Ajoute (ou augmente la quantité) et coche l'article de la liste en cours.
  Future<void> add(LiveCartItem item) async {
    final i = items.indexWhere((x) => x.sameProduct(item));
    if (i >= 0) {
      items[i] = items[i].copyWith(quantity: items[i].quantity + item.quantity, unitPrice: item.unitPrice);
    } else {
      final listItem = await service.checkListItemFor(item.label, listId: listId);
      items.add(item.copyWith(listItemId: listItem));
    }
    await _save(mayAlert: true);
  }

  Future<void> setQuantity(int index, double quantity) async {
    if (quantity <= 0) {
      await remove(index);
      return;
    }
    final before = items[index].quantity;
    items[index] = items[index].copyWith(quantity: quantity);
    await _save(mayAlert: quantity > before);
  }

  /// Retire un article (l'article de la liste coché redevient à prendre).
  Future<LiveCartItem> remove(int index) async {
    final removed = items.removeAt(index);
    if (removed.listItemId != null) await service.uncheckListItem(removed.listItemId!);
    await _save();
    return removed;
  }

  /// « Annuler » après un glissement.
  Future<void> undoRemove(int index, LiveCartItem item) async {
    items.insert(index.clamp(0, items.length), item);
    if (item.listItemId != null) await service.checkListItemFor(item.label, listId: listId);
    await _save();
  }

  void dismissAlert() {
    alert = null;
    notifyListeners();
  }

  /// Brouillon de ticket pour le passage en caisse.
  ReceiptDraft draft() => ReceiptDraft(
        date: service.now,
        lines: [
          for (final i in items)
            ReceiptLine(
              label: i.label,
              quantity: i.quantity,
              price: double.parse(i.total.toStringAsFixed(3)),
              barcode: i.barcode,
            ),
        ],
      );

  /// Après le passage en caisse (ticket enregistré).
  Future<void> clear() async {
    items = [];
    alert = null;
    await _save();
  }
}
