import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/features/shopping/viewmodels/shopping_lists_view_model.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Faux micro : renvoie une phrase (avec un résultat partiel avant), ou une
/// erreur.
class FakeVoice implements VoiceInput {
  String sentence = 'ajoute lait, pain et 6 œufs';
  VoiceError? error;
  bool settingsOpened = false;
  int starts = 0;

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(double level) onLevel,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  }) async {
    starts++;
    if (error != null) return onError(error!);
    onLevel(0.6);
    onText(sentence.split(',').first, false); // texte en direct
    await Future<void>.delayed(const Duration(milliseconds: 10));
    onText(sentence, true);
    onDone();
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> openSettings() async => settingsOpened = true;
}

class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

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

  group('Ajout vocal (view model)', () {
    late Database db;
    late ShoppingService service;
    late ListDetailViewModel vm;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = _service(db);
      vm = ListDetailViewModel(service, await service.createList('Test'));
      await vm.load();
      await vm.add('Lait', quantity: 2, unit: 'L');
      await vm.add('Tomates', quantity: 1, unit: 'kg');
    });
    tearDown(() => db.close());

    ShoppingItem byLabel(String l) => vm.items.firstWhere((i) => i.label == l);

    test('articles déjà présents repérés ; quantité augmentée au lieu d\'un doublon', () async {
      final drafts = await vm.prepareVoice('ajoute un litre de lait, 3 tomates et une douzaine d\'œufs');
      expect(drafts.map((d) => d.label), ['Lait', 'Tomates', 'Œufs']);
      expect(drafts[0].existing?.label, 'Lait');
      expect(drafts[0].mergePreview, '2 L → 3 L');
      expect(drafts[1].canMerge, isFalse, reason: '1 kg + 3 (sans unité) : incompatible');
      expect(drafts[2].existing, isNull);

      expect(await vm.addVoiceItems(drafts), 3);
      expect(vm.items.where((i) => i.label == 'Lait').length, 1);
      expect(byLabel('Lait').quantity, 3);
      expect(byLabel('Lait').origin, ItemOrigin.manual, reason: 'l\'article existant garde son origine');
      expect(vm.items.where((i) => i.label == 'Tomates').length, 2, reason: 'unités différentes : ajouté à part');
      final oeufs = byLabel('Œufs');
      expect(oeufs.quantity, 12);
      expect(oeufs.origin, ItemOrigin.voice);
    });

    test('doublon choisi explicitement, puis annulation par secousse', () async {
      final drafts = await vm.prepareVoice('mets du lait');
      drafts.single.mergeIntoExisting = false;
      await vm.addVoiceItems(drafts);
      expect(vm.items.where((i) => i.label == 'Lait').length, 2);
      final a = await vm.undo();
      expect(a!.undoDescription, 'lait retiré de la liste');
      expect(vm.items.where((i) => i.label == 'Lait').length, 1);
    });
  });

  group('Ajout vocal (écran)', () {
    late Database db;
    late ShoppingService service;
    late FakeVoice voice;

    Future<void> openList(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(380, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      voice = FakeVoice();
      late PanierMalinApp app;
      await tester.runAsync(() async {
        await initializeDateFormatting('fr_FR');
        await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
        db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
        service = _service(db);
        await seedDemoShoppingIfEmpty(service.repository, 1, DateTime.now());
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
          voiceInput: voice,
          home: const ShoppingHomeScreen(),
        );
      });
      await tester.runAsync(() => tester.pumpWidget(app));
      await go(tester);
      await tester.ensureVisible(find.text('Courses de la semaine'));
      await tester.pump();
      await tester.tap(find.text('Courses de la semaine'));
      await go(tester);
    }

    testWidgets('dictée → confirmation modifiable → ajout avec badge « Voix »', (tester) async {
      await openList(tester);
      await tester.tap(find.byTooltip('Ajouter par la voix'));
      await go(tester);
      expect(find.text('Articles dictés'), findsOneWidget);
      expect(find.text('« ajoute lait, pain et 6 œufs »'), findsOneWidget);
      // Lait et Pain sont déjà dans la liste de démo.
      expect(find.text('Déjà dans la liste : « Lait »'), findsOneWidget);
      expect(find.text('Augmenter la quantité : 2 L → 3 L'), findsOneWidget);
      expect(find.text('Ajouter à la liste (3)'), findsOneWidget);

      // Retirer « Pain », corriger la quantité d'œufs.
      await tester.tap(find.byTooltip('Retirer').at(1));
      await go(tester);
      await tester.enterText(find.widgetWithText(TextField, '6'), '10');
      await go(tester);
      await tester.tap(find.text('Ajouter à la liste (2)'));
      await go(tester);

      expect(find.text('2 articles ajoutés par la voix.'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Œufs'), find.byType(ListView).first, const Offset(0, -300));
      await go(tester);
      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('Voix'), findsOneWidget, reason: 'badge micro');
      final items = (await tester.runAsync(() async {
        final l = (await service.lists(status: ListStatus.active)).first;
        return service.items(l.id!);
      }))!;
      expect(items.firstWhere((i) => i.label == 'Lait').quantity, 3);
      expect(items.firstWhere((i) => i.label == 'Œufs').quantity, 10);
      expect(items.where((i) => i.label == 'Pain').length, 1);
      await tester.runAsync(db.close);
    });

    testWidgets('erreurs : micro bloqué, aucun son, hors ligne, repli sur la saisie manuelle', (tester) async {
      await openList(tester);

      voice.error = VoiceError.permissionPermanentlyDenied;
      await tester.tap(find.byTooltip('Ajouter par la voix'));
      await go(tester);
      expect(find.text('Micro bloqué'), findsOneWidget);
      await tester.tap(find.text('Ouvrir les réglages'));
      expect(voice.settingsOpened, isTrue);
      await tester.tap(find.text('Saisir à la main'));
      await go(tester);
      expect(find.text('Micro bloqué'), findsNothing);
      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Ajouter un article'));
      expect(field.focusNode!.hasFocus, isTrue, reason: 'bascule vers la saisie manuelle');

      voice.error = VoiceError.noSpeech;
      await tester.tap(find.byTooltip('Ajouter par la voix'));
      await go(tester);
      expect(find.text('Aucun son détecté'), findsOneWidget);
      // Réessayer, cette fois avec une phrase.
      voice.error = null;
      voice.sentence = 'ajoute des bananes';
      await tester.tap(find.text('Réessayer'));
      await go(tester);
      expect(find.text('Articles dictés'), findsOneWidget);
      expect(find.text('Ajouter à la liste (1)'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour').last);
      await go(tester);

      voice.error = VoiceError.offline;
      await tester.tap(find.byTooltip('Ajouter par la voix'));
      await go(tester);
      expect(find.text('Reconnaissance indisponible hors ligne'), findsOneWidget);
      await tester.tap(find.text('Saisir à la main'));
      await go(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('réglage « Ajout vocal » désactivé : pas de bouton micro', (tester) async {
      await openList(tester);
      expect(find.byTooltip('Ajouter par la voix'), findsOneWidget);
      await tester.runAsync(() async => service.saveSettings((await service.settings()).copyWith(voiceInput: false)));
      await tester.tap(find.byTooltip('Retour'));
      await go(tester);
      await tester.ensureVisible(find.text('Courses de la semaine'));
      await tester.pump();
      await tester.tap(find.text('Courses de la semaine'));
      await go(tester);
      expect(find.byTooltip('Ajouter par la voix'), findsNothing);
      await tester.runAsync(db.close);
    });
  });
}

Future<void> go(WidgetTester tester) async {
  for (var r = 0; r < 2; r++) {
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    // Les ondes sonores tournent en boucle pendant l'écoute : pas de pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
  }
}
