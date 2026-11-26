import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/logic/purchase_suggestions.dart';
import 'package:panier_malin/features/shopping/models/receipt.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/suggestions_card.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 11, 25, 10);
List<DateTime> daysAgo(List<int> d) => [for (final x in d) now.subtract(Duration(days: x))];

void main() {
  group('5 jeux de test', () {
    test('1. lait tous les 6 jours, dernier achat il y a 5 jours → proposé, confiance élevée', () {
      final s = frequencySuggestions(
        {
          'lait': daysAgo([35, 29, 23, 17, 11, 5]),
        },
        {'lait': 'Lait'},
        now: now,
      ).single;
      expect(s.sentence, "Tu achètes « Lait » tous les 6 jours, l'ajouter ?");
      expect(s.level, ConfidenceLevel.high);
      expect(s.detail, 'Dernier achat il y a 5 jours · 6 achats');
    });

    test('2. acheté hier → pas encore', () {
      expect(
        frequencySuggestions(
          {
            'lait': daysAgo([19, 13, 7, 1]),
          },
          {},
          now: now,
        ),
        isEmpty,
      );
    });

    test('3. seulement 2 achats → données insuffisantes, rien', () {
      expect(
        frequencySuggestions(
          {
            'cafe': daysAgo([40, 10]),
          },
          {},
          now: now,
        ),
        isEmpty,
      );
    });

    test('4. achats très irréguliers → confiance trop faible, rien ; abandonné depuis longtemps → rien', () {
      expect(
        frequencySuggestions(
          {
            'x': daysAgo([90, 88, 30]),
          },
          {},
          now: now,
        ),
        isEmpty,
        reason: 'intervalles 2 et 58 jours',
      );
      expect(
        frequencySuggestions(
          {
            'y': daysAgo([100, 93, 86]),
          },
          {},
          now: now,
        ),
        isEmpty,
        reason: '86 j > 2,5 × 7 j',
      );
    });

    test('5. souvent oublié : 3 fois → proposé ; 1 fois → rien', () {
      final s = forgottenSuggestions({'pain': (label: 'Pain', count: 3), 'sel': (label: 'Sel', count: 1)});
      expect(s.single.sentence, "Tu oublies souvent « Pain » (3 fois), l'ajouter ?");
      expect(s.single.level, ConfidenceLevel.high);
    });
  });

  test('libellés de fréquence', () {
    expect(Suggestion.everyLabel(7), 'chaque semaine');
    expect(Suggestion.everyLabel(14), 'toutes les 2 semaines');
    expect(Suggestion.everyLabel(30), 'chaque mois');
    expect(Suggestion.everyLabel(4), 'tous les 4 jours');
    expect(Suggestion.everyLabel(62), 'environ tous les 2 mois');
  });

  test('deux lignes le même jour = un achat ; tri par confiance', () {
    final r = frequencySuggestions(
      {
        'a': [
          ...daysAgo([21, 14, 7]),
          now.subtract(const Duration(days: 7, hours: 2)),
        ],
        'b': daysAgo([40, 27, 21, 13, 6]),
      },
      {},
      now: now,
    );
    expect(r.first.key, 'a');
    expect(r.first.purchases, 3);
  });

  group('Service', () {
    sqfliteFfiInit();
    late Database db;
    late ShoppingService s;
    var clock = now;

    setUp(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      clock = now;
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => clock,
      );
    });
    tearDown(() => db.close());

    Future<void> buyMilk() async {
      for (final d in [35, 29, 23, 17, 11, 5]) {
        await s.saveDraft(
          ReceiptDraft(
            date: now.subtract(Duration(days: d)),
            lines: [const ReceiptLine(label: 'LAIT DEMI ECREME 1L', price: 1.35)],
          ),
        );
      }
    }

    test('lait dû → proposé ; Ajouter = origine « Suggestion » ; plus proposé une fois sur la liste', () async {
      await buyMilk();
      final listId = await s.createList('Liste du 25/11/2026');
      await s.addItem(listId, label: 'Pain');
      final sug = (await s.suggestions(listId: listId)).single;
      expect(sug.sentence, "Tu achètes « Lait demi-écrémé 1L » tous les 6 jours, l'ajouter ?");

      final r = await s.acceptSuggestion(sug, listId: listId);
      final item = (await s.items(listId)).firstWhere((i) => i.id == r.itemId);
      expect(item.origin, ItemOrigin.suggestion);
      expect(await s.suggestions(listId: listId), isEmpty, reason: 'déjà sur la liste');
    });

    test('Pas maintenant : reporté de la moitié de l\'intervalle ; Ne plus proposer : définitif', () async {
      await buyMilk();
      final sug = (await s.suggestions()).single;
      await s.snoozeSuggestion(sug);
      expect(await s.suggestions(), isEmpty);
      clock = now.add(const Duration(days: 3));
      expect(await s.suggestions(), hasLength(1), reason: '6 j / 2 = 3 j plus tard');

      await s.neverSuggest(sug);
      expect(await s.suggestions(), isEmpty);
      await s.resetNeverSuggest();
      expect(await s.suggestions(), isNotEmpty);
    });

    test('oublis enregistrés au rapprochement (un ticket compte une fois) → « souvent oublié »', () async {
      Future<int> trip(int day) async {
        final list = await s.createList('Courses $day');
        await s.addItem(list, label: 'Lessive');
        await s.addItem(list, label: 'Tomates');
        final r = await s.saveDraft(
          ReceiptDraft(
            date: now.subtract(Duration(days: day)),
            listId: list,
            lines: [const ReceiptLine(label: 'TOMATES', price: 2.7)],
          ),
        );
        return r.receiptId;
      }

      final first = await trip(20);
      final empty = await s.createList('Vide');
      Future<Iterable<Suggestion>> forgotten() async =>
          (await s.suggestions(listId: empty)).where((x) => x.kind == SuggestionKind.forgotten);
      expect(await forgotten(), isEmpty, reason: '1 oubli');
      final firstList = (await s.lists()).firstWhere((l) => l.name == 'Courses 20').id!;
      await s.reconcile(first, firstList); // relancé : pas de double comptage
      expect(await forgotten(), isEmpty);
      await trip(10);
      // Sur une nouvelle liste (la précédente contient encore « Lessive »).
      final next = await s.createList('Suivante');
      final f = (await s.suggestions(listId: next)).singleWhere((x) => x.kind == SuggestionKind.forgotten);
      expect(f.sentence, "Tu oublies souvent « Lessive » (2 fois), l'ajouter ?");
      expect(f.level, ConfidenceLevel.medium);
    });

    test('interrupteur et données insuffisantes : rien', () async {
      expect(await s.suggestions(), isEmpty, reason: 'aucun achat');
      await buyMilk();
      await s.saveSettings((await s.settings()).copyWith(suggestions: false));
      expect(await s.suggestions(), isEmpty);
    });
  });

  testWidgets('carte : Ajouter, Pas maintenant, Ne plus proposer', (tester) async {
    late Database db;
    late ShoppingService s;
    late int listId;
    await tester.runAsync(() async {
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      s = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: SilentVibrator(),
        tokens: MemoryTokenStore(),
        clock: () => now,
      );
      for (final d in [35, 29, 23, 17, 11, 5]) {
        await s.saveDraft(
          ReceiptDraft(
            date: now.subtract(Duration(days: d)),
            lines: [
              const ReceiptLine(label: 'LAIT DEMI ECREME 1L', price: 1.35),
              if (d.isOdd) const ReceiptLine(label: 'PAIN DE MIE', price: 2.1),
            ],
          ),
        );
      }
      listId = await s.createList('Liste');
    });
    Future<void> go() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      Provider.value(
        value: s,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SuggestionsCard(listId: listId)),
          ),
        ),
      ),
    );
    await go();
    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.textContaining('Confiance'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter').first);
    await go();
    expect(find.textContaining('ajouté à la liste'), findsOneWidget);
    expect((await tester.runAsync(() => s.items(listId)))!.single.origin, ItemOrigin.suggestion);

    await tester.tap(find.text('Ne plus proposer'));
    await go();
    expect(find.text('Suggestions'), findsNothing, reason: 'plus rien à proposer : carte masquée');
    await tester.runAsync(db.close);
  });
}
