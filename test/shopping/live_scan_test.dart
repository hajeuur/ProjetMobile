import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/logic/live_receipt_parser.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/receipt_scan_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/live_scan_view_model.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fausse caméra : on lui fait « voir » des rangées de texte.
class FakeLiveCamera implements LiveReceiptCamera {
  LiveCameraException? openError;
  Duration openDelay = Duration.zero;
  StreamController<LiveFrame> _frames = StreamController<LiveFrame>.broadcast();
  int opens = 0;
  bool closed = false;
  bool torch = false;
  bool settingsOpened = false;
  String? photo = 'receipt_photos/ticket_live.jpg';

  @override
  Future<void> open() async {
    opens++;
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    if (openError != null) throw openError!;
    closed = false;
    if (_frames.isClosed) _frames = StreamController<LiveFrame>.broadcast();
  }

  @override
  Widget buildPreview(Widget overlay) => ColoredBox(color: Colors.black, child: overlay);

  @override
  Stream<LiveFrame> frames() => _frames.stream;

  void show(List<String> texts, {double brightness = 0.6, double height = 0.04}) => _frames.add(LiveFrame(
        brightness: brightness,
        rows: [
          for (var i = 0; i < texts.length; i++)
            LiveOcrRow(texts[i], box: Rect.fromLTWH(0.1, 0.15 + i * 0.06, 0.8, height), confidence: 0.95),
        ],
      ));

  @override
  Future<void> setTorch(bool on) async => torch = on;

  @override
  Future<String?> takePhoto() async => photo;

  @override
  Future<bool> openSettings() async => settingsOpened = true;

  @override
  Future<void> close() async => closed = true;
}

class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

class CancelReader implements ReceiptReader {
  @override
  Future<String?> capture(PhotoSource source) async => null;
  @override
  Future<String> readText(String photoPath) async => '';
}

const ticket = [
  'CARREFOUR MARKET',
  'LA MARSA',
  'LAIT DELICE 1L        1,350',
  'PAIN BAGUETTE         0,200',
  'YAOURT VITALAIT 4 x 0,600  2,400',
  'CAFE BONDIN           1,3S0',
  'TOTAL TTC             5,300 DT',
  'ESPECES              10,000',
];

ShoppingService _service(Database db) => ShoppingModule.createService(
      db: db,
      users: shop.DemoUserGateway(),
      products: shop.DemoProductGateway(),
      stores: shop.DemoStoreGateway(),
      vibrator: SilentVibrator(),
      tokens: MemoryTokenStore(),
    );

