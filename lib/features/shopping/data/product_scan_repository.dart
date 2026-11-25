import 'cached_json_client.dart';
import 'demo_products.dart';
import 'open_prices_api.dart';

/// Fiche produit Open Food Facts (champs demandés avec `fields=`).
class OffProduct {
  const OffProduct({
    required this.code,
    required this.name,
    this.brands,
    this.quantity,
    this.imageUrl,
    this.nutriscore,
    this.allergens = const [],
    this.categories = const [],
  });

  final String code;
  final String name;
  final String? brands;
  final String? quantity;
  final String? imageUrl;

  /// a à e (null : non calculé, « unknown », « not-applicable »).
  final String? nutriscore;

  /// Étiquettes `en:milk`, `en:nuts`…
  final List<String> allergens;

  /// Du plus général au plus précis : `en:spreads` … `en:hazelnut-spreads`.
  final List<String> categories;

  /// Marque principale (« Ferrero, Nutella » → « Ferrero »).
  String? get brand => brands?.split(',').first.trim();

  /// Catégorie la plus précise en anglais (pour chercher une alternative).
  String? get specificCategory => categories.lastWhere((c) => c.startsWith('en:'), orElse: () => '').nullIfEmpty;

  static OffProduct? fromResponse(String code, Object? json) {
    if (json is! Map || json['status'] != 1 || json['product'] is! Map) return null;
    final p = json['product'] as Map;
    String? str(String k) {
      final v = p[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    List<String> tags(String k) => [for (final t in (p[k] is List ? p[k] as List : const [])) if (t is String) t];
    final grade = str('nutriscore_grade');
    return OffProduct(
      code: code,
      // Nom dans la langue principale du produit ; le champ _fr est parfois mal rempli.
      name: str('product_name') ?? str('product_name_fr') ?? 'Produit $code',
      brands: str('brands'),
      quantity: str('quantity'),
      imageUrl: str('image_front_small_url') ?? str('image_front_url'),
      nutriscore: grade != null && RegExp(r'^[a-e]$').hasMatch(grade) ? grade : null,
      // « en:none » : aucun allergène déclaré.
      allergens: [for (final a in tags('allergens_tags')) if (a != 'en:none') a],
      categories: tags('categories_tags'),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Résultat d'un appel : valeur, et d'où elle vient.
class Fetched<T> {
  const Fetched(this.value, {this.offline = false, this.fetchedAt, this.demo = false});
  final T value;

  /// Réseau absent : dernière réponse connue (« données hors ligne »).
  final bool offline;
  final DateTime? fetchedAt;

  /// Réponse du mode démo.
  final bool demo;
}

/// Accès aux données produits et prix (Open Food Facts + Open Prices),
/// avec cache local, délai d'attente et mode démo.
///
/// Points d'accès vérifiés (documentation et code source officiels) :
/// - `GET https://world.openfoodfacts.org/api/v2/product/{code}?fields=…`
///   → `{code, product, status: 1|0, status_verbose}` ;
/// - `GET https://prices.openfoodfacts.org/api/v1/prices?product_code=…&order_by=-date&size=…`
///   → `{items, page, pages, size, total}` ;
/// - même point avec `product__categories_tags__contains=…&currency=…&order_by=price`.
class ProductScanRepository {
  ProductScanRepository({required this.client, this.demo = const DemoProducts()});

  static const offBase = 'https://world.openfoodfacts.org/api/v2';
  static const offFields =
      'product_name,product_name_fr,brands,quantity,image_front_small_url,image_front_url,nutriscore_grade,'
      'allergens_tags,categories_tags';

  final CachedJsonClient client;
  final DemoProducts demo;

  /// Fiche produit, ou null si le code est inconnu d'Open Food Facts.
  Future<Fetched<OffProduct?>> product(String code, {bool demoMode = false}) async {
    if (demoMode && demo.has(code)) return Fetched(OffProduct.fromResponse(code, demo.product(code)), demo: true);
    final r = await client.get(
      Uri.parse('$offBase/product/$code?fields=$offFields'),
      service: 'Open Food Facts',
      maxAge: const Duration(days: 7), // fiche produit : change rarement
    );
    final p = r.statusCode == 404 ? null : OffProduct.fromResponse(code, r.json);
    return Fetched(p, offline: r.offline, fetchedAt: r.fetchedAt);
  }

  /// Prix signalés par la communauté pour ce code-barres (les plus récents).
  Future<Fetched<List<OpenPrice>>> prices(String code, {bool demoMode = false}) async {
    if (demoMode && demo.has(code)) return Fetched(parseOpenPrices(demo.prices(code)), demo: true);
    final r = await client.get(
      Uri.parse('${OpenPricesApi.base}/prices?product_code=$code&order_by=-date&size=100'),
      service: 'Open Prices',
    );
    return Fetched(parseOpenPrices(r.json), offline: r.offline, fetchedAt: r.fetchedAt);
  }

  /// Prix les plus bas d'une catégorie, dans une devise (alternative).
  Future<Fetched<List<OpenPrice>>> categoryPrices(String tag, String currency, {bool demoMode = false}) async {
    if (demoMode) {
      final d = demo.categoryPrices(tag);
      if (d != null) return Fetched(parseOpenPrices(d), demo: true);
    }
    final r = await client.get(
      Uri.parse('${OpenPricesApi.base}/prices'
          '?product__categories_tags__contains=${Uri.encodeQueryComponent(tag)}'
          '&currency=$currency&order_by=price&size=50'),
      service: 'Open Prices',
      maxAge: const Duration(days: 1),
    );
    return Fetched(parseOpenPrices(r.json), offline: r.offline, fetchedAt: r.fetchedAt);
  }
}
