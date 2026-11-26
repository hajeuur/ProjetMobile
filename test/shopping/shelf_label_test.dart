import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/live_receipt_parser.dart';
import 'package:panier_malin/features/shopping/logic/product_price.dart' show PricePoint;
import 'package:panier_malin/features/shopping/logic/shelf_label_parser.dart';
import 'package:panier_malin/features/shopping/models/live_cart.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/shelf_label_scan_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fausse caméra : on lui fait « voir » une étiquette.
class FakeCamera implements LiveReceiptCamera {
  LiveCameraException? openError;
  final _frames = StreamController<LiveFrame>.broadcast();
  bool closed = false;

  @override
  Future<void> open() async {
    if (openError != null) throw openError!;
  }

  @override
  Widget buildPreview(Widget overlay) => ColoredBox(color: Colors.black, child: overlay);
  @override
  Stream<LiveFrame> frames() => _frames.stream;
  void show(List<LiveOcrRow> rows, {double brightness = 0.6}) => _frames.add(LiveFrame(rows: rows, brightness: brightness));
  @override
  Future<void> setTorch(bool on) async {}
  @override
  Future<String?> takePhoto() async => null;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> close() async => closed = true;
}

ShoppingService _service(Database db, {DateTime? today}) => ShoppingModule.createService(
      db: db,
      users: shop.DemoUserGateway(),
      products: shop.DemoProductGateway(),
      stores: shop.DemoStoreGateway(),
      vibrator: SilentVibrator(),
      tokens: MemoryTokenStore(),
      clock: today == null ? null : () => today,
    );

/// Rangées d'une étiquette : (texte, hauteur relative du texte).
List<LiveOcrRow> label(List<(String, double)> rows) => [
      for (var i = 0; i < rows.length; i++)
        LiveOcrRow(rows[i].$1, box: Rect.fromLTWH(0.1, 0.1 + i * 0.1, 0.6, rows[i].$2)),
    ];

