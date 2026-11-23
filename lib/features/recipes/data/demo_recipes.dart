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
  ];
}

/// Insère les recettes de démo si l'utilisateur n'a encore aucune recette.
Future<void> seedDemoRecipesIfEmpty(RecipeRepository repo, int userId) async {
  if (await repo.countRecipes(userId) > 0) return;
  for (final r in demoRecipes(userId)) {
    await repo.insertRecipe(r);
  }
}
