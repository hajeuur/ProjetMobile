import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/open_prices_api.dart';
import '../data/shopping_repository.dart';
import '../integration/gateways.dart';
import '../logic/advice.dart';
import '../logic/badges.dart';
import '../logic/budget_forecast.dart';
import '../logic/best_time.dart';
import '../logic/categories.dart';
import '../logic/habitual_basket.dart';
import '../logic/price_alerts.dart';
import '../logic/receipt_reconciler.dart';
import '../logic/receipt_parser.dart';
import '../logic/store_comparison.dart';
import '../logic/text_similarity.dart';
import '../models/budget.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../models/shopping_list.dart';
import 'shopping_devices.dart';

/// Article envoyé par une autre gestion vers la liste en cours.
class ShoppingRequestData {
  const ShoppingRequestData({
    required this.label,
    this.quantity,
    this.unit,
    this.productId,
    this.origin = ItemOrigin.manual,
    this.aisle,
  });

  final String label;
  final double? quantity;
  final String? unit;
  final int? productId;
  final ItemOrigin origin;
  final String? aisle;
}

/// Ticket en cours de validation, avant enregistrement.
class ReceiptDraft {
  ReceiptDraft({
    this.photo,
    this.ocrText,
    this.storeId,
    this.storeName,
    required this.date,
    this.readTotal,
    List<ReceiptLine>? lines,
    this.listId,
  }) : lines = lines ?? [];

  String? photo;
  String? ocrText;
  int? storeId;
  String? storeName;
  DateTime date;

  /// Total lu sur le ticket (null si introuvable ou saisie manuelle).
  double? readTotal;
  List<ReceiptLine> lines;

  /// Liste à rapprocher avec ce ticket.
  int? listId;

  double get linesSum => lines.fold(0.0, (s, l) => s + l.price);
  double get total => readTotal ?? linesSum;
  bool get isConsistent => readTotal == null || (readTotal! - linesSum).abs() < 0.011;
}

/// Message d'état du budget après un achat.
class BudgetNotice {
  const BudgetNotice({
    required this.snapshot,
    required this.isNewLevel,
    required this.isNewForecast,
    this.previousRatio,
    this.vibrated = false,
    this.vibrationEnabled = true,
  });

  final BudgetSnapshot snapshot;

  /// Part du budget utilisée avant ce ticket (la jauge s'anime depuis là).
  final double? previousRatio;

  /// Le téléphone a vibré (false : vibreur désactivé ou absent).
  final bool vibrated;

  /// Interrupteur « Vibreur » des Réglages.
  final bool vibrationEnabled;

  /// Titre court de l'alerte (bannière, notification).
  String get title => switch (snapshot.level) {
        BudgetLevel.exceeded => snapshot.spent > (snapshot.amount ?? 0) ? 'Budget dépassé' : 'Budget atteint',
        BudgetLevel.threshold => 'Seuil d\'alerte de ${snapshot.budget?.alertThreshold ?? 80} % atteint',
        _ => 'Budget du mois',
      };

  /// Le niveau (seuil ou dépassement) vient d'être franchi : on a vibré.
  final bool isNewLevel;

  /// L'avertissement de dépassement prévu est nouveau ce mois-ci.
  final bool isNewForecast;

  bool get shouldShow => isNewLevel || isNewForecast;

  String get message {
    final s = snapshot;
    final b = s.budget;
    if (b == null) return 'Aucun budget défini pour ${monthLabel(s.month)}.';
    final used = '${(s.ratio * 100).round()} % du budget utilisé (${formatDt(s.spent)} sur ${formatDt(b.amount)})';
    final parts = <String>[
      switch (s.level) {
        BudgetLevel.exceeded => 'Budget dépassé de ${formatDt(s.spent - b.amount)} : $used.',
        BudgetLevel.threshold => 'Seuil d\'alerte de ${b.alertThreshold} % franchi : $used.',
        _ => 'Budget respecté : $used.',
      },
    ];
    // « À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour. »
    if (s.forecastOverrun) parts.add('Dépassement prévu. ${budgetSentence(s)}');
    return parts.join(' ');
  }
}

/// Article rapproché d'une ligne du ticket.
class PurchasedMatch {
  const PurchasedMatch({required this.itemId, required this.itemLabel, required this.lineLabel, required this.score});
  final int itemId;
  final String itemLabel;
  final String lineLabel;
  final double score;
}

/// Rapprochement incertain (score moyen) : « oui / non ? ».
class PendingMatch {
  const PendingMatch({
    required this.itemId,
    required this.itemLabel,
    this.itemProductId,
    required this.lineId,
    required this.lineLabel,
    this.lineProductId,
    required this.score,
  });
  final int itemId;
  final String itemLabel;
  final int? itemProductId;
  final int lineId;
  final String lineLabel;
  final int? lineProductId;
  final double score;
}

/// Résultat du rapprochement d'un ticket avec une liste (écran résumé).
class ReconciliationReport {
  const ReconciliationReport({
    required this.receiptId,
    required this.listId,
    required this.listName,
    this.purchased = const [],
    this.uncertain = const [],
    this.forgotten = const [],
    this.unplanned = const [],
    this.carriedTo,
  });

  final int receiptId;
  final int listId;
  final String listName;

  /// Articles cochés tout seuls (rapprochement sûr).
  final List<PurchasedMatch> purchased;

  /// À confirmer par l'utilisateur.
  final List<PendingMatch> uncertain;

  /// Articles non achetés.
  final List<ShoppingItem> forgotten;

  /// Libellés du ticket absents de la liste.
  final List<String> unplanned;

  /// Nom de la liste où les oubliés ont été reportés automatiquement.
  final String? carriedTo;
}

/// Bilan de la validation d'un ticket.
class ReceiptReport {
  const ReceiptReport({
    required this.receiptId,
    this.checkedLabels = const [],
    this.forgottenLabels = const [],
    this.unplannedLabels = const [],
    this.budget,
    this.priceAlerts = const [],
    this.warnings = const [],
    this.reconciliation,
  });

  final int receiptId;

  /// Rapprochement avec la liste (null si le ticket n'est lié à aucune liste).
  final ReconciliationReport? reconciliation;

  /// Articles de la liste cochés automatiquement.
  final List<String> checkedLabels;

