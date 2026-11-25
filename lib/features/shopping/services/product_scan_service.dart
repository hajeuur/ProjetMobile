import 'dart:convert';

import '../data/cached_json_client.dart';
import '../data/open_prices_api.dart';
import '../data/product_scan_repository.dart';
import '../logic/product_price.dart';
import '../logic/text_similarity.dart';
import '../models/dates.dart';
import '../models/shopping_list.dart';
import 'shopping_service.dart';

/// Fiche produit affichée après un scan.
class ProductSheet {
  const ProductSheet({
    required this.code,
    this.product,
    this.productUnknown = false,
    this.history = const [],
    this.community = const [],
    this.otherCurrencyCount = 0,
    this.verdict = const PriceVerdict(VerdictKind.unknown, ''),
    this.alternative,
    this.comparisonEnabled = true,
    this.offline = false,
    this.fetchedAt,
    this.demo = false,
    this.networkError,
    this.watched = false,
  });

  final String code;
  final OffProduct? product;

  /// Open Food Facts ne connaît pas ce code.
  final bool productUnknown;

  /// Mes achats de ce produit (le plus ancien en premier).
  final List<PricePoint> history;

  /// Prix de la communauté en DT.
  final List<OpenPrice> community;

  /// Prix signalés dans d'autres devises (non comparables).
  final int otherCurrencyCount;
  final PriceVerdict verdict;
  final CheaperAlternative? alternative;

  /// Interrupteur « Comparer avec Open Prices ».
  final bool comparisonEnabled;

  /// Au moins une donnée vient du cache faute de réseau.
  final bool offline;
  final DateTime? fetchedAt;
  final bool demo;

  /// Pas de réseau et rien en cache (ou serveur en erreur).
  final String? networkError;
  final bool watched;

  PricePoint? get myLast => history.isEmpty ? null : history.last;
  double? get communityMean => meanOf(community.map((p) => p.price));
  String get name => product?.name ?? (history.isNotEmpty ? 'Produit $code' : 'Code $code');
  String get listLabel => [product?.name ?? 'Produit $code', if (product?.brand != null) product!.brand!].join(' ');
}

/// Produit surveillé (écran Prix).
class WatchedProduct {
  const WatchedProduct({required this.code, required this.name, this.mean, required this.since});
  final String code;
  final String name;

  /// Prix moyen de la communauté au moment où on l'a surveillé.
  final double? mean;
  final DateTime since;

  Map<String, Object?> toJson() => {'code': code, 'name': name, 'mean': mean, 'since': since.toIso8601String()};
  static WatchedProduct fromJson(Map<String, dynamic> j) => WatchedProduct(
        code: j['code'] as String,
        name: j['name'] as String,
        mean: (j['mean'] as num?)?.toDouble(),
        since: DateTime.parse(j['since'] as String),
      );
}

/// Scan de code-barres : fiche Open Food Facts, prix Open Prices, mon
/// historique, verdict, alternative, liste, surveillance, contribution.
class ProductScanService {
  ProductScanService(this.shopping, this.repository);

  final ShoppingService shopping;
  final ProductScanRepository repository;

  static const _pendingKey = 'scan_pending';
  static const _watchKey = 'watched_products';

  Future<ProductSheet> lookup(String code) async {
    final c = code.trim();
    final settings = await shopping.settings();
    final demoMode = settings.demoProducts;
    var offline = false;
    var demo = false;
    DateTime? fetchedAt;
    String? networkError;
    void track(Fetched<Object?> f) {
      offline |= f.offline;
      demo |= f.demo;
      if (f.fetchedAt != null && (fetchedAt == null || f.fetchedAt!.isBefore(fetchedAt!))) fetchedAt = f.fetchedAt;
    }

    // 1. Fiche produit (Open Food Facts).
    OffProduct? product;
    var unknown = false;
    try {
      final f = await repository.product(c, demoMode: demoMode);
      track(f);
      product = f.value;
      unknown = product == null;
    } on ApiUnreachable catch (e) {
      networkError = '$e';
    } on ApiHttpError catch (e) {
      networkError = '$e';
    }

    // 2. Mon historique (tickets) : même code-barres, ou même nom de produit.
    final history = await _history(c, product?.name);

    // 3. Prix de la communauté (Open Prices), si la comparaison est activée.
    var community = <OpenPrice>[];
    var others = 0;
    CheaperAlternative? alternative;
    if (settings.openPrices && networkError == null) {
      try {
        final f = await repository.prices(c, demoMode: demoMode);
        track(f);
        community = [for (final p in f.value) if (p.currency.toUpperCase() == ShoppingService.currency) p];
        others = f.value.length - community.length;
      } on ApiUnreachable catch (e) {
        networkError = '$e';
      } on ApiHttpError catch (e) {
        networkError = '$e';
      }
      // 4. Alternative moins chère de la même catégorie.
      final tag = product?.specificCategory;
      final reference = history.isNotEmpty ? history.last.unitPrice : meanOf(community.map((p) => p.price));
      if (tag != null && networkError == null) {
        try {
          final f = await repository.categoryPrices(tag, ShoppingService.currency, demoMode: demoMode);
          track(f);
          alternative = communityAlternative(code: c, reference: reference, categoryPrices: f.value);
        } catch (_) {
          // Pas d'alternative communautaire : on tente l'historique.
        }
      }
    }
    alternative ??= historyAlternative(name: product?.name ?? 'ce produit', history: history);

    final mean = meanOf(community.map((p) => p.price));
    final verdict = !settings.openPrices
        ? const PriceVerdict(VerdictKind.unknown, 'Comparaison désactivée dans les Réglages.')
        : priceVerdict(myPrice: history.isEmpty ? null : history.last.unitPrice, communityMean: mean);

    // Hors ligne : on resynchronisera ce code dès que le réseau revient.
    await _setPending(c, offline || networkError != null);

    return ProductSheet(
      code: c,
      product: product,
      productUnknown: unknown,
      history: history,
      community: community,
      otherCurrencyCount: others,
      verdict: verdict,
      alternative: alternative,
      comparisonEnabled: settings.openPrices,
      offline: offline,
      fetchedAt: fetchedAt,
      demo: demo,
      networkError: networkError,
      watched: (await watched()).any((w) => w.code == c),
    );
  }

