import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/cached_json_client.dart';
import 'package:panier_malin/features/shopping/data/demo_products.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/data/open_prices_api.dart';
import 'package:panier_malin/features/shopping/data/product_scan_repository.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/product_price.dart';
import 'package:panier_malin/features/shopping/services/product_scan_service.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/barcode_scanner_screen.dart';
import 'package:panier_malin/features/shopping/ui/product_sheet_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Faux serveur : répond selon l'URL, compte les appels, peut couper le réseau.
class FakeServer {
  bool online = true;
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];
  http.Response Function(Uri url)? onGet;

  late final client = MockClient.streaming((req, body) async {
    requests.add(req);
    final bytes = await body.toBytes();
    bodies.add(req is http.MultipartRequest ? '' : utf8.decode(bytes, allowMalformed: true));
    if (!online) throw const SocketException('pas de réseau');
    final res = _route(req, bytes);
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers);
  });

  http.Response _route(http.BaseRequest req, List<int> bytes) {
    final url = req.url;
    if (req.method == 'POST' && url.path == '/api/v1/proofs/upload') {
      return json({'id': 4242, 'type': 'PRICE_TAG'}, 201);
    }
    if (req.method == 'POST' && url.path == '/api/v1/prices') {
      return json({'id': 1}, 201);
    }
    final custom = onGet?.call(url);
    if (custom != null) return custom;
    if (url.host == 'world.openfoodfacts.org') {
      final code = url.pathSegments.last;
      if (code == '3017620422003') {
        return json(const DemoProducts().product(code), 200);
      }
      return json({'code': code, 'status': 0, 'status_verbose': 'product not found'}, 200);
    }
    if (url.path == '/api/v1/prices') {
      final code = url.queryParameters['product_code'];
      if (code != null) return json(const DemoProducts().prices(code) ?? _empty, 200);
      final tag = url.queryParameters['product__categories_tags__contains'];
      return json(const DemoProducts().categoryPrices(tag ?? '') ?? _empty, 200);
    }
    return http.Response('{}', 404);
  }

  /// Corps JSON en UTF-8, comme les vraies API.
  static http.Response json(Object? body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static const _empty = {'items': [], 'page': 1, 'pages': 0, 'size': 0, 'total': 0};
}

