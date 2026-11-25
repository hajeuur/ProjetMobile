import '../models/meal_plan.dart';
import '../models/recipe.dart';
import 'recipe_repository.dart';

/// Recettes personnelles insérées au premier lancement, pour que la gestion
/// soit utilisable hors ligne et pour la démo. La recette aux cacahuètes sert
/// à montrer le filtrage par allergie du foyer.
List<Recipe> demoRecipes(int userId) {
  RecipeIngredient i(String name, [double? q, String? unit]) =>
      RecipeIngredient(name: name, quantity: q, unit: unit);
  List<RecipeStep> steps(List<(String, int?)> s) => [
        for (var n = 0; n < s.length; n++) RecipeStep(number: n + 1, text: s[n].$1, durationMin: s[n].$2),
      ];

  return [
    Recipe(
      userId: userId,
      title: 'Chakchouka',
      category: 'Plat',
      prepTimeMin: 30,
      baseServings: 3,
      caloriesPerServing: 320,
      ingredients: [i('Tomate', 4, 'pièce'), i('Poivron', 2, 'pièce'), i('Oignon', 1, 'pièce'), i('Ail', 2, 'gousse'), i('Oeuf', 4, 'pièce'), i('Huile d\'olive', 3, 'cas'), i('Sel'), i('Cumin')],
      steps: steps([
        ('Émincer l\'oignon et faire revenir dans l\'huile d\'olive.', 5),
        ('Ajouter les poivrons en lanières et l\'ail écrasé, cuire 10 minutes.', 10),
        ('Ajouter les tomates coupées, le sel et le cumin, laisser mijoter 10 minutes.', 10),
        ('Creuser des puits, casser les oeufs dedans et couvrir 5 minutes.', 5),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Couscous au poulet',
      category: 'Plat',
      prepTimeMin: 75,
      baseServings: 4,
      caloriesPerServing: 650,
      ingredients: [i('Semoule', 400, 'g'), i('Poulet', 600, 'g'), i('Pois chiches', 150, 'g'), i('Carotte', 3, 'pièce'), i('Tomate', 2, 'pièce'), i('Oignon', 1, 'pièce'), i('Huile d\'olive', 4, 'cas'), i('Harissa', 1, 'cac')],
      steps: steps([
        ('Faire revenir le poulet et l\'oignon dans l\'huile.', 10),
        ('Ajouter les tomates, la harissa et couvrir d\'eau.', null),
        ('Ajouter carottes et pois chiches, cuire 45 minutes.', 45),
        ('Cuire la semoule à la vapeur au-dessus de la sauce.', 20),
        ('Servir la semoule arrosée de sauce avec le poulet et les légumes.', null),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Riz au poulet',
      category: 'Plat',
      prepTimeMin: 40,
      baseServings: 3,
      caloriesPerServing: 580,
      ingredients: [i('Riz', 300, 'g'), i('Poulet', 400, 'g'), i('Oignon', 1, 'pièce'), i('Ail', 2, 'gousse'), i('Huile d\'olive', 2, 'cas')],
      steps: steps([
        ('Dorer le poulet en morceaux avec l\'oignon et l\'ail.', 10),
        ('Ajouter le riz, couvrir d\'eau deux fois son volume.', null),
        ('Cuire à couvert 20 minutes à feu doux.', 20),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Lablabi',
      category: 'Soupe',
      prepTimeMin: 30,
      baseServings: 3,
      caloriesPerServing: 450,
      ingredients: [i('Pois chiches', 300, 'g'), i('Ail', 3, 'gousse'), i('Cumin', 1, 'cac'), i('Pain', 1, 'pièce'), i('Huile d\'olive', 3, 'cas'), i('Oeuf', 3, 'pièce')],
      steps: steps([
        ('Cuire les pois chiches dans l\'eau avec l\'ail 20 minutes.', 20),
        ('Émietter le pain dans les bols.', null),
        ('Verser le bouillon, ajouter cumin, huile et un oeuf poché.', 5),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Salade méchouia',
      category: 'Entrée',
      prepTimeMin: 35,
      baseServings: 4,
      caloriesPerServing: 180,
      ingredients: [i('Poivron', 3, 'pièce'), i('Tomate', 3, 'pièce'), i('Ail', 2, 'gousse'), i('Huile d\'olive', 3, 'cas'), i('Thon', 160, 'g')],
      steps: steps([
        ('Griller poivrons et tomates 20 minutes, puis les peler.', 20),
        ('Hacher finement avec l\'ail.', 5),
        ('Assaisonner d\'huile d\'olive et garnir de thon.', null),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Omelette aux tomates',
      category: 'Breakfast',
      prepTimeMin: 15,
      baseServings: 2,
      caloriesPerServing: 280,
      ingredients: [i('Oeuf', 4, 'pièce'), i('Tomate', 2, 'pièce'), i('Huile d\'olive', 1, 'cas'), i('Sel')],
      steps: steps([
        ('Faire fondre les tomates en dés dans l\'huile 5 minutes.', 5),
        ('Verser les oeufs battus, cuire 3 minutes.', 3),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Bouillie de semoule au lait',
      category: 'Breakfast',
      prepTimeMin: 10,
      baseServings: 2,
      caloriesPerServing: 350,
      ingredients: [i('Lait', 500, 'ml'), i('Semoule', 60, 'g'), i('Sucre', 30, 'g')],
      steps: steps([
        ('Chauffer le lait avec le sucre.', 5),
        ('Verser la semoule en pluie en remuant, cuire 3 minutes.', 3),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Pâtes au thon',
      category: 'Plat',
      prepTimeMin: 20,
      baseServings: 3,
      caloriesPerServing: 560,
      ingredients: [i('Pâtes', 300, 'g'), i('Thon', 160, 'g'), i('Tomate', 3, 'pièce'), i('Ail', 1, 'gousse'), i('Huile d\'olive', 2, 'cas')],
      steps: steps([
        ('Cuire les pâtes 10 minutes dans l\'eau salée.', 10),
        ('Faire une sauce avec tomates, ail et huile, 10 minutes.', 10),
        ('Ajouter le thon et mélanger avec les pâtes.', null),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Soupe de lentilles',
      category: 'Soupe',
      prepTimeMin: 40,
      baseServings: 4,
      caloriesPerServing: 300,
      ingredients: [i('Lentilles', 250, 'g'), i('Carotte', 2, 'pièce'), i('Oignon', 1, 'pièce'), i('Cumin', 1, 'cac'), i('Huile d\'olive', 2, 'cas')],
      steps: steps([
        ('Faire revenir oignon et carottes 5 minutes.', 5),
        ('Ajouter lentilles, cumin et 1 litre d\'eau, cuire 30 minutes.', 30),
        ('Mixer et rectifier l\'assaisonnement.', null),
      ]),
    ),
    Recipe(
      userId: userId,
      title: 'Poulet sauce cacahuète',
      category: 'Plat',
      prepTimeMin: 35,
      baseServings: 3,
      caloriesPerServing: 620,
      ingredients: [i('Poulet', 450, 'g'), i('Beurre de cacahuète', 80, 'g'), i('Oignon', 1, 'pièce'), i('Riz', 250, 'g')],
      steps: steps([
        ('Dorer le poulet et l\'oignon.', 10),
        ('Ajouter le beurre de cacahuète délayé dans de l\'eau, mijoter 20 minutes.', 20),
        ('Servir avec le riz.', null),
      ]),
    ),
    ...moreDemoRecipes(userId),
  ];
}

/// Recettes de démo supplémentaires (version 2) : assez de recettes compatibles
/// avec le foyer pour remplir les 21 créneaux du menu et tester tri et stats.
List<Recipe> moreDemoRecipes(int userId) {
  RecipeIngredient i(String name, [double? q, String? unit]) =>
      RecipeIngredient(name: name, quantity: q, unit: unit);
  List<RecipeStep> steps(List<(String, int?)> s) => [
        for (var n = 0; n < s.length; n++) RecipeStep(number: n + 1, text: s[n].$1, durationMin: s[n].$2),
      ];
  Recipe r(String title, String category, int prep, int servings, double kcal, List<RecipeIngredient> ingredients,
          List<(String, int?)> s) =>
      Recipe(
        userId: userId,
        title: title,
        category: category,
        prepTimeMin: prep,
        baseServings: servings,
        caloriesPerServing: kcal,
        ingredients: ingredients,
        steps: steps(s),
      );

  return [
    // Petits-déjeuners
    r('Crêpes', 'Breakfast', 25, 4, 260, [i('Farine', 250, 'g'), i('Oeuf', 3, 'pièce'), i('Lait', 500, 'ml'), i('Sucre', 30, 'g'), i('Huile d\'olive', 1, 'cas')], [
      ('Mélanger farine, sucre et oeufs, puis ajouter le lait petit à petit.', 5),
      ('Laisser reposer la pâte 10 minutes.', 10),
      ('Cuire les crêpes une à une dans une poêle huilée.', 10),
    ]),
    r('Bsissa', 'Breakfast', 5, 2, 380, [i('Farine de blé grillé', 80, 'g'), i('Huile d\'olive', 2, 'cas'), i('Miel', 2, 'cas'), i('Eau', 100, 'ml')], [
      ('Mélanger la farine avec l\'eau et l\'huile.', 3),
      ('Ajouter le miel et servir.', null),
    ]),
    r('Yaourt aux fruits et flocons d\'avoine', 'Breakfast', 5, 2, 290, [i('Yaourt', 2, 'pièce'), i('Flocons d\'avoine', 60, 'g'), i('Banane', 1, 'pièce'), i('Miel', 1, 'cas')], [
      ('Couper la banane en rondelles.', null),
      ('Mélanger yaourt, flocons, banane et miel.', null),
    ]),
    r('Pain perdu', 'Breakfast', 15, 2, 340, [i('Pain', 4, 'tranche'), i('Oeuf', 2, 'pièce'), i('Lait', 200, 'ml'), i('Sucre', 20, 'g'), i('Beurre', 15, 'g')], [
      ('Battre oeufs, lait et sucre.', null),
      ('Tremper les tranches de pain.', null),
      ('Dorer au beurre 3 minutes de chaque côté.', 6),
    ]),
    r('Oeufs brouillés et pain grillé', 'Breakfast', 10, 2, 310, [i('Oeuf', 4, 'pièce'), i('Pain', 2, 'tranche'), i('Beurre', 10, 'g'), i('Sel')], [
      ('Griller le pain.', 3),
      ('Cuire les oeufs battus au beurre en remuant 4 minutes.', 4),
    ]),
    r('Smoothie banane dattes', 'Breakfast', 5, 2, 240, [i('Banane', 2, 'pièce'), i('Dattes', 6, 'pièce'), i('Lait', 400, 'ml')], [
      ('Dénoyauter les dattes.', null),
      ('Mixer tous les ingrédients 1 minute.', 1),
    ]),
    // Plats
    r('Tajine de poulet aux olives', 'Plat', 60, 4, 520, [i('Poulet', 800, 'g'), i('Olives vertes', 150, 'g'), i('Citron confit', 1, 'pièce'), i('Oignon', 2, 'pièce'), i('Ail', 3, 'gousse'), i('Huile d\'olive', 3, 'cas'), i('Curcuma', 1, 'cac')], [
      ('Faire revenir le poulet, l\'oignon et l\'ail avec le curcuma.', 10),
      ('Couvrir d\'eau et mijoter 35 minutes.', 35),
      ('Ajouter olives et citron confit, cuire encore 10 minutes.', 10),
    ]),
    r('Kafteji', 'Plat', 45, 4, 480, [i('Pomme de terre', 3, 'pièce'), i('Poivron', 2, 'pièce'), i('Courgette', 2, 'pièce'), i('Potiron', 300, 'g'), i('Oeuf', 4, 'pièce'), i('Huile d\'olive', 5, 'cas'), i('Harissa', 1, 'cac')], [
      ('Frire séparément les légumes coupés en morceaux.', 25),
      ('Frire les oeufs.', 5),
      ('Hacher le tout grossièrement avec la harissa.', 5),
    ]),
    r('Spaghetti bolognaise', 'Plat', 40, 4, 610, [i('Spaghetti', 400, 'g'), i('Viande hachée', 400, 'g'), i('Tomate', 4, 'pièce'), i('Oignon', 1, 'pièce'), i('Ail', 2, 'gousse'), i('Huile d\'olive', 2, 'cas')], [
      ('Faire revenir oignon, ail et viande hachée 10 minutes.', 10),
      ('Ajouter les tomates et mijoter 20 minutes.', 20),
      ('Cuire les spaghetti 10 minutes et mélanger avec la sauce.', 10),
    ]),
    r('Poisson grillé et légumes', 'Plat', 30, 2, 420, [i('Daurade', 2, 'pièce'), i('Courgette', 1, 'pièce'), i('Poivron', 1, 'pièce'), i('Citron', 1, 'pièce'), i('Huile d\'olive', 2, 'cas'), i('Sel')], [
      ('Assaisonner les poissons avec citron, sel et huile.', 5),
      ('Griller les poissons 8 minutes de chaque côté.', 16),
      ('Griller les légumes en tranches 10 minutes.', 10),
    ]),
    r('Mloukhia', 'Plat', 150, 4, 560, [i('Poudre de mloukhia', 60, 'g'), i('Boeuf', 500, 'g'), i('Huile d\'olive', 200, 'ml'), i('Ail', 4, 'gousse'), i('Laurier', 2, 'feuille')], [
      ('Délayer la poudre dans l\'huile et chauffer 10 minutes.', 10),
      ('Ajouter eau, viande, ail et laurier.', null),
      ('Mijoter à feu doux 2 heures en remuant.', 120),
    ]),
    r('Ojja merguez', 'Plat', 25, 3, 540, [i('Merguez', 6, 'pièce'), i('Tomate', 4, 'pièce'), i('Oeuf', 4, 'pièce'), i('Harissa', 1, 'cac'), i('Ail', 2, 'gousse'), i('Huile d\'olive', 2, 'cas')], [
      ('Dorer les merguez coupées 5 minutes.', 5),
      ('Ajouter tomates, ail et harissa, cuire 10 minutes.', 10),
      ('Casser les oeufs dessus et cuire 5 minutes.', 5),
    ]),
    r('Gratin de pâtes au poulet', 'Plat', 45, 4, 650, [i('Pâtes', 400, 'g'), i('Poulet', 300, 'g'), i('Fromage râpé', 150, 'g'), i('Crème', 200, 'ml'), i('Oignon', 1, 'pièce')], [
      ('Cuire les pâtes 10 minutes.', 10),
      ('Faire revenir le poulet et l\'oignon 10 minutes.', 10),
      ('Mélanger avec la crème, couvrir de fromage et gratiner 20 minutes.', 20),
    ]),
    r('Riz sauté aux légumes', 'Plat', 25, 3, 430, [i('Riz', 250, 'g'), i('Carotte', 2, 'pièce'), i('Petits pois', 150, 'g'), i('Oeuf', 2, 'pièce'), i('Sauce soja', 2, 'cas'), i('Huile d\'olive', 2, 'cas')], [
      ('Cuire le riz 15 minutes et le laisser refroidir.', 15),
      ('Sauter carottes et petits pois 5 minutes.', 5),
      ('Ajouter le riz, les oeufs battus et la sauce soja, sauter 3 minutes.', 3),
    ]),
    r('Burger maison', 'Plat', 25, 4, 690, [i('Pain burger', 4, 'pièce'), i('Viande hachée', 500, 'g'), i('Fromage', 4, 'tranche'), i('Tomate', 1, 'pièce'), i('Salade', 1, 'pièce'), i('Oignon', 1, 'pièce')], [
      ('Former 4 steaks avec la viande hachée.', 5),
      ('Cuire les steaks 4 minutes de chaque côté, ajouter le fromage.', 8),
      ('Monter les burgers avec salade, tomate et oignon.', null),
    ]),
    r('Lentilles corail au curry', 'Plat', 30, 4, 390, [i('Lentilles corail', 250, 'g'), i('Lait de coco', 400, 'ml'), i('Oignon', 1, 'pièce'), i('Curry', 2, 'cac'), i('Tomate', 2, 'pièce')], [
      ('Faire revenir l\'oignon avec le curry.', 5),
      ('Ajouter lentilles, tomates, lait de coco et 300 ml d\'eau.', null),
      ('Cuire 20 minutes en remuant.', 20),
    ]),
    // Soupes et entrées
    r('Chorba frik', 'Soupe', 50, 4, 330, [i('Frik', 100, 'g'), i('Agneau', 300, 'g'), i('Tomate', 2, 'pièce'), i('Oignon', 1, 'pièce'), i('Pois chiches', 100, 'g'), i('Huile d\'olive', 2, 'cas')], [
      ('Faire revenir l\'agneau et l\'oignon 10 minutes.', 10),
      ('Ajouter tomates, pois chiches et 1,5 litre d\'eau, cuire 20 minutes.', 20),
      ('Ajouter le frik et cuire encore 15 minutes.', 15),
    ]),
    r('Velouté de potiron', 'Soupe', 35, 4, 210, [i('Potiron', 800, 'g'), i('Pomme de terre', 1, 'pièce'), i('Oignon', 1, 'pièce'), i('Crème', 100, 'ml')], [
      ('Couper les légumes en cubes.', 5),
      ('Cuire dans 1 litre d\'eau 25 minutes.', 25),
      ('Mixer avec la crème.', null),
    ]),
    r('Salade tunisienne', 'Entrée', 15, 4, 220, [i('Tomate', 3, 'pièce'), i('Concombre', 1, 'pièce'), i('Oignon', 1, 'pièce'), i('Thon', 160, 'g'), i('Oeuf', 2, 'pièce'), i('Huile d\'olive', 3, 'cas')], [
      ('Cuire les oeufs durs 10 minutes.', 10),
      ('Couper tomates, concombre et oignon en petits dés.', 5),
      ('Ajouter thon, oeufs et huile d\'olive.', null),
    ]),
    r('Brick au thon', 'Entrée', 20, 4, 290, [i('Feuilles de brick', 4, 'pièce'), i('Thon', 160, 'g'), i('Oeuf', 4, 'pièce'), i('Persil'), i('Huile de friture', 500, 'ml')], [
      ('Garnir chaque feuille de thon et de persil.', null),
      ('Casser un oeuf au centre et plier en triangle.', null),
      ('Frire 2 minutes de chaque côté.', 4),
    ]),
    // Desserts
    r('Assida zgougou', 'Dessert', 90, 6, 450, [i('Graines de pin d\'Alep', 250, 'g'), i('Farine', 100, 'g'), i('Sucre', 150, 'g'), i('Lait', 500, 'ml'), i('Crème', 200, 'ml')], [
      ('Mixer les graines et filtrer pour obtenir un jus.', 20),
      ('Cuire le jus avec la farine et le sucre 45 minutes en remuant.', 45),
      ('Napper de crème au lait refroidie.', 20),
    ]),
    r('Salade de fruits', 'Dessert', 10, 4, 150, [i('Pomme', 2, 'pièce'), i('Orange', 2, 'pièce'), i('Banane', 2, 'pièce'), i('Sucre', 20, 'g')], [
      ('Couper les fruits en morceaux.', 10),
      ('Saupoudrer de sucre et mettre au frais.', null),
    ]),
  ];
}

/// Version des données de démo : à augmenter quand on ajoute des recettes de
/// démo, pour que les bases déjà créées les reçoivent aussi.
const _demoSeedVersion = 2;
const _demoSeedKey = 'demo.seed_version';

/// Insère les recettes de démo manquantes (comparaison par titre).
/// Au premier lancement : toutes les recettes de démo. Après une mise à jour des
/// données de démo : seulement les nouvelles. Une recette de démo supprimée par
/// l'utilisateur n'est pas recréée tant que la version ne change pas.
Future<void> seedDemoRecipesIfEmpty(RecipeRepository repo, int userId) async {
  final stored = int.tryParse(await repo.getSetting(_demoSeedKey) ?? '');
  // Bases créées avant le numéro de version : elles ont déjà la version 1.
  final version = stored ?? (await repo.countRecipes(userId) > 0 ? 1 : 0);
  if (version >= _demoSeedVersion) return;

  final all = demoRecipes(userId);
  final toInsert = version == 0 ? all : moreDemoRecipes(userId);
  final existing = (await repo.listRecipes(userId)).map((r) => r.title).toSet();
  for (final r in toInsert) {
    if (!existing.contains(r.title)) await repo.insertRecipe(r);
  }
  await repo.setSetting(_demoSeedKey, '$_demoSeedVersion');
}

/// Historique de repas cuisinés sur les 3 semaines passées et jusqu'à hier,
/// pour que l'écran Statistiques ait des données. Ne remplit que les créneaux
/// libres et ne retire rien du stock (ce sont des repas « passés »).
/// Ne s'exécute qu'une fois.
Future<int> seedDemoMealHistory(RecipeRepository repo, int userId, DateTime today) async {
  const key = 'demo.history_seeded';
  if (await repo.getSetting(key) != null) return 0;

  final recipes = (await repo.listRecipes(userId)).where((r) => r.id != null && r.title != 'Poulet sauce cacahuète').toList();
  bool isBreakfast(Recipe r) => r.category == 'Breakfast';
  final breakfasts = recipes.where(isBreakfast).toList();
  final mains = recipes.where((r) => !isBreakfast(r) && r.category != 'Dessert').toList();
  if (breakfasts.isEmpty || mains.isEmpty) return 0;

  final from = addDays(weekStartOf(today), -21);
  final to = addDays(dateOnly(today), -1);
  final taken = {
    for (final p in await repo.mealPlansBetween(userId, from, to)) '${dateKey(p.date)}|${p.meal.dbValue}',
  };

  // Générateur déterministe : toujours le même historique.
  var seed = 7;
  int next(int max) => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) % max;

  var n = 0;
  for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
    for (final meal in MealType.values) {
      if (taken.contains('${dateKey(d)}|${meal.dbValue}')) continue;
      if (next(100) < 20) continue; // ~20 % de repas non planifiés
      final pool = meal == MealType.breakfast ? breakfasts : mains;
      final recipe = pool[next(pool.length)];
      await repo.insertMealPlan(MealPlan(
        date: d,
        meal: meal,
        recipeId: recipe.id!,
        servings: 3,
        status: MealStatus.cooked,
        cookedAt: DateTime(d.year, d.month, d.day, switch (meal) { MealType.breakfast => 8, MealType.lunch => 13, MealType.dinner => 20 }),
      ));
      n++;
    }
  }
  await repo.setSetting(key, '1');
  return n;
}