  /// Articles de la liste oubliés en magasin.
  final List<String> forgottenLabels;

  /// Achats hors liste.
  final List<String> unplannedLabels;
  final BudgetNotice? budget;

  /// Hausses de prix détectées sur les produits de ce ticket.
  final List<PriceAlert> priceAlerts;

  /// Échecs non bloquants (autre gestion indisponible…).
  final List<String> warnings;
}

class MonthSpending {
  const MonthSpending(this.month, this.spent, this.budget);
  final DateTime month;
  final double spent;
  final double? budget;
}

/// Réglages de la gestion (chaque capteur peut être désactivé).
class ShoppingSettings {
  const ShoppingSettings({
    this.vibration = true,
    this.ocr = true,
    this.openPrices = true,
    this.shakeToUndo = true,
    this.voiceInput = true,
    this.carryForgotten = false,
    this.sharePrices = false,
    this.demoProducts = true,
    this.autoReconcile = true,
    this.matchThreshold = sureMatchScore,
    this.budgetAlerts = true,
    this.habitualBasket = true,
    this.bestTime = true,
  });
  final bool vibration;
  final bool ocr;
  final bool openPrices;

  /// « Secouer pour annuler » dans le détail d'une liste (accéléromètre).
  final bool shakeToUndo;

  /// Bouton micro « Ajout vocal » dans le détail d'une liste.
  final bool voiceInput;

  /// Oubliés reportés automatiquement dans « Prochaines courses ».
  final bool carryForgotten;

  /// « Partager mes prix » : bouton « Contribuer mon prix » (compte Open Food Facts).
  final bool sharePrices;

  /// Mode démo : trois codes-barres préchargés, utilisables sans réseau.
  final bool demoProducts;

  /// Rapprochement automatique du ticket avec la liste en cours.
  final bool autoReconcile;

  /// Score à partir duquel un article est coché sans confirmation (0,6 à 0,9).
  final double matchThreshold;

  /// Bannière, vibration et notification au franchissement du seuil / budget.
  final bool budgetAlerts;

  /// « Panier type par magasin » sur l'accueil Courses et l'écran Prix.
  final bool habitualBasket;

  /// « Meilleur moment pour acheter » dans l'écran Prix.
  final bool bestTime;

  ShoppingSettings copyWith({
    bool? vibration,
    bool? ocr,
    bool? openPrices,
    bool? shakeToUndo,
    bool? voiceInput,
    bool? carryForgotten,
    bool? sharePrices,
    bool? demoProducts,
    bool? autoReconcile,
    double? matchThreshold,
    bool? budgetAlerts,
    bool? habitualBasket,
    bool? bestTime,
  }) =>
      ShoppingSettings(
        vibration: vibration ?? this.vibration,
        ocr: ocr ?? this.ocr,
        openPrices: openPrices ?? this.openPrices,
        shakeToUndo: shakeToUndo ?? this.shakeToUndo,
        voiceInput: voiceInput ?? this.voiceInput,
        carryForgotten: carryForgotten ?? this.carryForgotten,
        sharePrices: sharePrices ?? this.sharePrices,
        demoProducts: demoProducts ?? this.demoProducts,
        autoReconcile: autoReconcile ?? this.autoReconcile,
        matchThreshold: matchThreshold ?? this.matchThreshold,
        budgetAlerts: budgetAlerts ?? this.budgetAlerts,
        habitualBasket: habitualBasket ?? this.habitualBasket,
        bestTime: bestTime ?? this.bestTime,
      );
}

/// Service de la gestion 5 — Courses et Budget.
///
/// Point d'entrée unique pour les écrans et pour les autres gestions.
class ShoppingService {
  ShoppingService({
    required this.repository,
    required this.prices,
    required this.users,
    required this.products,
    required this.stores,
    required this.vibrator,
    required this.tokens,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ShoppingRepository repository;
  final OpenPricesApi prices;
  final UserGateway users;
  final ProductGateway products;
  final StoreGateway stores;
  final AlertVibrator vibrator;
  final TokenStore tokens;
  final DateTime Function() _clock;

  static const currency = 'TND';

  DateTime get now => _clock();
  int get userId => users.currentUserId;

  // ------------------------------------------------------------ Réglages

  final _budgetAlerts = StreamController<BudgetNotice>.broadcast();
  final _receiptsChanged = StreamController<void>.broadcast();

  /// Franchissement du seuil ou du budget (une fois par franchissement) :
  /// l'app affiche la bannière, ou une notification en arrière-plan.
  Stream<BudgetNotice> get budgetAlerts => _budgetAlerts.stream;

  /// Un ticket a été ajouté, modifié ou supprimé : la jauge se met à jour.
  Stream<void> get receiptsChanged => _receiptsChanged.stream;

  Future<ShoppingSettings> settings() async => ShoppingSettings(
        vibration: (await repository.setting('vibration')) != '0',
        ocr: (await repository.setting('ocr')) != '0',
        openPrices: (await repository.setting('open_prices')) != '0',
        shakeToUndo: (await repository.setting('shake_undo')) != '0',
        voiceInput: (await repository.setting('voice_input')) != '0',
        carryForgotten: (await repository.setting('carry_forgotten')) == '1',
        sharePrices: (await repository.setting('share_prices')) == '1',
        demoProducts: (await repository.setting('demo_products')) != '0',
        autoReconcile: (await repository.setting('auto_reconcile')) != '0',
        matchThreshold: double.tryParse(await repository.setting('match_threshold') ?? '') ?? sureMatchScore,
        budgetAlerts: (await repository.setting('budget_alerts')) != '0',
        habitualBasket: (await repository.setting('habitual_basket')) != '0',
        bestTime: (await repository.setting('best_time')) != '0',
      );

  Future<void> saveSettings(ShoppingSettings s) async {
    await repository.setSetting('vibration', s.vibration ? '1' : '0');
    await repository.setSetting('ocr', s.ocr ? '1' : '0');
    await repository.setSetting('open_prices', s.openPrices ? '1' : '0');
    await repository.setSetting('shake_undo', s.shakeToUndo ? '1' : '0');
    await repository.setSetting('voice_input', s.voiceInput ? '1' : '0');
    await repository.setSetting('carry_forgotten', s.carryForgotten ? '1' : '0');
    await repository.setSetting('share_prices', s.sharePrices ? '1' : '0');
    await repository.setSetting('demo_products', s.demoProducts ? '1' : '0');
    await repository.setSetting('auto_reconcile', s.autoReconcile ? '1' : '0');
    await repository.setSetting('match_threshold', s.matchThreshold.toStringAsFixed(2));
    await repository.setSetting('budget_alerts', s.budgetAlerts ? '1' : '0');
    await repository.setSetting('habitual_basket', s.habitualBasket ? '1' : '0');
    await repository.setSetting('best_time', s.bestTime ? '1' : '0');
  }

  // -------------------------------------------------------------- Listes

  Future<List<ShoppingList>> lists({ListStatus? status}) => repository.lists(userId, status: status);
  Future<ShoppingList?> list(int id) => repository.list(id);

  Future<int> createList(String name, {int? storeId}) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Le nom de la liste est obligatoire.');
    return repository.insertList(ShoppingList(userId: userId, name: n, createdAt: now, storeId: storeId));
  }

  Future<void> renameList(ShoppingList l, String name) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Le nom de la liste est obligatoire.');
    return repository.updateList(l.copyWith(name: n));
  }