  Future<List<PricePoint>> _history(String code, String? name) async {
    final lines = await shopping.repository.linesSince(shopping.userId, DateTime(2000));
    final out = <PricePoint>[];
    for (final l in lines) {
      if (l.line.price <= 0) continue;
      final barcode = await shopping.barcodeOf(l.line);
      final same = barcode != null
          ? barcode == code
          : name != null && labelSimilarity(name, l.line.label) >= 0.9;
      if (same) out.add(PricePoint(date: l.date, unitPrice: l.line.unitPrice, store: l.storeName));
    }
    return out;
  }

  // ------------------------------------------------- Resynchronisation

  Future<Set<String>> pendingCodes() async {
    final raw = await shopping.repository.setting(_pendingKey);
    return raw == null || raw.isEmpty ? <String>{} : raw.split(',').toSet();
  }

  Future<void> _setPending(String code, bool pending) async {
    final set = await pendingCodes();
    final changed = pending ? set.add(code) : set.remove(code);
    if (changed) await shopping.repository.setSetting(_pendingKey, set.join(','));
  }

  /// Relance les codes consultés hors ligne. Renvoie ceux qui sont à jour.
  Future<List<String>> resyncPending() async {
    final done = <String>[];
    for (final code in await pendingCodes()) {
      final s = await lookup(code);
      if (!s.offline && s.networkError == null) done.add(code);
    }
    return done;
  }

  // ------------------------------------------------------------ Liste

  /// Ajoute à la liste en cours (créée si besoin). Renvoie son nom.
  Future<String> addToList(String label) async {
    var id = await shopping.currentListId();
    if (id == null) {
      final active = await shopping.lists(status: ListStatus.active);
      id = active.where((l) => l.name != ShoppingService.nextListName).firstOrNull?.id ??
          await shopping.createList('Liste du ${formatDate(shopping.now)}');
    }
    await shopping.addItem(id, label: label);
    return (await shopping.list(id))!.name;
  }

  // ------------------------------------------------------- Surveillance

  Future<List<WatchedProduct>> watched() async {
    final raw = await shopping.repository.setting(_watchKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) WatchedProduct.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  /// Surveille ou arrête de surveiller. Renvoie le nouvel état.
  Future<bool> toggleWatch(ProductSheet s) async {
    final list = await watched();
    final i = list.indexWhere((w) => w.code == s.code);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.add(WatchedProduct(code: s.code, name: s.product?.name ?? s.name, mean: s.communityMean, since: shopping.now));
    }
    await shopping.repository.setSetting(_watchKey, jsonEncode([for (final w in list) w.toJson()]));
    return i < 0;
  }

  // ------------------------------------------------------- Contribution

  /// « Contribuer mon prix » : preuve (photo du ticket ou de l'étiquette)
  /// puis prix. Renvoie le nombre de prix partagés depuis l'app.
  Future<int> contribute({
    required String code,
    required double price,
    required DateTime date,
    required String proofPhoto,
    required String proofType,
  }) async {
    final s = await shopping.settings();
    if (!s.sharePrices) throw OpenPricesException('Le partage des prix est désactivé dans les Réglages.');
    return shopping.contributePrice(
      barcode: code,
      unitPrice: price,
      date: date,
      proofPhoto: proofPhoto,
      proofType: proofType,
    );
  }
}
