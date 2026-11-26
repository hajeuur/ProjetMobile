import 'package:flutter/foundation.dart';

import '../integration/gateways.dart';
import '../logic/text_similarity.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../models/shopping_list.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import 'live_scan_view_model.dart';

enum ReceiptSort {
  date('Date'),
  amount('Montant');

  const ReceiptSort(this.label);
  final String label;
}

/// Écran « Historique des tickets » : tri par date ou montant, recherche par
/// magasin.
class ReceiptsViewModel extends ChangeNotifier {
  ReceiptsViewModel(this.service);
  final ShoppingService service;

  bool loading = false;
  String? error;
  List<Receipt> receipts = [];
  ReceiptSort sort = ReceiptSort.date;
  bool descending = true;
  String query = '';

  List<Receipt> get visible {
    final q = normalize(query);
    final out = receipts.where((r) => q.isEmpty || normalize(r.storeName ?? '').contains(q)).toList();
    out.sort((a, b) {
      final c = sort == ReceiptSort.date ? a.date.compareTo(b.date) : a.total.compareTo(b.total);
      return descending ? -c : c;
    });
    return out;
  }

  double get visibleTotal => visible.fold(0, (s, r) => s + r.total);

  /// Magasins de la gestion 4 (type, pour l'icône).
  Map<int, StoreRef> stores = {};

  StoreRef? storeOf(Receipt r) => r.storeId == null ? null : stores[r.storeId];

  /// Tickets regroupés par mois (tri par date uniquement), avec le total du mois.
  List<({DateTime month, double total, List<Receipt> receipts})> get byMonth {
    final groups = <String, List<Receipt>>{};
    for (final r in visible) {
      groups.putIfAbsent(monthKey(r.date), () => []).add(r);
    }
    return [
      for (final e in groups.entries)
        (
          month: parseMonthKey(e.key),
          total: e.value.fold<double>(0, (s, r) => s + r.total),
          receipts: e.value,
        ),
    ];
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      receipts = await service.receipts();
      if (stores.isEmpty) stores = {for (final s in await service.storeList()) s.id: s};
    } catch (e) {
      error = 'Chargement impossible : $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSort(ReceiptSort s) {
    if (s == sort) {
      descending = !descending;
    } else {
      sort = s;
      descending = true;
    }
    notifyListeners();
  }

  void search(String q) {
    query = q;
    notifyListeners();
  }

  Future<void> delete(Receipt r) async {
    await service.deleteReceipt(r.id!);
    await load();
  }
}

enum ScanStep { choose, capturing, reading, review, saving }

/// Écrans « Scan du ticket » puis « Validation des lignes ».
class ReceiptScanViewModel extends ChangeNotifier {
  ReceiptScanViewModel(this.service, this.reader, {this.listId});

  final ShoppingService service;
  final ReceiptReader reader;
  final int? listId;

  ScanStep step = ScanStep.choose;
  String? error;
  ReceiptDraft? draft;
  List<StoreRef> stores = [];
  List<ShoppingList> lists = [];
  bool ocrEnabled = true;

  /// Lignes à vérifier (confiance faible au scan en direct), en orange.
  final Set<ReceiptLine> doubtful = Set.identity();

  bool isDoubtful(ReceiptLine l) => doubtful.contains(l);

  Future<void> init() async {
    stores = await service.storeList();
    lists = await service.lists(status: ListStatus.active);
    ocrEnabled = (await service.settings()).ocr;
    notifyListeners();
  }

  /// Photo puis reconnaissance du texte.
  Future<void> capture(PhotoSource source) async {
    error = null;
    step = ScanStep.capturing;
    notifyListeners();
    try {
      final photo = await reader.capture(source);
      if (photo == null) {
        step = ScanStep.choose;
        notifyListeners();
        return;
      }
      if (!ocrEnabled) {
        draft = ReceiptDraft(photo: photo, date: service.now, listId: listId);
        await _targetCurrentList();
        step = ScanStep.review;
        notifyListeners();
        return;
      }
      step = ScanStep.reading;
      notifyListeners();
      final text = await reader.readText(photo);
      draft = await service.draftFromText(text, photo: photo, listId: listId);
      await _targetCurrentList();
      if (draft!.lines.isEmpty) {
        error = 'Aucune ligne lue : vérifiez la netteté et la lumière, ou complétez à la main.';
      }
      step = ScanStep.review;
    } on LiveCameraException catch (e) {
      error = '$e Choisissez une photo ou saisissez le ticket à la main.';
      step = ScanStep.choose;
    } catch (e) {
      error = 'Lecture impossible : $e';
      step = ScanStep.choose;
    }
    notifyListeners();
  }