  Future<void> setListStore(ShoppingList l, int? storeId) =>
      repository.updateList(storeId == null ? l.copyWith(clearStore: true) : l.copyWith(storeId: storeId));

  /// Archive la liste (statut « terminée »).
  Future<void> archiveList(ShoppingList l) => repository.updateList(l.copyWith(status: ListStatus.done));
  Future<void> reopenList(ShoppingList l) => repository.updateList(l.copyWith(status: ListStatus.active));
  Future<void> deleteList(int id) => repository.deleteList(id);

  /// Liste en cours la plus récente ; en crée une si aucune n'existe.
  Future<ShoppingList> activeList() async {
    final active = await repository.lists(userId, status: ListStatus.active);
    if (active.isNotEmpty) return active.first;
    final id = await createList('Liste du ${formatDate(now)}');
    return (await repository.list(id))!;
  }

  // ------------------------------------------------------------ Articles

  Future<List<ShoppingItem>> items(int listId) => repository.items(listId);

  /// Ajoute un article. Si un article non coché du même nom existe déjà, les
  /// quantités sont additionnées (évite les achats en double) ; renvoie son id.
  Future<int> addItem(
    int listId, {
    required String label,
    double? quantity,
    String? unit,
    int? productId,
    ItemOrigin origin = ItemOrigin.manual,
    String? aisle,
    bool mergeWithExisting = true,
  }) async {
    final l = label.trim();
    if (l.isEmpty) throw ArgumentError('Le libellé est obligatoire.');
    if (quantity != null && quantity <= 0) throw ArgumentError('La quantité doit être positive.');
    final existing = mergeWithExisting ? _findSame(await repository.items(listId), l, productId) : null;
    if (existing != null) {
      await repository.updateItem(_merge(existing, quantity, unit));
      return existing.id!;
    }
    return repository.insertItem(ShoppingItem(
      listId: listId,
      label: l,
      quantity: quantity,
      unit: (unit?.trim().isEmpty ?? true) ? null : unit!.trim(),
      productId: productId,
      origin: origin,
      aisle: aisle ?? guessCategory(l),
      position: await repository.nextPosition(listId),
      createdAt: now,
    ));
  }

  /// Article non coché de la liste qui correspond à ce libellé (même
  /// produit ou même nom), pour proposer d'augmenter sa quantité.
  Future<ShoppingItem?> findSameItem(int listId, String label, {int? productId}) async =>
      _findSame(await repository.items(listId), label, productId);

  ShoppingItem? _findSame(List<ShoppingItem> items, String label, int? productId) {
    final key = labelKey(label);
    for (final i in items) {
      if (i.checked) continue;
      if (productId != null && i.productId == productId) return i;
      if (labelKey(i.label) == key) return i;
    }
    return null;
  }

  ShoppingItem _merge(ShoppingItem existing, double? quantity, String? unit) {
    if (quantity == null) return existing;
    if (existing.quantity == null) return existing.copyWith(quantity: quantity, unit: unit);
    final sameUnit = (existing.unit ?? '').toLowerCase() == (unit ?? '').toLowerCase();
    // Unités différentes : on garde la première quantité, le libellé suffit.
    return sameUnit ? existing.copyWith(quantity: existing.quantity! + quantity) : existing;
  }

  Future<void> updateItem(ShoppingItem item) {
    if (item.label.trim().isEmpty) throw ArgumentError('Le libellé est obligatoire.');
    return repository.updateItem(item);
  }

  Future<void> setChecked(ShoppingItem item, bool checked) => repository.setChecked(item.id!, checked);
  Future<void> removeItem(int id) => repository.deleteItem(id);

  /// Remet un article supprimé (même position, même état coché, même origine).
  Future<int> restoreItem(ShoppingItem item) => repository.insertItem(ShoppingItem(
        listId: item.listId,
        label: item.label,
        productId: item.productId,
        quantity: item.quantity,
        unit: item.unit,
        checked: item.checked,
        origin: item.origin,
        aisle: item.aisle,
        position: item.position,
        createdAt: item.createdAt,
      ));
  Future<int> removeCheckedItems(int listId) => repository.deleteCheckedItems(listId);

  // ------------------------------------- Alimentation automatique (métier 4)

  /// Point d'entrée des autres gestions : ajoute les articles à la liste en
  /// cours et renvoie le nombre d'articles ajoutés ou complétés.
  ///
  /// Une rupture prévue déjà présente n'est pas ajoutée une seconde fois ; un
  /// ingrédient de recette s'additionne (deux recettes peuvent demander des
  /// tomates).
  Future<int> addRequests(List<ShoppingRequestData> requests) async {
    if (requests.isEmpty) return 0;
    final list = await activeList();
    var count = 0;
    for (final r in requests) {
      if (r.label.trim().isEmpty) continue;
      if (r.origin == ItemOrigin.shortage) {
        final present = _findSame(await repository.items(list.id!), r.label, r.productId);
        if (present != null) continue;
      }
      await addItem(
        list.id!,
        label: r.label,
        quantity: (r.quantity != null && r.quantity! > 0) ? r.quantity : null,
        unit: r.unit,
        productId: r.productId,
        origin: r.origin,
        aisle: r.aisle,
      );
      count++;
    }
    return count;
  }