void main() {
  sqfliteFfiInit();

  group('Code-barres, verdict, alternative', () {
    test('clé de contrôle EAN-13 / EAN-8 / UPC', () {
      for (final c in ['3017620422003', '5449000000996', '8076800195057', '96385074', '036000291452']) {
        expect(isValidBarcode(c), isTrue, reason: c);
      }
      expect(isValidBarcode('3017620422004'), isFalse, reason: 'mauvaise clé');
      expect(isValidBarcode('1234'), isFalse);
      expect(isValidBarcode('30176204220a3'), isFalse);
    });

    test('verdict : « Tu paies 9 % de plus que la moyenne » / « Bon prix »', () {
      const mean = (12.9 + 13.2 + 12.8 + 13.4 + 12.95 + 12.95) / 6;
      final v = priceVerdict(myPrice: 14.2, communityMean: mean);
      expect(v.kind, VerdictKind.expensive);
      expect(v.text, 'Tu paies 9 % de plus que la moyenne');
      expect(priceVerdict(myPrice: 0.9, communityMean: 0.975).text, 'Bon prix : 8 % de moins que la moyenne');
      expect(priceVerdict(myPrice: 1.0, communityMean: 0.975).text, 'Bon prix (dans la moyenne)');
      expect(priceVerdict(myPrice: null, communityMean: 1).kind, VerdictKind.unknown);
      expect(priceVerdict(myPrice: 1, communityMean: null).kind, VerdictKind.unknown);
    });

    test('alternative : communauté (même catégorie), sinon mon historique dans un autre magasin', () {
      final cat = parseOpenPrices(const DemoProducts().categoryPrices('en:hazelnut-spreads'));
      final a = communityAlternative(code: DemoProducts.nutella, reference: 14.2, categoryPrices: cat)!;
      expect(a.name, contains('Pâte à tartiner'));
      expect(a.price, closeTo(9.967, 0.001));
      expect(a.priceCount, 3);
      expect(communityAlternative(code: DemoProducts.nutella, reference: 9.5, categoryPrices: cat), isNull,
          reason: 'pas assez moins cher');

      final h = [
        PricePoint(date: DateTime(2026, 9, 1), unitPrice: 12.5, store: 'Monoprix'),
        PricePoint(date: DateTime(2026, 10, 1), unitPrice: 14.2, store: 'Carrefour'),
      ];
      final b = historyAlternative(name: 'Nutella', history: h)!;
      expect(b.where, 'Monoprix');
      expect(b.source, AlternativeSource.myHistory);
    });
  });

  group('Repository (API vérifiées, cache, hors ligne)', () {
    late Database db;
    late FakeServer server;
    late ProductScanRepository repo;
    var now = DateTime(2026, 11, 25, 10);

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      server = FakeServer();
      now = DateTime(2026, 11, 25, 10);
      repo = ProductScanRepository(
        client: CachedJsonClient(client: server.client, cache: ShoppingApiCache(db), clock: () => now),
      );
    });
    tearDown(() => db.close());

    test('URL, champs et User-Agent ; fiche Open Food Facts ; produit inconnu', () async {
      final f = await repo.product(DemoProducts.nutella);
      final p = f.value!;
      expect(p.name, 'Nutella');
      expect(p.brand, 'Ferrero');
      expect(p.nutriscore, 'e');
      expect(p.allergens, ['en:milk', 'en:nuts', 'en:soybeans']);
      expect(p.specificCategory, 'en:hazelnut-spreads');
      final url = server.requests.single.url;
      expect(url.toString(), startsWith('https://world.openfoodfacts.org/api/v2/product/3017620422003?fields='));
      expect(url.queryParameters['fields'], contains('nutriscore_grade'));
      expect(server.requests.single.headers['User-Agent'], startsWith('PanierMalin/1.0'));

      expect((await repo.product('0000000000017')).value, isNull, reason: 'status 0 : inconnu');

      // Données réelles : « en:none » = pas d'allergène ; nom principal avant le nom _fr.
      final water = OffProduct.fromResponse('3274080005003', {
        'status': 1,
        'product': {'product_name': 'Cristaline', 'product_name_fr': 'isabelle', 'allergens_tags': ['en:none']},
      })!;
      expect(water.allergens, isEmpty);
      expect(water.name, 'Cristaline');
    });

    test('prix : filtre product_code, tri par date ; catégorie : product__categories_tags__contains + devise', () async {
      final prices = await repo.prices(DemoProducts.nutella);
      expect(prices.value, hasLength(7));
      expect(prices.value.first.productName, 'Nutella');
      var url = server.requests.last.url;
      expect(url.host, 'prices.openfoodfacts.org');
      expect(url.path, '/api/v1/prices');
      expect(url.queryParameters, containsPair('product_code', '3017620422003'));
      expect(url.queryParameters, containsPair('order_by', '-date'));

      await repo.categoryPrices('en:hazelnut-spreads', 'TND');
      url = server.requests.last.url;
      expect(url.queryParameters, containsPair('product__categories_tags__contains', 'en:hazelnut-spreads'));
      expect(url.queryParameters, containsPair('currency', 'TND'));
      expect(url.queryParameters, containsPair('order_by', 'price'));
    });

    test('cache : pas de nouvel appel tant qu\'il est frais ; hors ligne : dernier résultat « hors ligne »', () async {
      await repo.prices(DemoProducts.nutella);
      await repo.prices(DemoProducts.nutella);
      expect(server.requests, hasLength(1), reason: 'réponse fraîche servie par le cache');

      now = now.add(const Duration(days: 2)); // cache périmé
      server.online = false;
      final f = await repo.prices(DemoProducts.nutella);
      expect(f.offline, isTrue);
      expect(f.value, hasLength(7));
      expect(f.fetchedAt, DateTime(2026, 11, 25, 10), reason: 'date de la dernière synchro');

      await expectLater(repo.prices(DemoProducts.coca), throwsA(isA<ApiUnreachable>()), reason: 'rien en cache');
    });

    test('délai d\'attente, limite de requêtes (503)', () async {
      final slow = CachedJsonClient(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(ProductScanRepository(client: slow).product('3017620422003'), throwsA(isA<ApiUnreachable>()));

      server.onGet = (_) => http.Response('busy', 503);
      await expectLater(
        repo.product(DemoProducts.nutella),
        throwsA(isA<ApiHttpError>().having((e) => '$e', 'message', contains('limite'))),
      );
    });

    test('mode démo : aucune requête', () async {
      final f = await repo.product(DemoProducts.spaghetti, demoMode: true);
      expect(f.demo, isTrue);
      expect(f.value!.name, 'Spaghetti n°5');
      expect((await repo.prices(DemoProducts.coca, demoMode: true)).value, hasLength(4));
      expect(server.requests, isEmpty);
    });
  });

  group('Fiche produit (service)', () {
    late Database db;
    late FakeServer server;
    late ShoppingService shopping;
    late ProductScanService scan;
    late MemoryTokenStore tokens;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      server = FakeServer();
      tokens = MemoryTokenStore();
      shopping = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: tokens,
        api: OpenPricesApi(client: server.client),
        clock: () => DateTime(2026, 11, 25, 10),
      );
      await seedDemoShoppingIfEmpty(shopping.repository, 1, DateTime(2026, 11, 25, 10));
      scan = ShoppingModule.createProductScan(shopping, client: server.client);
    });
    tearDown(() => db.close());

    test('démo Nutella : historique (3 achats), dernier prix, moyenne, verdict rouge, alternative', () async {
      final s = await scan.lookup(DemoProducts.nutella);
      expect(s.demo, isTrue);
      expect(s.history.map((p) => p.unitPrice), [13.9, 13.5, 14.2]);
      expect(s.myLast!.store, 'Carrefour La Marsa');
      expect(s.community, hasLength(6), reason: 'prix en DT seulement');
      expect(s.otherCurrencyCount, 1);
      expect(s.verdict.text, 'Tu paies 9 % de plus que la moyenne');
      expect(s.alternative!.source, AlternativeSource.community);
      expect(server.requests, isEmpty, reason: 'mode démo : sans réseau');
    });

    test('démo Coca-Cola : bon prix ; démo Spaghetti : aucun prix en DT', () async {
      final coca = await scan.lookup(DemoProducts.coca);
      expect(coca.myLast!.unitPrice, 0.9);
      expect(coca.verdict.kind, VerdictKind.good);
      final spag = await scan.lookup(DemoProducts.spaghetti);
      expect(spag.community, isEmpty);
      expect(spag.otherCurrencyCount, 2);
      expect(spag.verdict.kind, VerdictKind.unknown);
    });

    test('hors ligne puis resynchronisation ; produit inconnu ; comparaison désactivée', () async {
      await shopping.saveSettings((await shopping.settings()).copyWith(demoProducts: false));
      server.online = false;
      final off = await scan.lookup(DemoProducts.nutella);
      expect(off.networkError, contains('injoignable'));
      expect(off.history, hasLength(3), reason: 'mon historique reste disponible');
      expect(await scan.pendingCodes(), {DemoProducts.nutella});

      server.online = true;
      expect(await scan.resyncPending(), [DemoProducts.nutella]);
      expect(await scan.pendingCodes(), isEmpty);
      final on = await scan.lookup(DemoProducts.nutella);
      expect(on.offline, isFalse);
      expect(on.verdict.kind, VerdictKind.expensive);

      final unknown = await scan.lookup('4006381333931');
      expect(unknown.productUnknown, isTrue);
      expect(unknown.community, isEmpty);

      int pricesCalls() => server.requests.where((r) => r.url.host == 'prices.openfoodfacts.org').length;
      final before = pricesCalls();
      await shopping.saveSettings((await shopping.settings()).copyWith(openPrices: false));
      final noCompare = await scan.lookup(DemoProducts.nutella);
      expect(noCompare.comparisonEnabled, isFalse);
      expect(noCompare.community, isEmpty);
      expect(noCompare.verdict.text, contains('désactivée'));
      await scan.lookup('4006381333931');
      expect(pricesCalls(), before, reason: 'plus aucun appel à Open Prices une fois désactivé');
    });

    test('ajouter à ma liste, surveiller', () async {
      final s = await scan.lookup(DemoProducts.nutella);
      final listName = await scan.addToList(s.listLabel);
      expect(listName, 'Courses de la semaine');
      expect(await scan.toggleWatch(s), isTrue);
      expect((await scan.watched()).single.mean, closeTo(13.033, 0.001));
      expect((await scan.lookup(DemoProducts.nutella)).watched, isTrue);
      expect(await scan.toggleWatch(s), isFalse);
      expect(await scan.watched(), isEmpty);
    });

    test('contribuer : interrupteur respecté, preuve envoyée puis prix avec proof_id, compteur', () async {
      final photo = File('${Directory.systemTemp.path}/preuve_test.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
      Future<int> send() => scan.contribute(
            code: DemoProducts.nutella,
            price: 14.2,
            date: DateTime(2026, 11, 25),
            proofPhoto: photo.path,
            proofType: 'PRICE_TAG',
          );
      await expectLater(send(), throwsA(isA<OpenPricesException>()), reason: 'partage désactivé');
      await shopping.saveSettings((await shopping.settings()).copyWith(sharePrices: true));
      await expectLater(send(), throwsA(isA<OpenPricesException>()), reason: 'pas connecté');

      tokens.token = 'moi__Uabc';
      expect(await send(), 1);
      final upload = server.requests.firstWhere((r) => r.url.path == '/api/v1/proofs/upload') as http.MultipartRequest;
      expect(upload.headers['Authorization'], 'Bearer moi__Uabc');
      expect(upload.fields, containsPair('type', 'PRICE_TAG'));
      expect(upload.fields, containsPair('currency', 'TND'));
      expect(upload.files.single.field, 'file');
      final i = server.requests.indexWhere((r) => r.url.path == '/api/v1/prices' && r.method == 'POST');
      final body = jsonDecode(server.bodies[i]) as Map;
      expect(body['proof_id'], 4242);
      expect(body['product_code'], DemoProducts.nutella);
      expect(body['currency'], 'TND');
      expect(body.containsKey('location_osm_id'), isFalse, reason: 'pas de magasin OSM : localisation omise');
      expect(await send(), 2);
    });
  });

  testWidgets('écran fiche produit (démo Nutella) + saisie manuelle du code', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Database db;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final shopping = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
      );
      await seedDemoShoppingIfEmpty(shopping.repository, 1, DateTime.now());
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(shopping),
        ),
        shopping: shopping,
        productScan: ShoppingModule.createProductScan(shopping, client: FakeServer().client),
        home: const ProductSheetScreen(code: DemoProducts.nutella),
      );
    });
    Future<void> go() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.runAsync(() => tester.pumpWidget(app));
    await go();
    expect(find.text('Nutella'), findsOneWidget);
    expect(find.text('Nutri-Score E'), findsOneWidget);
    expect(find.text('Lait'), findsOneWidget);
    expect(find.text('Mode démo · prix fictifs'), findsOneWidget);
    expect(find.text('Tu paies 9 % de plus que la moyenne'), findsOneWidget);
    expect(find.text('6 prix comparés en DT (Open Prices)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Alternative moins chère (même catégorie)'), 200);
    expect(find.textContaining('Évolution de mon prix (3 achats)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Surveiller ce produit'), 200);
    expect(find.text('Contribuer mon prix'), findsNothing, reason: '« Partager mes prix » désactivé');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter à ma liste'));
    await go();
    expect(find.textContaining('ajouté à « Courses de la semaine »'), findsOneWidget);

    // Saisie manuelle : clé de contrôle vérifiée.
    final ctx = tester.element(find.byType(ProductSheetScreen));
    final result = showDialog<String>(context: ctx, builder: (_) => const ManualBarcodeDialog());
    await go();
    await tester.enterText(find.byType(TextField), '3017620422004');
    await tester.tap(find.text('Valider'));
    await go();
    expect(find.textContaining('Clé de contrôle incorrecte'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '3017620422003');
    await tester.tap(find.text('Valider'));
    await go();
    expect(await result, '3017620422003');
    await tester.runAsync(db.close);
  });
}
