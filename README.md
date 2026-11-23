# PanierMalin

Application mobile Flutter d'assistance aux courses et à la cuisine (voir le cahier des charges).
Ce dépôt contient pour l'instant la **gestion 3 — Recettes**, utilisable seule grâce à des passerelles de démo.

```
flutter pub get
flutter run          # Android de préférence (capteur de proximité, micro)
flutter test         # tests de la logique, du service (SQLite en mémoire) et de l'écran d'accueil
```

## Gestion 3 — Recettes

| Exigence du cahier des charges | Où |
|---|---|
| Tables `recipes`, `recipe_ingredients`, `recipe_steps`, `meal_plans` | `lib/features/recipes/data/recipe_schema.dart`, `recipe_repository.dart` |
| CRUD recette personnelle (ingrédients + étapes) | `ui/recipe_edit_screen.dart`, `services/recipe_service.dart` |
| Import TheMealDB (nom, catégorie, ingrédient) + cache hors ligne | `data/themealdb_api.dart`, `ui/recipe_import_screen.dart` |
| Planifier, déplacer, supprimer un repas | `ui/week_plan_screen.dart`, `viewmodels/meal_plan_view_model.dart` |
| Marquer cuisiné → sortie de stock (gestion 2) | `RecipeService.markCooked` |
| Proximité : 1 passage = suivant, 2 passages = précédent | `logic/hand_wave_detector.dart` |
| Commandes vocales (« suivant », « répète », « précédent », « minuteur 10 minutes ») | `logic/voice_commands.dart` |
| Lecture à voix haute + sonnerie du minuteur | `services/cooking_devices.dart` |
| Score anti-gaspi (poids double si péremption ≤ 3 j) | `logic/stock_analysis.dart` |
| Menu hebdomadaire automatique (calories, allergies/régimes, anti-gaspi, variété) | `logic/menu_generator.dart`, `ui/menu_generation_screen.dart` |
| Ajustement des portions | `logic/portion_scaler.dart` |
| Ingrédients manquants → liste de courses (gestion 5) | `RecipeService.sendMissingToShopping` / `sendWeekMissingToShopping` |
| Tri (temps, calories, anti-gaspi), recherche (titre, ingrédient) | `viewmodels/recipe_list_view_model.dart` |
| Statistiques (plus cuisinées, calories moyennes par repas) | `ui/recipe_stats_screen.dart` |
| Capteurs désactivables, mode grand format | `services/cooking_settings.dart` (bouton « Capteurs » du mode cuisine) |

TheMealDB ne fournit ni calories ni portions : à l'import, on suppose 4 portions et les calories sont
estimées (`logic/calorie_estimator.dart`). Elles restent modifiables dans la fiche.

## Intégration avec les autres gestions

La gestion Recettes ne touche jamais aux tables des autres gestions. Elle passe par trois interfaces
définies dans `lib/features/recipes/integration/gateways.dart` :

| Interface | Fournie par | Utilisée pour |
|---|---|---|
| `HouseholdGateway` | Gestion 1 — Utilisateurs et Foyer | utilisateur connecté, allergies (union), régimes (intersection), objectif calorique |
| `StockGateway` | Gestion 2 — Produits et Stock | lire le stock, enregistrer une sortie « consommé » |
| `ShoppingGateway` | Gestion 5 — Courses et Budget | ajouter des articles d'origine « recette » à la liste en cours |

En attendant, `integration/demo_gateways.dart` fournit des versions en mémoire. Pour brancher les
vraies, il suffit de les passer à `RecipesModule.createService(...)` dans `lib/main.dart`.

Dans l'autre sens, la gestion 6 (Activité et Santé) lit les calories consommées avec
`RecipeService.caloriesConsumedPerPerson(date)`.

Base de données : `lib/core/database/app_database.dart` ouvre la base unique ; chaque gestion y ajoute
son `XxxSchema.create(db)`.