  /// Ajoute à la liste en cours les ruptures prévues par la gestion 2.
  Future<int> importShortages() async {
    final shortages = await products.upcomingShortages(withinDays: 2);
    return addRequests([
      for (final s in shortages)
        ShoppingRequestData(
          label: s.label,
          quantity: s.quantity,
          unit: s.unit,
          productId: s.productId,
          origin: ItemOrigin.shortage,
          aisle: s.category,
        ),
    ]);
  }

  /// Pour la gestion 4 : nombre d'articles restant à acheter (notification
  /// de géofencing à l'entrée d'un magasin).
  Future<int> pendingItemCount() async {
    final active = await repository.lists(userId, status: ListStatus.active);
    return active.fold<int>(0, (s, l) => s + l.itemCount - l.checkedCount);
  }

  /// Pour la gestion 4 : articles de la liste en cours (magasin optimal).
  Future<List<ShoppingItem>> activeListItems() async {
    final active = await repository.lists(userId, status: ListStatus.active);
    if (active.isEmpty) return const [];
    return (await repository.items(active.first.id!)).where((i) => !i.checked).toList();
  }

  // ------------------------------------------------------------ Magasins

  Future<List<StoreRef>> storeList() async {
    try {
      return await stores.stores();
    } catch (e) {
      debugPrint('Magasins indisponibles : $e');
      return const [];
    }
  }

