import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/recipes/data/themealdb_api.dart';
import 'package:panier_malin/features/recipes/integration/gateways.dart';
import 'package:panier_malin/features/recipes/logic/calorie_estimator.dart';
import 'package:panier_malin/features/recipes/logic/hand_wave_detector.dart';
import 'package:panier_malin/features/recipes/logic/measure_parser.dart';
import 'package:panier_malin/features/recipes/logic/menu_generator.dart';
import 'package:panier_malin/features/recipes/logic/text_matching.dart';
import 'package:panier_malin/features/recipes/logic/voice_commands.dart';
import 'package:panier_malin/features/recipes/models/meal_plan.dart';
import 'package:panier_malin/features/recipes/models/recipe.dart';

void main() {
  group('parseMeasure', () {
    test('quantités et unités TheMealDB', () {
      final a = parseMeasure('1/2 cup');
      expect(a.quantity, 0.5);
      expect(a.unit, 'cup');
      final b = parseMeasure('200g');
      expect(b.quantity, 200);
      expect(b.unit, 'g');
      final c = parseMeasure('1 1/2 tsp');
      expect(c.quantity, 1.5);
      expect(c.unit, 'tsp');
      final d = parseMeasure('2 tbs');
      expect(d.unit, 'tbsp');
      final e = parseMeasure('Pinch');
      expect(e.quantity, isNull);
      expect(e.unit, 'Pinch');
      expect(parseMeasure('1½ kg').quantity, 1.5);
      expect(parseMeasure('3 cloves').unit, 'gousse');
      expect(parseMeasure('').quantity, isNull);
    });
  });

  group('text matching', () {
    test('pluriels anglais en -oes', () {
      expect(sameIngredient('Tomatoes', 'Tomate'), isTrue);
      expect(sameIngredient('Potatoes', 'pomme de terre'), isTrue);
    });
  });

  group('splitInstructions', () {
    test('lignes STEP et durées', () {
      final steps = splitInstructions('STEP 1\r\nBoil the rice for 15 minutes.\r\n\r\nSTEP 2\r\nBake for 1 hour.');
      expect(steps.length, 2);
      expect(steps[0].text, 'Boil the rice for 15 minutes.');
      expect(steps[0].durationMin, 15);
      expect(steps[1].durationMin, 60);
    });

    test('paragraphe unique découpé par phrases', () {
      final steps = splitInstructions('Cut. Fry. Serve. Enjoy.');
      expect(steps.length, 2);
      expect(steps.first.number, 1);
    });
  });

  test('mealToRecipe convertit un meal TheMealDB', () {
    final r = mealToRecipe({
      'idMeal': '52772',
      'strMeal': 'Teriyaki Chicken',
      'strCategory': 'Chicken',
      'strInstructions': 'Cook chicken 10 minutes.\nServe.',
      'strMealThumb': 'https://x/img.jpg',
      'strIngredient1': 'chicken breast',
      'strMeasure1': '400g',
      'strIngredient2': 'rice',
      'strMeasure2': '300g',
      'strIngredient3': '',
      'strMeasure3': '',
    }, userId: 1);
    expect(r.source, RecipeSource.themealdb);
    expect(r.externalId, '52772');
    expect(r.ingredients.length, 2);
    expect(r.ingredients.first.quantity, 400);
    expect(r.caloriesPerServing, greaterThan(0));
    expect(r.steps.length, 2);
  });

  test('estimateCalories', () {
    final e = estimateCalories(const [
      RecipeIngredient(name: 'Riz', quantity: 100, unit: 'g'),
      RecipeIngredient(name: 'Oeuf', quantity: 2, unit: 'pièce'),
    ], 1)!;
    // 360 + 2 × 55 g × 1,55
    expect(e.perServing, closeTo(360 + 170.5, 1));
    expect(e.reliable, isTrue);
  });

  group('parseVoiceCommand', () {
    test('navigation', () {
      expect(parseVoiceCommand('Suivant'), isA<NextStepCommand>());
      expect(parseVoiceCommand('étape précédente'), isA<PreviousStepCommand>());
      expect(parseVoiceCommand('répète'), isA<RepeatStepCommand>());
      expect(parseVoiceCommand('bonjour'), isNull);
    });

    test('minuteurs', () {
      Duration? d(String s) => (parseVoiceCommand(s) as StartTimerCommand?)?.duration;
      expect(d('minuteur 10 minutes'), const Duration(minutes: 10));
      expect(d('minuteur de vingt cinq minutes'), const Duration(minutes: 25));
      expect(d('minuteur une heure et demie'), const Duration(minutes: 90));
      expect(d('minuteur 1 heure 30 minutes'), const Duration(minutes: 90));
      expect(d('minuteur 30 secondes'), const Duration(seconds: 30));
      expect(parseVoiceCommand('arrête le minuteur'), isA<StopTimerCommand>());
    });
  });

  group('HandWaveDetector', () {
    test('un passage = suivant, deux passages = précédent, main posée = rien', () {
      fakeAsync((fa) {
        final gestures = <HandGesture>[];
        final det = HandWaveDetector(onGesture: gestures.add, clock: () => fa.getClock(DateTime(2026)).now());

        void wave() {
          det.onProximity(true);
          fa.elapse(const Duration(milliseconds: 200));
          det.onProximity(false);
        }

        wave();
        fa.elapse(const Duration(seconds: 1));
        expect(gestures, [HandGesture.next]);

        wave();
        fa.elapse(const Duration(milliseconds: 200));
        wave();
        fa.elapse(const Duration(seconds: 1));
        expect(gestures, [HandGesture.next, HandGesture.previous]);

        det.onProximity(true);
        fa.elapse(const Duration(seconds: 3));
        det.onProximity(false);
        fa.elapse(const Duration(seconds: 1));
        expect(gestures.length, 2);
        det.dispose();
      });
    });
  });

  group('MenuGenerator', () {
    final now = DateTime(2026, 11, 23); // lundi
    Recipe recipe(int id, String title, List<String> ings, {double kcal = 600, String category = 'Plat'}) => Recipe(
          id: id,
          userId: 1,
          title: title,
          category: category,
          caloriesPerServing: kcal,
          ingredients: [for (final i in ings) RecipeIngredient(name: i, quantity: 1, unit: 'pièce')],
        );

    const profile = HouseholdProfile(allergies: {'arachide'}, diets: {'halal'}, dailyCaloriesPerPerson: 2000, memberCount: 2);
    final stock = [
      StockSnapshot(name: 'Poivron', quantity: 3, unit: 'pièce', expiryDate: now.add(const Duration(days: 1))),
      StockSnapshot(name: 'Riz', quantity: 3, unit: 'pièce', expiryDate: now.add(const Duration(days: 100))),
    ];

    test('respecte allergies, régimes, variété et priorité anti-gaspi', () {
      final recipes = [
        recipe(1, 'Poulet cacahuète', ['Poulet', 'Cacahuètes']),
        recipe(2, 'Rôti de porc', ['Porc']),
        recipe(3, 'Poivrons farcis', ['Poivron', 'Riz']),
        recipe(4, 'Riz nature', ['Riz']),
        recipe(5, 'Pâtes', ['Pâtes']),
        recipe(6, 'Omelette', ['Oeuf'], kcal: 500, category: 'Breakfast'),
      ];
      final menu = const MenuGenerator().generate(
        recipes: recipes,
        profile: profile,
        stock: stock,
        slots: weekSlots(now),
        now: now,
      );
      final ids = menu.entries.map((e) => e.recipe.id).toList();
      expect(ids, isNot(contains(1)));
      expect(ids, isNot(contains(2)));
      expect(ids.toSet().length, ids.length, reason: 'pas de doublon dans la semaine');
      expect(menu.entries.length, 4);
      expect(menu.unfilled.length, 21 - 4);
      // Petit-déjeuner du lundi : l'omelette ; déjeuner du lundi : le poivron qui périme.
      expect(menu.entries.first.slot.meal, MealType.breakfast);
      expect(menu.entries.first.recipe.id, 6);
      expect(menu.entries[1].recipe.id, 3);
      expect(menu.entries.every((e) => e.servings == 2), isTrue);
    });

    test('calorieFit', () {
      expect(calorieFit(800, 800), 1);
      expect(calorieFit(null, 800), 0.5);
      expect(calorieFit(1600, 800), 0);
    });
  });
}
