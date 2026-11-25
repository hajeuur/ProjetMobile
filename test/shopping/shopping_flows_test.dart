import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panier_malin/core/database/app_database.dart';
import 'package:panier_malin/features/recipes/integration/demo_gateways.dart';
import 'package:panier_malin/features/recipes/recipes_module.dart';
import 'package:panier_malin/features/shopping/data/demo_shopping.dart';
import 'package:panier_malin/features/shopping/integration/demo_gateways.dart' as shop;
import 'package:panier_malin/features/shopping/integration/recipes_bridge.dart';
import 'package:panier_malin/features/shopping/services/shopping_devices.dart';
import 'package:panier_malin/features/shopping/services/shopping_service.dart';
import 'package:panier_malin/features/shopping/shopping_module.dart';
import 'package:panier_malin/features/shopping/ui/budget_alert_banner.dart';
import 'package:panier_malin/features/shopping/ui/shopping_home_screen.dart';
import 'package:panier_malin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Parcours complets à l'écran : chaque bouton, menu et boîte de dialogue de
/// la gestion 5. Le test échoue à la moindre exception Flutter (écran rouge).
/// Pas d'accéléromètre en test : source de secousses silencieuse.
class NoShakes implements ShakeSource {
  @override
  Stream<void> shakes() => const Stream<void>.empty();
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late ShoppingService service;
  late SilentVibrator vibrator;