  Future<StoreRef?> store(int? id) async {
    if (id == null) return null;
    for (final s in await storeList()) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ------------------------------------------------------------- Tickets

  Future<List<Receipt>> receipts({DateTime? from, DateTime? to}) => repository.receipts(userId, from: from, to: to);
  Future<Receipt?> receipt(int id) => repository.receipt(id);
  Future<void> deleteReceipt(int id) async {
    final r = await repository.receipt(id);
    await repository.deleteReceipt(id);
    // La dépense baisse : le niveau mémorisé redescend (un nouveau
    // franchissement déclenchera à nouveau l'alerte).
    if (r != null) await checkBudget(r.date);
    _receiptsChanged.add(null);
  }

  /// Prépare un brouillon à partir du texte reconnu sur la photo.
  Future<ReceiptDraft> draftFromText(String text, {String? photo, int? listId}) =>
      draftFromParsed(parseReceiptText(text), ocrText: text, photo: photo, listId: listId);

  /// Brouillon de ticket à partir de lignes déjà lues (scan en direct).
  Future<ReceiptDraft> draftFromParsed(ParsedReceipt parsed, {String? ocrText, String? photo, int? listId}) async {
    final draft = ReceiptDraft(
      photo: photo,
      ocrText: ocrText,
      date: _receiptDate(parsed.date),
      readTotal: parsed.total,
      listId: listId,
    );
    // Magasin : le nom d'un magasin connu dans l'en-tête du ticket.
    final known = await storeList();
    final head = normalize(parsed.headerLines.join(' '));
    StoreRef? guessed;
    for (final s in known) {
      final first = significantTokens(s.name);
      if (first.isNotEmpty && head.contains(first.first)) {
        guessed = s;
        break;
      }
    }
    if (listId != null && guessed == null) {
      final l = await repository.list(listId);
      guessed = await store(l?.storeId);
    }
    draft.storeId = guessed?.id;
    draft.storeName = guessed?.name ?? (parsed.headerLines.isEmpty ? null : parsed.headerLines.first);

    for (final p in parsed.lines) {
      draft.lines.add(await enrichLine(ReceiptLine(label: p.label, quantity: p.quantity, price: p.price, barcode: p.barcode)));
    }
    return draft;
  }

  DateTime _receiptDate(DateTime? read) {
    final today = now;
    // Une date lue dans le futur ou très ancienne est sûrement mal lue.
    if (read == null || read.isAfter(today) || today.difference(read).inDays > 365) return today;
    return DateTime(read.year, read.month, read.day, today.hour, today.minute);
  }

  /// Rapproche une ligne d'un produit de la gestion 2 et devine sa catégorie.
  Future<ReceiptLine> enrichLine(ReceiptLine line) async {
    var l = line;
    if (l.productId == null) {
      try {
        final p = await products.findByLabel(l.label);
        if (p != null) l = l.copyWith(productId: p.id, barcode: l.barcode ?? p.barcode, category: l.category ?? p.category);
      } catch (e) {
        debugPrint('Produits indisponibles : $e');
      }
    }
    return l.category == null ? l.copyWith(category: guessCategory(l.label)) : l;
  }

  void _validateReceipt(double total, List<ReceiptLine> lines) {
    if (lines.isEmpty && total <= 0) throw ArgumentError('Le ticket est vide.');
    if (total < 0) throw ArgumentError('Le total ne peut pas être négatif.');
    for (final l in lines) {
      if (l.label.trim().isEmpty) throw ArgumentError('Une ligne n\'a pas de libellé.');
      if (l.quantity <= 0) throw ArgumentError('Quantité invalide pour « ${l.label} ».');
    }
  }

  /// Enregistre le ticket validé puis referme le circuit :
  /// rapprochement avec la liste, prix payés (gestion 4), entrées en stock
  /// (gestion 2), contrôle du budget (vibreur) et hausses de prix.
  Future<ReceiptReport> saveDraft(ReceiptDraft draft) async {
    _validateReceipt(draft.total, draft.lines);
    final spentBefore = await spentIn(monthStart(draft.date));
    final lines = [for (final l in draft.lines) await enrichLine(l)];
    final receiptId = await repository.insertReceipt(Receipt(
      userId: userId,
      storeId: draft.storeId,
      storeName: draft.storeName?.trim().isEmpty ?? true ? null : draft.storeName!.trim(),
      date: draft.date,
      total: draft.total,
      photo: draft.photo,
      listId: draft.listId,
      lines: lines,
    ));
    final warnings = <String>[];

    ReconciliationReport? rec;
    if (draft.listId != null) {
      rec = await reconcile(receiptId, draft.listId!);
      if (rec.forgotten.isNotEmpty && (await settings()).carryForgotten) {
        final target = await keepForNextList(rec.forgotten);
        rec = ReconciliationReport(
          receiptId: rec.receiptId,
          listId: rec.listId,
          listName: rec.listName,
          purchased: rec.purchased,
          uncertain: rec.uncertain,
          forgotten: rec.forgotten,
          unplanned: rec.unplanned,
          carriedTo: target.name,
        );
      }
    }

    if (draft.storeId != null) {
      try {
        await stores.recordPaidPrices(draft.storeId!, draft.date, [
          for (final l in lines)
            if (l.price > 0) PaidPrice(label: l.label, productId: l.productId, unitPrice: l.unitPrice),
        ]);
      } catch (e) {
        warnings.add('Prix non transmis à la gestion Magasins : $e');
      }
    }
    try {
      for (final l in lines) {
        if (l.price > 0) await products.registerPurchase(productId: l.productId, label: l.label, quantity: l.quantity);
      }
    } catch (e) {
      warnings.add('Stock non mis à jour : $e');
    }

    final budget = await checkBudget(draft.date, spentBefore);
    _receiptsChanged.add(null);
    final keys = lines.map(_priceKey).toSet();
    final alerts = (await priceAlerts()).where((a) => keys.contains(a.key)).toList();

    return ReceiptReport(
      receiptId: receiptId,
      checkedLabels: [for (final m in rec?.purchased ?? const <PurchasedMatch>[]) m.itemLabel],
      forgottenLabels: [for (final i in rec?.forgotten ?? const <ShoppingItem>[]) i.label],
      unplannedLabels: rec?.unplanned ?? const [],
      reconciliation: rec,
      budget: budget,
      priceAlerts: alerts,
      warnings: warnings,
    );
  }

  /// Liste de courses en cours : la plus récente liste active qui a encore
  /// des articles à prendre (hors « Prochaines courses »).
  Future<int?> currentListId() async {
    final active = (await lists(status: ListStatus.active))
        .where((l) => l.name != nextListName && l.itemCount > l.checkedCount)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active.firstOrNull?.id;
  }

  /// Nom de la liste qui reçoit les articles oubliés.
  static const nextListName = 'Prochaines courses';

  /// Historique des réponses de l'utilisateur aux rapprochements incertains.
  Future<CorrectionMemory> correctionMemory() async =>
      CorrectionMemory.fromJson(await repository.setting('match_corrections'));

  /// Rapprochement liste ↔ ticket : les articles sûrs se cochent seuls (et
  /// la ligne reçoit le product_id de l'article), les cas moyens sont
  /// renvoyés pour confirmation, le reste est oublié ou hors liste.
  Future<ReconciliationReport> reconcile(int receiptId, int listId) async {
    final receipt = await repository.receipt(receiptId);
    if (receipt == null) throw StateError('Ticket introuvable.');
    final list = await repository.list(listId);
    if (list == null) throw StateError('Liste introuvable.');
    final items = await repository.items(listId);
    final lines = receipt.lines;
    final sure = (await settings()).matchThreshold.clamp(0.6, 0.9).toDouble();
    final result = ReceiptReconciler(
      sureThreshold: sure,
      askThreshold: sure - 0.25, // en dessous : aucune question
      memory: await correctionMemory(),
    ).reconcile(
      [for (final i in items) MatchCandidate(id: i.id!, label: i.label, productId: i.productId, checked: i.checked)],
      [
        for (var k = 0; k < lines.length; k++)
          if (lines[k].price > 0) LineCandidate(index: k, label: lines[k].label, productId: lines[k].productId),
      ],
    );
    final byId = {for (final i in items) i.id!: i};
    final purchased = <PurchasedMatch>[];
    for (final m in result.sure) {
      final item = byId[m.item.id]!;
      await _attachProduct(lines[m.line.index], item);
      if (item.checked) continue; // déjà coché à la main : rien à animer
      await repository.setChecked(item.id!, true);
      purchased.add(PurchasedMatch(itemId: item.id!, itemLabel: item.label, lineLabel: m.line.label, score: m.score));
    }
    if (receipt.listId != listId) await repository.setReceiptList(receiptId, listId);
    // Badge « Zéro oubli » : une course sans article oublié.
    if (result.forgotten.isEmpty && result.uncertain.isEmpty && purchased.isNotEmpty) {
      await _increment('perfect_trips');
    }
    return ReconciliationReport(
      receiptId: receiptId,
      listId: listId,
      listName: list.name,
      purchased: purchased,
      uncertain: [
        for (final m in result.uncertain)
          PendingMatch(
            itemId: m.item.id,
            itemLabel: m.item.label,
            itemProductId: m.item.productId,
            lineId: lines[m.line.index].id!,
            lineLabel: m.line.label,
            lineProductId: m.line.productId,
            score: m.score,
          ),
      ],
      forgotten: [for (final c in result.forgotten) byId[c.id]!],
      unplanned: [for (final l in result.unplanned) l.label],
    );
  }

  /// Rapprochement sûr : la ligne du ticket reçoit le produit de l'article.
  Future<void> _attachProduct(ReceiptLine line, ShoppingItem item) async {
    if (item.productId == null || line.productId != null || line.id == null) return;
    await repository.updateReceiptLine(line.copyWith(productId: item.productId));
  }

  /// Réponse à « « JUS POMME » correspond-il à « Jus d'orange » ? ». La réponse
  /// est mémorisée : la même paire ne sera plus jamais demandée.
  Future<void> confirmMatch(PendingMatch m, {required bool accepted}) async {
    final memory = await correctionMemory();
    memory.record(m.itemLabel, m.lineLabel, accepted);
    await repository.setSetting('match_corrections', memory.toJson());
    if (!accepted) return;
    await repository.setChecked(m.itemId, true);
    final item = await repository.item(m.itemId);
    final receipt = await repository.receipt(
      (await repository.receiptIdOfLine(m.lineId)) ?? -1,
    );
    final line = receipt?.lines.where((l) => l.id == m.lineId).firstOrNull;
    if (item != null && line != null) await _attachProduct(line, item);
  }

  /// Annule une réponse « oui » (l'article redevient à prendre).
  Future<void> undoConfirm(PendingMatch m) => repository.setChecked(m.itemId, false);

  /// Liste « Prochaines courses » (créée au besoin).
  Future<ShoppingList> nextList() async {
    final existing = (await lists(status: ListStatus.active)).where((l) => l.name == nextListName).firstOrNull;
    if (existing != null) return existing;
    final id = await createList(nextListName);
    return (await repository.list(id))!;
  }

  /// « Garder pour la prochaine liste » : les oubliés sont reportés dans
  /// « Prochaines courses » (sans doublon). Renvoie la liste utilisée.
  Future<ShoppingList> keepForNextList(List<ShoppingItem> forgotten) async {
    final target = await nextList();
    for (final i in forgotten) {
      if (await findSameItem(target.id!, i.label, productId: i.productId) != null) continue;
      await addItem(
        target.id!,
        label: i.label,
        quantity: i.quantity,
        unit: i.unit,
        productId: i.productId,
        aisle: i.aisle,
        origin: ItemOrigin.forgotten,
        mergeWithExisting: false,
      );
    }
    return target;
  }

  /// Retire un oublié de « Prochaines courses » (annulation du report).
  Future<void> unkeep(ShoppingItem forgotten) async {
    final target = (await lists(status: ListStatus.active)).where((l) => l.name == nextListName).firstOrNull;
    if (target == null) return;
    final copy = await findSameItem(target.id!, forgotten.label, productId: forgotten.productId);
    if (copy != null && copy.origin == ItemOrigin.forgotten) await repository.deleteItem(copy.id!);
  }

  /// Saisie manuelle ou correction d'un ticket existant.
  Future<void> updateReceipt(Receipt r) async {
    _validateReceipt(r.total, r.lines);
    final before = await spentIn(monthStart(r.date));
    await repository.updateReceipt(r);
    await _spendingChanged(r.date, before);
  }

  /// Après toute modification d'un ticket : dépense du mois recalculée,
  /// alerte si un seuil vient d'être franchi, jauge mise à jour.
  Future<void> _spendingChanged(DateTime date, double spentBefore) async {
    await checkBudget(date, spentBefore);
    _receiptsChanged.add(null);
  }

  /// Corrige (ou ajoute) une ligne mal lue. Si le total du ticket était la
  /// somme des lignes, il suit la correction.
  Future<void> saveLine(Receipt receipt, ReceiptLine line) async {
    if (line.label.trim().isEmpty) throw ArgumentError('Le libellé est obligatoire.');
    if (line.quantity <= 0) throw ArgumentError('Quantité invalide.');
    final fresh = await repository.receipt(receipt.id!);
    if (fresh == null) throw StateError('Ticket introuvable.');
    final wasSum = (fresh.total - fresh.linesTotal).abs() < 0.011;
    final before = await spentIn(monthStart(fresh.date));
    final enriched = await enrichLine(line);
    if (line.id == null) {
      await repository.insertReceiptLine(receipt.id!, enriched);
    } else {
      await repository.updateReceiptLine(enriched);
    }
    if (wasSum) await _syncTotal(receipt.id!);
    await _spendingChanged(fresh.date, before);
  }

  Future<void> removeLine(Receipt receipt, ReceiptLine line) async {
    final fresh = await repository.receipt(receipt.id!);
    if (fresh == null) return;
    final wasSum = (fresh.total - fresh.linesTotal).abs() < 0.011;
    final before = await spentIn(monthStart(fresh.date));
    await repository.deleteReceiptLine(line.id!);
    if (wasSum) await _syncTotal(receipt.id!);
    await _spendingChanged(fresh.date, before);
  }

  Future<void> _syncTotal(int receiptId) async {
    final r = await repository.receipt(receiptId);
    if (r != null) await repository.setReceiptTotal(receiptId, double.parse(r.linesTotal.toStringAsFixed(3)));
  }

  Future<void> setReceiptTotal(Receipt receipt, double total) async {
    if (total < 0) throw ArgumentError('Le total ne peut pas être négatif.');
    final before = await spentIn(monthStart(receipt.date));
    await repository.setReceiptTotal(receipt.id!, total);
    await _spendingChanged(receipt.date, before);
  }

  // -------------------------------------------------------------- Budget

  Future<List<Budget>> budgets() => repository.budgets(userId);
  Future<Budget?> budget(DateTime month) => repository.budget(userId, monthStart(month));

  Future<void> setBudget(DateTime month, double amount, {int alertThreshold = 80}) async {
    if (amount <= 0) throw ArgumentError('Le budget doit être positif.');
    if (alertThreshold < 1 || alertThreshold > 100) throw ArgumentError('Le seuil doit être entre 1 et 100 %.');
    await repository.upsertBudget(
      Budget(userId: userId, month: monthStart(month), amount: amount, alertThreshold: alertThreshold),
    );
    // Nouveau budget : les alertes du mois repartent de zéro.
    await repository.setSetting('budget_level_${monthKey(month)}', '0');
    await repository.setSetting('budget_forecast_${monthKey(month)}', '0');
  }

  Future<void> deleteBudget(Budget b) => repository.deleteBudget(b.id!);

  Future<double> spentIn(DateTime month) {
    final start = monthStart(month);
    return repository.spentBetween(userId, start, addMonths(start, 1));
  }

  Future<BudgetSnapshot> snapshot(DateTime month) async => BudgetSnapshot.compute(
        month: month,
        budget: await budget(month),
        spent: await spentIn(month),
        today: now,
      );

  /// Contrôle le budget du mois de [date] ; vibre quand le seuil puis le
  /// budget sont atteints (une seule fois par niveau et par mois), et
  /// avertit une fois si un dépassement est prévu.
  /// Recalcule la dépense du mois et déclenche l'alerte **une seule fois par
  /// franchissement** : seuil d'alerte (vibration courte, bannière orange),
  /// budget atteint ou dépassé (vibration longue, bannière rouge). Le niveau
  /// déjà signalé est mémorisé par mois ; s'il redescend (ticket supprimé),
  /// le prochain franchissement alerte de nouveau.
  Future<BudgetNotice> checkBudget([DateTime? date, double? spentBefore]) async {
    final month = monthStart(date ?? now);
    final s = await snapshot(month);
    final levelKey = 'budget_level_${monthKey(month)}';
    final forecastKey = 'budget_forecast_${monthKey(month)}';
    final previous = int.tryParse(await repository.setting(levelKey) ?? '') ?? 0;
    final level = s.level;
    final isNewLevel = level.index >= BudgetLevel.threshold.index && level.index > previous;
    final st = await settings();
    final vibrationEnabled = st.vibration && st.budgetAlerts;
    var vibrated = false;
    if (isNewLevel) {
      // Le niveau est mémorisé même alertes coupées : pas de rafale à la réactivation.
      await repository.setSetting(levelKey, '${level.index}');
      if (vibrationEnabled) vibrated = await vibrator.alert(level);
    } else if (level.index < previous) {
      await repository.setSetting(levelKey, '${level.index}');
    }
    var isNewForecast = false;
    if (s.forecastOverrun && (await repository.setting(forecastKey)) != '1') {
      isNewForecast = true;
      await repository.setSetting(forecastKey, '1');
    }
    final amount = s.amount;
    final notice = BudgetNotice(
      snapshot: s,
      isNewLevel: isNewLevel,
      isNewForecast: isNewForecast,
      previousRatio: spentBefore == null || amount == null || amount == 0 ? null : spentBefore / amount,
      vibrated: vibrated,
      vibrationEnabled: vibrationEnabled,
    );
    if (isNewLevel && st.budgetAlerts && isCurrentMonth(month)) _budgetAlerts.add(notice);
    return notice;
  }

  bool isCurrentMonth(DateTime month) => monthKey(month) == monthKey(now);

  // ------------------------------------------------------- Statistiques

  /// Dépenses des [count] derniers mois (le plus ancien en premier).
  Future<List<MonthSpending>> monthlySpending({int count = 6, DateTime? until}) async {
    final last = monthStart(until ?? now);
    return [
      for (var i = count - 1; i >= 0; i--)
        MonthSpending(addMonths(last, -i), await spentIn(addMonths(last, -i)), (await budget(addMonths(last, -i)))?.amount),
    ];
  }

  /// Dépenses par catégorie sur le mois (lignes des tickets).
  Future<Map<String, double>> categorySpending(DateTime month) async {
    final start = monthStart(month);
    final end = addMonths(start, 1);
    final lines = await repository.linesSince(userId, start);
    final out = <String, double>{};
    for (final x in lines) {
      if (!x.date.isBefore(end)) continue;
      final c = x.line.category ?? guessCategory(x.line.label);
      out[c] = (out[c] ?? 0) + x.line.price;
    }
    final sorted = out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Panier moyen (montant moyen d'un ticket) sur les [months] derniers mois.
  Future<double> averageBasket({int months = 3}) async {
    final r = await receipts(from: addMonths(monthStart(now), -(months - 1)));
    if (r.isEmpty) return 0;
    return r.fold<double>(0, (s, x) => s + x.total) / r.length;
  }

  /// Respect du budget : mois terminés dans le budget / mois avec budget.
  Future<(int respected, int total)> budgetRespect() async {
    final current = monthStart(now);
    var ok = 0;
    var n = 0;
    for (final b in await budgets()) {
      if (!b.month.isBefore(current)) continue;
      n++;
      if (await spentIn(b.month) <= b.amount) ok++;
    }
    return (ok, n);
  }

  // ------------------------------------------------ Hausses de prix (métier 2)

  String _priceKey(ReceiptLine l) => l.productId != null ? 'p:${l.productId}' : 'l:${labelKey(l.label)}';

  Future<List<PricePoint>> pricePoints({int days = 200}) async {
    final rows = await repository.linesSince(userId, now.subtract(Duration(days: days)));
    return [
      for (final x in rows)
        if (x.line.price > 0)
          PricePoint(
            key: _priceKey(x.line),
            label: x.line.label,
            date: x.date,
            unitPrice: x.line.unitPrice,
            storeName: x.storeName,
            receiptId: x.line.receiptId,
            quantity: x.line.quantity,
          ),
    ];
  }

  Future<List<PriceAlert>> priceAlerts() async => detectPriceIncreases(await pricePoints());

  /// Historique des prix payés pour une clé de produit (graphique).
  Future<List<PricePoint>> priceHistory(String key) async =>
      (await pricePoints(days: 365)).where((p) => p.key == key).toList()..sort((a, b) => a.date.compareTo(b.date));

  // ------------------------------------------------------- Open Prices (API)

  Future<String?> barcodeOf(ReceiptLine line) async {
    if (line.barcode != null && line.barcode!.isNotEmpty) return line.barcode;
    if (line.productId == null) return null;
    try {
      return (await products.byId(line.productId!))?.barcode;
    } catch (_) {
      return null;
    }
  }

  /// Compare le prix payé avec ceux signalés sur Open Prices.
  Future<PriceComparison> compareWithCommunity(ReceiptLine line) async {
    if (!(await settings()).openPrices) throw OpenPricesException('Open Prices est désactivé dans les réglages.');
    final code = await barcodeOf(line);
    if (code == null) {
      throw OpenPricesException('Pas de code-barres pour « ${line.label} » : ajoutez-le pour comparer.');
    }
    final cmp = comparePrices(line.unitPrice, currency, await prices.pricesFor(code));
    await _increment('price_comparisons');
    return cmp;
  }

  Future<void> _increment(String key) async {
    final n = int.tryParse(await repository.setting(key) ?? '') ?? 0;
    await repository.setSetting(key, '${n + 1}');
  }

  Future<int> _counter(String key) async => int.tryParse(await repository.setting(key) ?? '') ?? 0;

  // ------------------------------------------------- Comparateur de magasins

  /// Derniers prix payés par magasin pour chaque produit (90 jours).
  Future<Map<String, ProductPrices>> storePrices() async => latestPricesByStore(await pricePoints(days: 120), now: now);

  /// Panier type : produits achetés au moins 3 fois en 3 mois, coût estimé
  /// dans chaque magasin avec le dernier prix connu.
  Future<HabitualBasket> habitualBasket() async => buildHabitualBasket(await pricePoints(days: 120), now: now);

  /// Meilleur moment pour acheter : produits achetés au moins 3 fois sur un
  /// an (ceux qui ont 6 achats ou plus sont analysés), conclusions d'abord.
  Future<List<BestTimeInsight>> bestTimes() async {
    final byKey = <String, List<PricePoint>>{};
    for (final p in await pricePoints(days: 365)) {
      byKey.putIfAbsent(p.key, () => []).add(p);
    }
    final out = <BestTimeInsight>[];
    for (final e in byKey.entries) {
      if (e.value.length < 3) continue;
      final latest = e.value.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
      var name = displayLabel(latest.label);
      final id = e.key.startsWith('p:') ? int.tryParse(e.key.substring(2)) : null;
      if (id != null) {
        try {
          name = (await products.byId(id))?.name ?? name;
        } catch (_) {}
      }
      out.add(analyseBestTime(e.key, '« $name »', e.value));
    }
    int rank(BestTimeInsight i) => switch (i.status) {
          BestTimeStatus.ok => 0,
          BestTimeStatus.noDifference => 1,
          BestTimeStatus.notEnoughData => 2,
        };
    out.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.status == BestTimeStatus.ok ? b.saving.compareTo(a.saving) : b.purchases.compareTo(a.purchases);
    });
    return out;
  }

  /// Coût de la liste dans chaque magasin, d'après les prix déjà payés.
  Future<BasketComparison> compareListStores(int listId) async {
    final items = (await repository.items(listId)).where((i) => !i.checked).toList();
    return compareBasket(
      [for (final i in items) BasketEntry(label: i.label, productId: i.productId, quantity: _unitsOf(i))],
      await storePrices(),
    );
  }

  /// Quantité à multiplier par le prix unitaire : un nombre d'articles, pas
  /// des grammes ou des litres (le prix unitaire du ticket est par article).
  double _unitsOf(ShoppingItem i) {
    final q = i.quantity;
    final u = (i.unit ?? '').toLowerCase();
    if (q == null || q <= 0) return 1;
    return (u.isEmpty || u == 'pièce' || u == 'piece' || u == 'pc' || u == 'x') ? q : 1;
  }

  // --------------------------------------------------- Alertes intelligentes

  /// Ajoute le produit d'une alerte de prix à la liste en cours.
  Future<int> addAlertToList(PriceAlert a) async {
    String label = displayLabel(a.label);
    final id = a.productId;
    if (id != null) {
      try {
        label = (await products.byId(id))?.name ?? label;
      } catch (_) {}
    }
    // Déjà à acheter : on ne l'ajoute pas une seconde fois (renvoie 0).
    final list = await activeList();
    if (_findSame(await repository.items(list.id!), label, id) != null ||
        _findSame(await repository.items(list.id!), a.label, id) != null) {
      return 0;
    }
    return addRequests([ShoppingRequestData(label: label, productId: id)]);
  }


  // ------------------------------------------------------ Conseil et badges

  Future<Advice> advice([DateTime? month]) async {
    final m = month ?? now;
    final cats = await categorySpending(m);
    final alerts = await priceAlerts();
    return dailyAdvice(
      await snapshot(m),
      topCategory: cats.entries.isEmpty ? null : cats.entries.first,
      topAlert: alerts.isEmpty ? null : alerts.first,
    );
  }

  Future<List<Achievement>> badges() async {
    final months = await monthlySpending(count: 12);
    final lists = await repository.lists(userId, status: ListStatus.done);
    return computeBadges(
      budgetStreakMonths: budgetStreak([for (final x in months) (month: x.month, spent: x.spent, budget: x.budget)], now),
      perfectTrips: await _counter('perfect_trips'),
      receiptCount: (await receipts()).length,
      completedLists: lists.where((l) => l.itemCount > 0 && l.checkedCount == l.itemCount).length,
      priceComparisons: await _counter('price_comparisons'),
    );
  }

  Future<bool> hasOpenPricesAccount() async => (await tokens.read()) != null;

  Future<void> openPricesLogin(String username, String password) async {
    await tokens.write(await prices.login(username.trim(), password));
  }

  Future<void> openPricesLogout() => tokens.write(null);

  /// Partage facultatif d'un prix payé sur Open Prices.
  Future<void> sharePrice(Receipt receipt, ReceiptLine line) async {
    final token = await tokens.read();
    if (token == null) throw OpenPricesException('Connectez-vous à Open Food Facts dans les réglages.');
    final code = await barcodeOf(line);
    if (code == null) throw OpenPricesException('Pas de code-barres pour « ${line.label} ».');
    if (receipt.photo == null) {
      throw OpenPricesException('Open Prices demande une preuve : ajoutez la photo du ticket pour partager ce prix.');
    }
    await contributePrice(
      barcode: code,
      unitPrice: line.unitPrice,
      date: receipt.date,
      proofPhoto: receipt.photo!,
      proofType: 'RECEIPT',
      storeId: receipt.storeId,
    );
  }

  /// Contribution à Open Prices (facultative, compte Open Food Facts) :
  /// envoi de la preuve puis du prix. Renvoie le nombre de prix partagés
  /// depuis l'app (compteur affiché dans le remerciement).
  Future<int> contributePrice({
    required String barcode,
    required double unitPrice,
    required DateTime date,
    required String proofPhoto,
    String proofType = 'RECEIPT',
    int? storeId,
  }) async {
    final token = await tokens.read();
    if (token == null) throw OpenPricesException('Connectez-vous à Open Food Facts dans les réglages.');
    // Localisation OpenStreetMap du magasin (gestion 4) si elle est connue :
    // facultative pour Open Prices, mais id et type vont ensemble.
    final s = await store(storeId);
    final osmId = s?.osmType == null ? null : s?.osmId;
    final osmType = s?.osmId == null ? null : s?.osmType;
    final proofId = await prices.uploadProof(
      token: token,
      filePath: proofPhoto,
      type: proofType,
      currency: currency,
      date: date,
      locationOsmId: osmId,
      locationOsmType: osmType,
    );
    await prices.sharePrice(
      token: token,
      barcode: barcode,
      price: unitPrice,
      currency: currency,
      date: date,
      proofId: proofId,
      locationOsmId: osmId,
      locationOsmType: osmType,
    );
    await _increment('shared_prices');
    return sharedPriceCount();
  }

  Future<int> sharedPriceCount() async => int.tryParse(await repository.setting('shared_prices') ?? '') ?? 0;
}