  /// Texte déjà disponible (collé, ou tests).
  Future<void> fromText(String text) async {
    draft = await service.draftFromText(text, listId: listId);
    await _targetCurrentList();
    step = ScanStep.review;
    notifyListeners();
  }

  /// Résultat du scan en direct : lignes, total, photo conservée.
  Future<void> fromLive(LiveScanOutcome outcome) async {
    error = null;
    step = ScanStep.reading;
    notifyListeners();
    try {
      draft = await service.draftFromParsed(outcome.receipt!, ocrText: outcome.ocrText, photo: outcome.photo, listId: listId);
      await _targetCurrentList();
      doubtful
        ..clear()
        ..addAll([for (final i in outcome.doubtful) if (i < draft!.lines.length) draft!.lines[i]]);
      if (outcome.photo == null) error = "La photo du ticket n'a pas pu être prise : les lignes lues sont conservées.";
      step = ScanStep.review;
    } catch (e) {
      error = 'Lecture impossible : $e';
      step = ScanStep.choose;
    }
    notifyListeners();
  }

  /// Saisie entièrement manuelle.
  Future<void> manual() async {
    draft = ReceiptDraft(date: service.now, listId: listId);
    await _targetCurrentList();
    step = ScanStep.review;
    notifyListeners();
  }

  /// Brouillon déjà prêt (« Passer en caisse » du panier en direct).
  Future<void> useDraft(ReceiptDraft d) async {
    draft = d;
    await _targetCurrentList();
    step = ScanStep.review;
    notifyListeners();
  }

  /// Sans liste choisie : rapprochement avec la liste de courses en cours
  /// (modifiable sur l'écran de validation, « Aucune » possible).
  Future<void> _targetCurrentList() async {
    if (draft == null || draft!.listId != null) return;
    if (!(await service.settings()).autoReconcile) return; // interrupteur « Rapprochement automatique »
    draft!.listId = await service.currentListId();
  }

  void reset() {
    draft = null;
    doubtful.clear();
    error = null;
    step = ScanStep.choose;
    notifyListeners();
  }

  void setStore(StoreRef? s) {
    draft!
      ..storeId = s?.id
      ..storeName = s?.name;
    notifyListeners();
  }

  void setStoreName(String name) {
    draft!
      ..storeId = null
      ..storeName = name;
    notifyListeners();
  }

  void setDate(DateTime d) {
    draft!.date = DateTime(d.year, d.month, d.day, draft!.date.hour, draft!.date.minute);
    notifyListeners();
  }

  void setList(int? id) {
    draft!.listId = id;
    notifyListeners();
  }

  void setReadTotal(double? total) {
    draft!.readTotal = total;
    notifyListeners();
  }

  Future<void> putLine(int? index, ReceiptLine line) async {
    final enriched = await service.enrichLine(line);
    if (index == null) {
      draft!.lines.add(enriched);
    } else {
      doubtful.remove(draft!.lines[index]); // corrigée à la main : vérifiée
      draft!.lines[index] = enriched;
    }
    notifyListeners();
  }

  void removeLine(int index) {
    doubtful.remove(draft!.lines.removeAt(index));
    notifyListeners();
  }

  Future<ReceiptReport?> save() async {
    error = null;
    step = ScanStep.saving;
    notifyListeners();
    try {
      final report = await service.saveDraft(draft!);
      return report;
    } catch (e) {
      error = e is ArgumentError ? '${e.message}' : 'Enregistrement impossible : $e';
      step = ScanStep.review;
      notifyListeners();
      return null;
    }
  }
}