void main() {
  group('5 étiquettes de référence', () {
    test('1. « 1,350 DT » + code-barres → prix, nom, code', () {
      final r = parseShelfLabel(label([
        ('LAIT DELICE', 0.04),
        ('DEMI ECREME 1L', 0.03),
        ('1,350 DT', 0.09),
        ('3017620422003', 0.02),
      ]));
      expect(r.price, 1.35);
      expect(r.name, 'LAIT DELICE DEMI ECREME 1L');
      expect(r.barcode, '3017620422003');
      expect(r.priceIsPerKilo, isFalse);
    });

    test('2. prix + prix au kilo : le plus gros est le prix, le « LE KG » à part', () {
      final r = parseShelfLabel(label([
        ('NUTELLA 400G', 0.04),
        ('PRIX 13,900', 0.10),
        ('LE KG 34,750', 0.02),
        ('3017620422003', 0.02),
      ]));
      expect(r.price, 13.9);
      expect(r.perKiloPrice, 34.75);
      expect(r.name, 'NUTELLA 400G');
    });

    test('3. « 7 900 » (dinars en gros, millimes en petit), mot PROMO ignoré', () {
      final r = parseShelfLabel(label([
        ('PROMO', 0.03),
        ('CAFE MOULU 250G', 0.04),
        ('7 900', 0.12),
      ]));
      expect(r.price, 7.9);
      expect(r.name, 'CAFE MOULU 250G');
    });

    test('4. produit au poids : « 1.5 DT/KG » est le prix (au kilo)', () {
      final r = parseShelfLabel(label([('TOMATES', 0.06), ('1.5 DT/KG', 0.10)]));
      expect(r.price, 1.5);
      expect(r.priceIsPerKilo, isTrue);
      expect(r.name, 'TOMATES');
    });

    test('5. « 2DT200 » ; « 7,9 » = 7,900', () {
      expect(parseShelfLabel(label([('SPAGHETTI N5', 0.04), ('2DT200', 0.08)])).price, 2.2);
      expect(parseShelfLabel(label([('HARISSA', 0.04), ('7,9', 0.08)])).price, 7.9);
    });
  });

  test('illisible : pas de prix, date et faux code-barres ignorés', () {
    final r = parseShelfLabel(label([('PROMO -20%', 0.05), ('VALABLE AU 12/11/2026', 0.02), ('1234567890123', 0.02)]));
    expect(r.hasPrice, isFalse);
    expect(r.barcode, isNull, reason: 'clé de contrôle fausse');
  });

  test('vote : prix confirmé après 2 images identiques, lecture isolée écartée', () {
    final t = ShelfLabelTracker();
    final good = parseShelfLabel(label([('CAFE MOULU 250G', 0.04), ('7,900 DT', 0.1)]));
    final bad = parseShelfLabel(label([('CAFE MOULU 250G', 0.04), ('7,300 DT', 0.1)]));
    t.add(good, hadText: true);
    expect(t.confirmed, isNull);
    t.add(bad, hadText: true);
    expect(t.confirmed, isNull);
    t.add(good, hadText: true);
    expect(t.confirmed!.price, 7.9);
    expect(t.confirmed!.name, 'CAFE MOULU 250G');
  });

  group('Bulle : comparaison avec mes achats', () {
    final now = DateTime(2026, 11, 25);
    final h = [
      PricePoint(date: DateTime(2026, 9, 3), unitPrice: 6.90, store: 'Monoprix'),
      PricePoint(date: DateTime(2026, 10, 19), unitPrice: 6.85, store: 'Carrefour'),
      PricePoint(date: DateTime(2026, 11, 15), unitPrice: 7.90, store: 'Monoprix'),
    ];
    test("« 10 % moins cher que d'habitude » (vert)", () {
      final v = shelfVerdict(price: 6.5, history: h, now: now);
      expect(v.kind, ShelfVerdictKind.cheaper);
      expect(v.text, "10 % moins cher que d'habitude");
    });
    test('« 9 % plus cher que ton dernier achat » (rouge)', () {
      final v = shelfVerdict(price: 8.6, history: h, now: now);
      expect(v.kind, ShelfVerdictKind.dearer);
      expect(v.text, '9 % plus cher que ton dernier achat');
    });
    test('« Déjà payé 7,9 DT chez Monoprix » ; jamais acheté', () {
      expect(shelfVerdict(price: 7.9, history: h, now: now).text, 'Déjà payé 7,9 DT chez Monoprix');
      expect(shelfVerdict(price: 7.9, history: const [], now: now).kind, ShelfVerdictKind.unknown);
    });
  });

  group('Recherche dans mes achats (démo)', () {
    sqfliteFfiInit();
    test('code-barres → mon historique + Open Prices ; nom seul → libellé ressemblant', () async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = _service(db, today: DateTime(2026, 11, 25, 10));
      await seedDemoShoppingIfEmpty(s.repository, 1, DateTime(2026, 11, 25, 10));
      final scan = ShoppingModule.createProductScan(s);

      final nutella = await scan.shelfLookup(
        parseShelfLabel(label([('NUTELLA 400G', 0.04), ('PRIX 15,500', 0.1), ('3017620422003', 0.02)])),
      );
      expect(nutella.name, 'Nutella', reason: 'nom de la fiche produit (code-barres)');
      expect(nutella.verdict.text, '9 % plus cher que ton dernier achat');
      expect(nutella.communityCount, 6, reason: 'mode démo : 6 prix en DT');
      expect(nutella.communityDiff, greaterThan(0.15));

      final cafe = await scan.shelfLookup(parseShelfLabel(label([('CAFE MOULU 250G', 0.04), ('6 500', 0.12)])));
      expect(cafe.verdict.kind, ShelfVerdictKind.cheaper);
      expect(cafe.communityNote, isNull, reason: 'pas de code-barres : pas de comparaison Open Prices');

      final unknown = await scan.shelfLookup(parseShelfLabel(label([('CHOCOLAT NOIR', 0.04), ('3,200 DT', 0.1)])));
      expect(unknown.verdict.kind, ShelfVerdictKind.unknown);

      // Panier en direct : même produit = quantité + 1.
      await s.addToLiveCart(const LiveCartItem(label: 'Nutella', unitPrice: 15.5, barcode: '3017620422003'));
      final cart = await s.addToLiveCart(const LiveCartItem(label: 'Nutella', unitPrice: 15.5, barcode: '3017620422003'));
      expect(cart.single.quantity, 2);
      await db.close();
    });
  });

  Future<(Database, FakeCamera)> openScreen(WidgetTester tester, {LiveCameraException? error}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cam = FakeCamera()..openError = error;
    late Database db;
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = _service(db);
      await seedDemoShoppingIfEmpty(s.repository, 1, DateTime.now());
      app = PanierMalinApp(
        service: RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(s),
        ),
        shopping: s,
        liveCamera: () => cam,
        home: const ShelfLabelScanScreen(),
      );
    });
    await tester.runAsync(() => tester.pumpWidget(app));
    await go(tester);
    return (db, cam);
  }

  testWidgets('écran : étiquette filmée → prix confirmé → bulle rouge, communauté, panier', (tester) async {
    final (db, cam) = await openScreen(tester);
    final rows = label([('NUTELLA 400G', 0.04), ('PRIX 15,500', 0.1), ('3017620422003', 0.02)]);
    cam.show(rows);
    await go(tester);
    expect(find.text('9 % plus cher que ton dernier achat'), findsNothing, reason: 'une seule image : pas encore');
    cam.show(rows);
    await go(tester);
    expect(find.text('9 % plus cher que ton dernier achat'), findsOneWidget);
    expect(find.text('15,500 DT'), findsOneWidget);
    expect(find.textContaining('Communauté :'), findsOneWidget);
    await tester.tap(find.text('Ajouter au panier en direct'));
    await go(tester);
    expect(find.textContaining('Panier en direct : 1 article'), findsOneWidget);
    await tester.runAsync(db.close);
  });

  testWidgets('trop sombre : message clair', (tester) async {
    final (db, cam) = await openScreen(tester);
    cam.show(label([('NUTELLA', 0.04)]), brightness: 0.05);
    cam.show(label([('NUTELLA', 0.04)]), brightness: 0.05);
    await go(tester);
    expect(find.text('Trop sombre : rapproche-toi / ajoute de la lumière'), findsOneWidget);
    await tester.runAsync(db.close);
  });

  testWidgets('caméra refusée → saisie manuelle du prix', (tester) async {
    final (db, _) = await openScreen(tester, error: const LiveCameraException(LiveCameraError.permissionDenied));
    expect(find.text('Accès à la caméra refusé'), findsOneWidget);
    await tester.tap(find.text('Saisir le prix'));
    await go(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Produit'), 'Café moulu 250g');
    await tester.enterText(find.widgetWithText(TextField, 'Prix'), '6,5');
    await tester.tap(find.text('Comparer'));
    await go(tester);
    expect(find.text("10 % moins cher que d'habitude"), findsOneWidget);
    await tester.runAsync(db.close);
  });
}

Future<void> go(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}