void main() {
  sqfliteFfiInit();

  group('Scan en direct (view model)', () {
    test('lignes confirmées, total validé, stable → un seul retour haptique', () async {
      final cam = FakeLiveCamera();
      var buzz = 0;
      final vm = LiveScanViewModel(cam, onStable: () => buzz++);
      await vm.start();
      expect(vm.phase, LivePhase.scanning);
      for (var i = 0; i < 6; i++) {
        cam.show(ticket);
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.tracker.lines.map((l) => l.label), ['LAIT DELICE 1L', 'PAIN BAGUETTE', 'YAOURT VITALAIT', 'CAFE BONDIN']);
      expect(vm.tracker.lines[2].quantity, 4);
      expect(vm.tracker.total, 5.3);
      expect(vm.isStable, isTrue);
      expect(buzz, 1, reason: 'une vibration quand le texte devient stable, pas à chaque image');

      final out = (await vm.finish())!;
      expect(out.kind, LiveOutcomeKind.done);
      expect(out.photo, 'receipt_photos/ticket_live.jpg');
      expect(out.receipt!.lines.length, 4);
      expect(out.receipt!.total, 5.3);
      expect(out.receipt!.headerLines.first, 'CARREFOUR MARKET');
      expect(out.doubtful, {3}, reason: 'CAFE : « S » lu à la place de « 5 »');
      expect(out.ocrText, contains('TOTAL TTC'));
      vm.dispose();
      expect(cam.closed, isTrue, reason: 'caméra libérée');
    });

    test('trop sombre, texte trop petit, ticket illisible après 10 s', () async {
      final cam = FakeLiveCamera();
      var now = DateTime(2026, 11, 25, 10);
      final vm = LiveScanViewModel(cam, clock: () => now);
      await vm.start();
      cam.show(['CARREFOUR'], brightness: 0.05);
      cam.show(['CARREFOUR'], brightness: 0.05);
      await Future<void>.delayed(Duration.zero);
      expect(vm.hint, LiveHint.tooDark);
      cam.show(['L A I T', 'P A I N'], height: 0.008);
      await Future<void>.delayed(Duration.zero);
      expect(vm.hint, LiveHint.tooFar);
      expect(vm.illegible, isFalse);
      now = now.add(const Duration(seconds: 11));
      cam.show(['bla bla']);
      await Future<void>.delayed(Duration.zero);
      expect(vm.illegible, isTrue);
      vm.restartReading();
      expect(vm.illegible, isFalse);
      vm.dispose();
    });

    test('arrière-plan : caméra libérée puis rouverte ; lampe', () async {
      final cam = FakeLiveCamera();
      final vm = LiveScanViewModel(cam);
      await vm.start();
      await vm.toggleTorch();
      expect(cam.torch, isTrue);
      await vm.pause();
      expect(cam.closed, isTrue);
      expect(vm.torch, isFalse);
      await vm.resume();
      expect(cam.opens, 2);
      expect(vm.phase, LivePhase.scanning);
      vm.dispose();
    });

    test('la fenêtre de permission (pause/reprise) n’ouvre pas une seconde caméra', () async {
      final cam = FakeLiveCamera()..openDelay = const Duration(milliseconds: 50);
      final vm = LiveScanViewModel(cam);
      final opening = vm.start();
      await vm.pause(); // app « inactive » pendant la demande de permission
      await vm.resume();
      await vm.start(); // double appel ignoré
      await opening;
      expect(cam.opens, 1);
      expect(vm.phase, LivePhase.scanning);
      vm.dispose();
    });

    test('permission refusée : erreur, pas de flux', () async {
      final cam = FakeLiveCamera()..openError = const LiveCameraException(LiveCameraError.permissionDenied);
      final vm = LiveScanViewModel(cam);
      await vm.start();
      expect(vm.phase, LivePhase.error);
      expect(vm.error, LiveCameraError.permissionDenied);
      expect(await vm.finish(), isNull);
      vm.dispose();
    });
  });

  group('Scan en direct (écrans)', () {
    late Database db;
    late ShoppingService service;
    late FakeLiveCamera cam;

    Future<void> openScan(WidgetTester tester, {bool ocr = true}) async {
      // Téléphone étroit (360 × 780) : repère les débordements.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      cam = FakeLiveCamera();
      late PanierMalinApp app;
      await tester.runAsync(() async {
        await initializeDateFormatting('fr_FR');
        await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
        db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
        service = _service(db);
        if (!ocr) await service.saveSettings((await service.settings()).copyWith(ocr: false));
        final recipes = RecipesModule.createService(
          db: db,
          stock: DemoStockGateway(),
          household: DemoHouseholdGateway(),
          shopping: RecipesShoppingBridge(service),
        );
        app = PanierMalinApp(
          service: recipes,
          shopping: service,
          shakeSource: NoShakes(),
          receiptReader: CancelReader(),
          liveCamera: () => cam,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptScanScreen())),
                  child: const Text('Tickets'),
                ),
              ),
            ),
          ),
        );
      });
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
      await tester.tap(find.text('Tickets'));
      await go(tester);
    }

    Future<void> showFrames(WidgetTester tester, List<String> rows, int n) async {
      for (var i = 0; i < n; i++) {
        cam.show(rows);
        await go(tester);
      }
    }

    testWidgets('scan → lignes en surbrillance → total validé → validation modifiable → enregistré avec photo',
        (tester) async {
      await openScan(tester);
      await tester.tap(find.text('Scanner en direct'));
      await go(tester);
      expect(find.text('Scan en direct'), findsOneWidget);
      expect(find.text('Lignes lues (0)'), findsOneWidget);
      expect(find.text('Placez le ticket dans le cadre, bien à plat'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Terminer le scan')).onPressed, isNull);

      await showFrames(tester, ticket, 2);
      expect(find.text('Lignes lues (4)'), findsOneWidget);
      expect(find.text('LAIT DELICE 1L'), findsOneWidget);
      expect(find.text('Total validé'), findsOneWidget);
      await tester.dragUntilVisible(find.text('CAFE BONDIN'), find.byType(ListView), const Offset(0, -80));
      await go(tester);
      expect(find.text('à vérifier'), findsOneWidget, reason: 'CAFE en orange');

      await showFrames(tester, ticket, 4);
      expect(find.text('Lecture stable : vous pouvez terminer'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Terminer le scan'));
      await go(tester);

      // Écran de validation.
      expect(find.text('Validation du ticket'), findsOneWidget);
      expect(find.text('Photo du ticket'), findsOneWidget);
      expect(find.text('1 ligne à vérifier, en orange'), findsOneWidget);
      expect(find.text('4 lignes'), findsOneWidget);
      expect(find.textContaining(RegExp('carrefour', caseSensitive: false)), findsWidgets, reason: 'magasin reconnu dans l en-tête');

      // Supprimer « PAIN BAGUETTE » avec la corbeille.
      await tester.dragUntilVisible(find.text('PAIN BAGUETTE'), find.byType(ListView), const Offset(0, -150));
      await go(tester);
      await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('PAIN BAGUETTE'), matching: find.byType(Card)),
        matching: find.byTooltip('Supprimer la ligne'),
      ));
      await go(tester);
      expect(find.text('PAIN BAGUETTE'), findsNothing, reason: 'ligne supprimée');
      await tester.dragUntilVisible(find.textContaining('Écart de 0,200 DT'), find.byType(ListView), const Offset(0, -150));
      expect(find.textContaining('Écart de 0,200 DT'), findsOneWidget);

      await tester.tap(find.textContaining('Valider le ticket'));
      await go(tester);
      expect(find.text('Ticket enregistré'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await go(tester);

      final receipts = (await tester.runAsync(service.receipts))!;
      expect(receipts.length, 1);
      expect(receipts.single.photo, 'receipt_photos/ticket_live.jpg');
      expect(receipts.single.total, 5.3);
      final lines = (await tester.runAsync(() => service.receipt(receipts.single.id!)))!.lines;
      expect(lines.map((l) => l.label), ['LAIT DELICE 1L', 'YAOURT VITALAIT', 'CAFE BONDIN']);
      expect(cam.closed, isTrue, reason: 'caméra libérée en quittant l\'écran');
      await tester.runAsync(db.close);
    });

    testWidgets('trop sombre puis caméra refusée : messages et bascule vers la saisie manuelle', (tester) async {
      await openScan(tester);
      await tester.tap(find.text('Scanner en direct'));
      await go(tester);
      cam.show(['LAIT 1,350'], brightness: 0.05);
      cam.show(['LAIT 1,350'], brightness: 0.05);
      await go(tester);
      expect(find.text('Trop sombre : Rapproche-toi / ajoute de la lumière'), findsOneWidget);
      await tester.tap(find.byTooltip('Allumer la lampe'));
      await go(tester);
      expect(cam.torch, isTrue);
      await tester.tap(find.byTooltip('Fermer'));
      await go(tester);
      expect(cam.closed, isTrue);

      // Caméra refusée définitivement.
      cam.openError = const LiveCameraException(LiveCameraError.permissionPermanentlyDenied);
      await tester.tap(find.text('Scanner en direct'));
      await go(tester);
      expect(find.text('Caméra bloquée'), findsOneWidget);
      await tester.tap(find.text('Ouvrir les réglages'));
      expect(cam.settingsOpened, isTrue);
      // Refus simple : « Réessayer » relance la caméra.
      cam.openError = const LiveCameraException(LiveCameraError.permissionDenied);
      await tester.tap(find.text('Réessayer'));
      await go(tester);
      expect(find.text('Accès à la caméra refusé'), findsOneWidget);
      await tester.tap(find.text('Saisir à la main'));
      await go(tester);
      expect(find.text('Validation du ticket'), findsOneWidget);
      expect(find.text('Aucune ligne'), findsOneWidget);
      await tester.runAsync(db.close);
    });

    testWidgets('« Lecture automatique » désactivée : pas de scan en direct', (tester) async {
      await openScan(tester, ocr: false);
      expect(find.text('Scanner en direct'), findsNothing);
      expect(find.text('Prendre le ticket en photo'), findsOneWidget);
      expect(find.text('Lecture automatique désactivée'), findsOneWidget);
      await tester.runAsync(db.close);
    });
  });
}

Future<void> go(WidgetTester tester) async {
  for (var r = 0; r < 2; r++) {
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(milliseconds: 500));
  }
}
