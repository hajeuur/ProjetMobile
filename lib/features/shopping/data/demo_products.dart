/// Mode démo : trois codes-barres préchargés avec des réponses au format
/// exact des API (vérifié sur les API réelles), pour que la soutenance
/// fonctionne sans réseau.
///
/// - **Nutella 400 g** : prix communautaires en DT, payé plus cher que la
///   moyenne → verdict rouge, alternative moins chère dans la catégorie.
/// - **Coca-Cola 33 cl** : payé sous la moyenne → « Bon prix ».
/// - **Spaghetti n°5 Barilla** : uniquement des prix en euros → « aucun prix
///   communautaire en DT ».
///
/// Les fiches produits reprennent les informations publiques d'Open Food
/// Facts ; les **prix sont fictifs** (données de démonstration, signalées à
/// l'écran). Les deux produits « alternative » portent des codes fictifs.
library;

class DemoProducts {
  const DemoProducts();

  static const nutella = '3017620422003';
  static const coca = '5449000000996';
  static const spaghetti = '8076800195057';

  static const codes = [nutella, coca, spaghetti];

  /// Noms courts pour les raccourcis du scanner.
  static const labels = {nutella: 'Nutella', coca: 'Coca-Cola', spaghetti: 'Spaghetti'};

  bool has(String code) => codes.contains(code);

  /// Réponse de `GET /api/v2/product/{code}` (Open Food Facts).
  Map<String, dynamic>? product(String code) => switch (code) {
        nutella => _off(code, {
            'product_name': 'Nutella',
            'brands': 'Ferrero, Nutella',
            'quantity': '400 g',
            'image_front_small_url': 'https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.200.jpg',
            'nutriscore_grade': 'e',
            'allergens_tags': ['en:milk', 'en:nuts', 'en:soybeans'],
            'categories_tags': ['en:spreads', 'en:sweet-spreads', 'en:hazelnut-spreads'],
          }),
        coca => _off(code, {
            'product_name': 'Coca-Cola',
            'brands': 'Coca-Cola',
            'quantity': '330 ml',
            'nutriscore_grade': 'e',
            'allergens_tags': <String>[],
            'categories_tags': ['en:beverages', 'en:carbonated-drinks', 'en:sodas', 'en:colas'],
          }),
        spaghetti => _off(code, {
            'product_name': 'Spaghetti n°5',
            'brands': 'Barilla',
            'quantity': '500 g',
            'nutriscore_grade': 'a',
            'allergens_tags': ['en:gluten'],
            'categories_tags': ['en:cereals-and-their-products', 'en:pastas', 'en:spaghetti'],
          }),
        _ => null,
      };

  /// Réponse de `GET /api/v1/prices?product_code=…` (Open Prices).
  Map<String, dynamic>? prices(String code) => switch (code) {
        nutella => _page([
            _price(nutella, 'Nutella', 12.900, 'TND', '2026-11-10', 'Carrefour Lac 2'),
            _price(nutella, 'Nutella', 13.200, 'TND', '2026-11-03', 'Monoprix Menzah'),
            _price(nutella, 'Nutella', 12.800, 'TND', '2026-10-27', 'Géant Tunis City'),
            _price(nutella, 'Nutella', 13.400, 'TND', '2026-10-20', 'Aziza'),
            _price(nutella, 'Nutella', 12.950, 'TND', '2026-10-12', 'MG Maxi'),
            _price(nutella, 'Nutella', 12.950, 'TND', '2026-10-02', 'Carrefour Market'),
            _price(nutella, 'Nutella', 4.050, 'EUR', '2026-11-05', 'Carrefour'),
          ]),
        coca => _page([
            _price(coca, 'Coca-Cola', 0.950, 'TND', '2026-11-12', 'Aziza'),
            _price(coca, 'Coca-Cola', 1.000, 'TND', '2026-11-01', 'Monoprix Menzah'),
            _price(coca, 'Coca-Cola', 0.900, 'TND', '2026-10-25', 'Carrefour Lac 2'),
            _price(coca, 'Coca-Cola', 1.050, 'TND', '2026-10-14', 'Épicerie du quartier'),
          ]),
        spaghetti => _page([
            _price(spaghetti, 'Spaghetti n°5', 1.290, 'EUR', '2026-11-08', 'Carrefour'),
            _price(spaghetti, 'Spaghetti n°5', 1.350, 'EUR', '2026-10-30', 'Lidl'),
          ]),
        _ => null,
      };

  /// Réponse de `GET /api/v1/prices?product__categories_tags__contains=…`.
  Map<String, dynamic>? categoryPrices(String tag) => switch (tag) {
        'en:hazelnut-spreads' => _page([
            _price('6190000000017', 'Pâte à tartiner cacao-noisettes 400 g (démo)', 9.800, 'TND', '2026-11-09', 'Aziza'),
            _price('6190000000017', 'Pâte à tartiner cacao-noisettes 400 g (démo)', 9.900, 'TND', '2026-11-02', 'MG Maxi'),
            _price('6190000000017', 'Pâte à tartiner cacao-noisettes 400 g (démo)', 10.200, 'TND', '2026-10-21', 'Monoprix'),
            _price(nutella, 'Nutella', 12.800, 'TND', '2026-10-27', 'Géant Tunis City'),
          ]),
        'en:colas' => _page([
            _price('6190000000024', 'Cola 33 cl (démo)', 0.700, 'TND', '2026-11-04', 'Aziza'),
            _price('6190000000024', 'Cola 33 cl (démo)', 0.750, 'TND', '2026-10-18', 'MG Maxi'),
            _price(coca, 'Coca-Cola', 0.900, 'TND', '2026-10-25', 'Carrefour Lac 2'),
          ]),
        _ => null,
      };

  static Map<String, dynamic> _off(String code, Map<String, dynamic> product) =>
      {'code': code, 'product': product, 'status': 1, 'status_verbose': 'product found'};

  static Map<String, dynamic> _page(List<Map<String, dynamic>> items) =>
      {'items': items, 'page': 1, 'pages': 1, 'size': items.length, 'total': items.length};

  static Map<String, dynamic> _price(String code, String name, double price, String currency, String date, String shop) => {
        'product_code': code,
        'product_name': null,
        'product': {'code': code, 'product_name': name},
        'price': price,
        'currency': currency,
        'date': date,
        'location': {'osm_name': shop},
      };
}