  Future<PanierMalinApp> buildApp(WidgetTester tester, {bool seed = true}) async {
    late PanierMalinApp app;
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      // Repart d'une base vide même si un test précédent a échoué sans la fermer.
      await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      vibrator = SilentVibrator();
      service = ShoppingModule.createService(
        db: db,
        users: shop.DemoUserGateway(),
        products: shop.DemoProductGateway(),
        stores: shop.DemoStoreGateway(),
        vibrator: vibrator,
        tokens: MemoryTokenStore(),
      );
      if (seed) await seedDemoShoppingIfEmpty(service.repository, 1, DateTime.now());
      final recipes = RecipesModule.createService(
        db: db,
        stock: DemoStockGateway(),
        household: DemoHouseholdGateway(),
        shopping: RecipesShoppingBridge(service),
      );
      app = PanierMalinApp(service: recipes, shopping: service, shakeSource: NoShakes(), home: const ShoppingHomeScreen());
    });
    return app;
  }

  /// Laisse SQLite répondre et les animations se terminer.
  Future<void> go(WidgetTester tester) async {
    for (var round = 0; round < 2; round++) {
      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }
  }

  Finder dialogField([int index = 0]) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(index);

  Future<void> tapText(WidgetTester tester, String text) async {
    // Fait défiler jusqu'à l'élément s'il est hors de l'écran.
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await go(tester);
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.ensureVisible(find.byTooltip(tooltip).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tooltip).first);
    await go(tester);
  }

  testWidgets('listes : créer, ajouter, fusionner, modifier, trier, chercher, renommer, archiver, supprimer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = await buildApp(tester, seed: false);
    await tester.runAsync(() => tester.pumpWidget(app));
    await go(tester);
    expect(find.text('Aucune liste en cours'), findsOneWidget);

    // Nouvelle liste (l'écran rouge apparaissait ici).
    await tapText(tester, 'Nouvelle liste');
    await tester.enterText(dialogField(), 'Samedi');
    await tapText(tester, 'Valider');
    expect(find.text('Samedi'), findsOneWidget, reason: 'on arrive sur le détail de la liste');
    expect(find.text('Liste vide'), findsOneWidget);

    // Ajout d'articles, avec fusion des doublons.
    Future<void> add(String label, String qty) async {
      await tester.enterText(find.widgetWithText(TextField, 'Ajouter un article'), label);
      await tester.enterText(find.widgetWithText(TextField, 'Qté'), qty);
      await tester.tap(find.byTooltip('Ajouter'));
      await go(tester);
    }

    await add('Lait', '2 L');
    await add('Eau minérale', '6');
    await add('lait', '1 L');
    expect(find.text('Lait'), findsOneWidget);
    expect(find.text('3 L'), findsOneWidget, reason: '2 L + 1 L fusionnés');

    // Supprimer avec le bouton corbeille, puis « Annuler ».
    await tapTooltip(tester, 'Supprimer');
    expect(find.text('Lait'), findsNothing);
    expect(find.text('« Lait » supprimé.'), findsOneWidget);
    await tapText(tester, 'Annuler');
    expect(find.text('Lait'), findsOneWidget);
    expect(find.text('3 L'), findsOneWidget, reason: 'quantité conservée');

    // Modifier un article.
    await tapTooltip(tester, 'Modifier');
    await tester.enterText(dialogField(0), 'Lait demi-écrémé');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Lait demi-écrémé'), findsOneWidget);

    // Magasin visé puis tri par rayon : à Monoprix, les boissons d'abord.
    await tapText(tester, 'Choisir un magasin');
    await tapText(tester, 'Monoprix Lafayette');
    expect(find.text('Boissons'), findsOneWidget, reason: 'en-tête de rayon');
    final eau = tester.getTopLeft(find.text('Eau minérale')).dy;
    final lait = tester.getTopLeft(find.text('Lait demi-écrémé')).dy;
    expect(eau < lait, isTrue);

    // Cocher, chercher.
    await tester.tap(find.byType(Checkbox).first);
    await go(tester);
    expect(find.text('1/2'), findsOneWidget);
    await tapTooltip(tester, 'Rechercher');
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher un article'), 'eau');
    await go(tester);
    expect(find.text('Lait demi-écrémé'), findsNothing);
    await tapTooltip(tester, 'Fermer la recherche');

    // Menu : renommer, retirer les cochés.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await go(tester);
    await tapText(tester, 'Renommer');
    await tester.enterText(dialogField(), 'Samedi matin');
    await tapText(tester, 'Valider');
    expect(find.text('Samedi matin'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await go(tester);
    await tapText(tester, 'Retirer les articles cochés');
    expect(find.text('Eau minérale'), findsNothing);

    // Retour, archiver depuis la carte, remettre en cours, supprimer.
    await tapTooltip(tester, 'Retour');
    expect(find.text('1 / 1 à prendre'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await go(tester);
    await tapText(tester, 'Archiver (terminée)');
    await tapText(tester, 'Terminées (1)');
    expect(find.text('Samedi matin'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await go(tester);
    await tapText(tester, 'Remettre en cours');
    await tapText(tester, 'En cours (1)');
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await go(tester);
    await tapText(tester, 'Supprimer');
    await tapText(tester, 'Supprimer'); // confirmation
    expect(find.text('Aucune liste en cours'), findsOneWidget);

    // Ruptures prévues (gestion 2) → nouvelle liste en cours.
    await tapTooltip(tester, 'Ajouter les ruptures prévues');
    expect(find.textContaining(RegExp('ruptures? prévues? ajoutées?')), findsOneWidget);
    expect(find.text('2 / 2 à prendre'), findsOneWidget);

    await tester.runAsync(db.close);
  });

  testWidgets('ticket saisi à la main : lignes, total, validation, bilan, détail, correction, suppression',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = await buildApp(tester);
    await tester.runAsync(() => tester.pumpWidget(app));
    await go(tester);

    await tapText(tester, 'Tickets');
    expect(find.text('Carrefour La Marsa'), findsWidgets);
    // Tri par montant puis recherche par magasin.
    await tapText(tester, 'Montant');
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher par magasin'), 'aziza');
    await go(tester);
    expect(find.text('Aziza Ennasr'), findsOneWidget);
    expect(find.text('Monoprix Lafayette'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher par magasin'), '');
    await go(tester);

    // Nouveau ticket à la main.
    await tapText(tester, 'Scanner');
    await tapText(tester, 'Saisir le ticket à la main');
    expect(find.text('Validation du ticket'), findsOneWidget);

    Future<void> addLine(String label, String qty, String price) async {
      await tapText(tester, 'Ajouter une ligne');
      await tester.enterText(dialogField(0), label);
      await tester.enterText(dialogField(1), qty);
      await tester.enterText(dialogField(2), price);
      await tapText(tester, 'Valider');
    }

    await addLine('LAIT DEMI ECR 1L', '2', '2,700');
    await addLine('PAIN BAGUETTE', '1', '0,400');
    expect(find.text('2 lignes'), findsOneWidget);
    expect(find.text('2 × 1,350 DT · Produits laitiers · produit reconnu'), findsOneWidget);

    // Total lu différent de la somme : avertissement.
    await tapText(tester, 'Total lu sur le ticket');
    await tester.enterText(dialogField(), '3,500');
    await tapText(tester, 'Valider');
    expect(find.textContaining('Écart de 0,400 DT'), findsOneWidget);

    // Corriger une ligne mal lue.
    await tapText(tester, 'PAIN BAGUETTE');
    await tester.enterText(dialogField(2), '0,800');
    await tapText(tester, 'Valider');
    expect(find.textContaining('Écart'), findsNothing);

    // Magasin et liste à rapprocher.
    await tester.tap(find.byType(DropdownButtonFormField<int?>).first);
    await go(tester);
    await tapText(tester, 'Carrefour La Marsa');
    await tester.tap(find.byType(DropdownButtonFormField<int?>).last);
    await go(tester);
    await tapText(tester, 'Courses de la semaine');

    await tester.tap(find.textContaining('Valider le ticket'));
    await go(tester);
    expect(find.text('Rapprochement avec la liste'), findsOneWidget);
    expect(find.textContaining(' acheté'), findsWidgets);
    expect(find.textContaining('Oubliés ('), findsOneWidget);
    await tester.tap(find.textContaining('Terminer'));
    await go(tester);

    // Le budget du mois franchit le budget : vibration + bannière d'alerte
    // (au-dessus de tous les écrans), refermée à la main.
    expect(vibrator.calls, isNotEmpty);
    final banner = find.byType(BudgetAlertBanner);
    expect(banner, findsOneWidget);
    expect(find.descendant(of: banner, matching: find.textContaining('du budget utilisé')), findsOneWidget);
    await tester.tap(find.descendant(of: banner, matching: find.byIcon(Icons.close)));
    await go(tester);
    expect(find.byType(BudgetAlertBanner), findsNothing);

    // Détail du ticket (le plus récent, en tête du tri par date).
    await tapText(tester, 'Date');
    await tester.tap(find.text('3,500 DT').first);
    await go(tester);
    expect(find.text('Liste : Courses de la semaine'), findsOneWidget);
    await tapText(tester, 'PAIN BAGUETTE');
    await tapText(tester, 'Corriger la ligne');
    await tester.enterText(dialogField(0), 'PAIN DE MIE');
    await tapText(tester, 'Valider');
    expect(find.text('PAIN DE MIE'), findsOneWidget);
    await tester.tap(find.textContaining('Total :'));
    await go(tester);
    await tester.enterText(dialogField(), '3,600');
    await tapText(tester, 'Valider');
    expect(find.text('Total : 3,600 DT'), findsOneWidget);
    await tapText(tester, 'Rapprocher');
    await tapText(tester, 'Courses de la semaine');
    expect(find.text('Rapprochement avec la liste'), findsOneWidget);
    await tester.tap(find.textContaining('Terminer'));
    await go(tester);

    // Ajouter une ligne puis la supprimer.
    await tapTooltip(tester, 'Ajouter une ligne');
    await tester.enterText(dialogField(0), 'EAU 1,5L');
    await tester.enterText(dialogField(2), '0,900');
    await tapText(tester, 'Valider');
    expect(find.text('3 lignes — touchez pour corriger ou comparer'), findsOneWidget);
    await tapText(tester, 'EAU 1,5L');
    await tapText(tester, 'Supprimer la ligne');
    expect(find.text('2 lignes — touchez pour corriger ou comparer'), findsOneWidget);

    // Comparaison Open Prices sans code-barres : message clair, pas de plantage.
    await tapText(tester, 'PAIN DE MIE');
    await tapText(tester, 'Comparer avec Open Prices');
    expect(find.text('Comparaison impossible'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await go(tester);

    // Supprimer le ticket.
    await tapTooltip(tester, 'Supprimer le ticket');
    await tapText(tester, 'Supprimer');
    expect(find.text('Tickets de caisse'), findsOneWidget);
    expect(find.text('3,600 DT'), findsNothing);

    await tester.runAsync(db.close);
  });

  testWidgets('budget, alertes de prix, comparateur et réglages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = await buildApp(tester);
    await tester.runAsync(() => tester.pumpWidget(app));
    await go(tester);

    await tapText(tester, 'Budget');
    expect(find.text('sur 140,000 DT'), findsOneWidget);
    expect(find.text('Seuil d\'alerte atteint'), findsOneWidget);
    expect(vibrator.calls, isEmpty, reason: 'pas d\'alerte à l\'ouverture de l\'écran, seulement à l\'enregistrement d\'un ticket');
    // Jauge, bannière cohérente (seuil + dépassement prévu), conseil du jour.
    expect(find.text('86 %'), findsOneWidget);
    expect(find.text('Seuil d\'alerte franchi · dépassement prévu'), findsOneWidget);
    expect(find.textContaining('86 % du budget utilisé'), findsOneWidget);
    expect(find.textContaining('Conseil du jour'), findsOneWidget);
    // Graphique : légende et mois distincts.
    expect(find.text('Dépensé'), findsOneWidget);
    expect(find.text('Budget'), findsWidgets);
    expect(find.text('juin'), findsOneWidget);
    expect(find.text('juil.'), findsOneWidget);
    // Camembert : regroupement et détail au toucher.
    await tester.scrollUntilVisible(find.text('Autres'), 200);
    expect(find.text('Autres'), findsOneWidget);
    await tapText(tester, 'Autres');
    expect(find.textContaining('Autres : '), findsOneWidget);
    // Badges.
    expect(find.text('Badges et défis'), findsOneWidget);
    expect(find.text('Budget tenu 3 mois'), findsOneWidget);

    // Modifier le budget.
    await tapTooltip(tester, 'Définir le budget');
    await tester.enterText(dialogField(), '300');
    await tapText(tester, 'Enregistrer');
    expect(find.text('sur 300,000 DT'), findsOneWidget);
    expect(find.text('Dans le budget'), findsOneWidget);

    // Mois précédent puis retour (on remonte d'abord en haut de la page).
    await tester.dragUntilVisible(find.byTooltip('Mois précédent'), find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tapTooltip(tester, 'Mois précédent');
    expect(find.text('Dépenses par mois'), findsOneWidget);
    await tapTooltip(tester, 'Mois suivant');

    // Tickets regroupés par mois avec le total.
    await tapText(tester, 'Tickets');
    expect(find.textContaining('Novembre 2026 : '), findsOneWidget);

    // Alertes de prix : formulation, fiabilité, courbe, actions.
    await tapText(tester, 'Prix');
    expect(find.text('TOMATES'), findsOneWidget);
    expect(find.textContaining('basé sur 1 achat'), findsWidgets);
    expect(find.text('Fiabilité faible'), findsWidgets);
    await tapText(tester, 'HUILE OLIVE 1L');
    expect(find.textContaining('Évolution du prix'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await go(tester);
    await tester.ensureVisible(find.text('Ajouter à ma liste').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter à ma liste').first);
    await go(tester);
    expect(find.text('Déjà dans la liste en cours.'), findsOneWidget, reason: 'les tomates sont déjà sur la liste');
    await tester.ensureVisible(find.text('Où le payer moins cher ?').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Où le payer moins cher ?').first);
    await go(tester);
    expect(find.text('Comparateur de magasins'), findsOneWidget);
    expect(find.textContaining('Le moins cher pour vous : Carrefour La Marsa'), findsWidgets);
    expect(find.textContaining('« Courses de la semaine » dans chaque magasin'), findsOneWidget);
    await tapTooltip(tester, 'Retour');

    // Réglages : bouton de test du vibreur, couper le vibreur, connexion Open Prices annulée.
    await tapText(tester, 'Listes');
    await tapTooltip(tester, 'Réglages');
    await tapText(tester, 'Tester la vibration');
    expect(vibrator.calls.length, 1, reason: 'aucune vibration avant : l\'ouverture de Budget n\'alerte pas');
    // Démonstration visible même sur émulateur : bannière + téléphone qui vibre.
    expect(find.text('Test de l\'alerte de budget'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(BudgetAlertBanner), matching: find.byIcon(Icons.close)));
    await go(tester);
    await tester.scrollUntilVisible(find.text('Vibreur'), -200);
    await tapText(tester, 'Vibreur');
    // « Partager mes prix » : interrupteur, puis connexion Open Food Facts.
    expect(find.text('Se connecter à Open Food Facts'), findsNothing);
    await tester.scrollUntilVisible(find.text('Partager mes prix'), 200);
    await tapText(tester, 'Partager mes prix');
    await tester.scrollUntilVisible(find.text('Se connecter à Open Food Facts'), 200);
    await tapText(tester, 'Se connecter à Open Food Facts');
    await tester.enterText(dialogField(0), 'moi');
    await tapText(tester, 'Annuler');
    final settings = await tester.runAsync(service.settings);
    expect(settings!.vibration, isFalse);
    expect(settings.sharePrices, isTrue);

    await tester.runAsync(db.close);
  });

  testWidgets('comparateur depuis le détail d\'une liste', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = await buildApp(tester);
    await tester.runAsync(() => tester.pumpWidget(app));
    await go(tester);
    await tapText(tester, 'Courses de la semaine');
    await tapTooltip(tester, 'Comparer les magasins');
    expect(find.textContaining('Le moins cher pour vous'), findsWidgets);
    expect(find.text('Produit par produit'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
