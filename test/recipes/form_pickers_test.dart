import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/recipes/services/recipe_service.dart';
import 'package:panier_malin/features/recipes/ui/form_pickers.dart';
import 'package:panier_malin/features/recipes/ui/recipe_edit_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('nombres : virgule et point acceptés', () {
    expect(parseDecimal('320,5'), 320.5);
    expect(parseDecimal(' 0.75 '), 0.75);
    expect(parseWhole('30'), 30);
    expect(parseWhole('30,0'), 30);
    expect(parseWhole('30,5'), isNull);
    expect(formatDecimal(1.5), '1,5');
    expect(formatDecimal(200), '200');
    expect(validateDecimal('abc'), isNotNull);
    expect(validateDecimal(''), isNull);
  });

  Widget host(TextEditingController c, List<ComboOption> options) => MaterialApp(
        home: Scaffold(body: ComboTextField(controller: c, options: options, label: 'Unité')),
      );

  testWidgets('combo : choisir dans la liste', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c, unitOptions));
    await tester.tap(find.byTooltip('Choisir dans la liste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg — kilogramme'));
    await tester.pumpAndSettle();
    expect(c.text, 'kg'); // la valeur courte est écrite, pas le libellé
  });

  testWidgets('combo : taper une valeur absente de la liste', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c, unitOptions));
    await tester.enterText(find.byType(TextFormField), 'sachet');
    expect(c.text, 'sachet');
    // La liste reste disponible ensuite.
    await tester.tap(find.byTooltip('Choisir dans la liste'));
    await tester.pumpAndSettle();
    expect(find.text('g — gramme'), findsOneWidget);
  });

  testWidgets('formulaire : quantité avec virgule + unité de la liste enregistrées', (tester) async {
    sqfliteFfiInit();
    late RecipeService service;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      service = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: DemoShoppingGateway(),
      );
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(Provider<RecipeService>.value(
      value: service,
      child: const MaterialApp(home: RecipeEditScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Titre *'), 'Riz test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Catégorie'), 'Plat');
    await tester.enterText(find.widgetWithText(TextFormField, 'Ingrédient 1'), 'Riz');
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantité'), '1,5');

    // Unité choisie dans la liste.
    await tester.tap(find.descendant(
      of: find.widgetWithText(TextFormField, 'Unité'),
      matching: find.byTooltip('Choisir dans la liste'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg — kilogramme'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    final saved = await tester.runAsync(() => service.recipes());
    final r = saved!.single;
    expect(r.title, 'Riz test');
    expect(r.category, 'Plat');
    expect(r.ingredients.single.quantity, 1.5);
    expect(r.ingredients.single.unit, 'kg');
  });
}
