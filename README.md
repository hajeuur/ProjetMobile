# PanierMalin

Application mobile Flutter d'assistance aux courses et à la cuisine (voir le cahier des charges).
Ce dépôt contient la **gestion 5 — Courses et Budget** (branche `Courses`) et la **gestion 3 — Recettes**,
utilisables seules grâce à des passerelles de démo, et déjà reliées entre elles.

```
flutter pub get
flutter run          # Android de préférence (caméra, vibreur, proximité, micro)
flutter test         # logique, services (SQLite en mémoire) et écrans
```

L'écran d'accueil donne accès à chaque gestion présente.

## Gestion 5 — Courses et Budget

Explication détaillée : [docs/explication_gestion_courses.md](docs/explication_gestion_courses.md).

| Exigence du cahier des charges | Où (`lib/features/shopping/`) |
|---|---|
| Tables `shopping_lists`, `shopping_items`, `receipts`, `receipt_lines`, `budgets` | `data/shopping_schema.dart`, `data/shopping_repository.dart` |
| CRUD listes et articles (créer, renommer, archiver, supprimer, cocher) | `ui/shopping_lists_screen.dart`, `ui/list_detail_screen.dart` |
| Ticket par photo ou à la main, correction d'une ligne, suppression | `ui/receipt_scan_screen.dart`, `ui/receipt_detail_screen.dart` |
| Budget de chaque mois (montant DT, seuil %) | `ui/budget_screen.dart` |
| Caméra : lecture du ticket (ML Kit), l'utilisateur n'a qu'à valider | `services/shopping_devices.dart`, `logic/ocr_rows.dart`, `logic/receipt_parser.dart` |
| Vibreur : seuil puis budget atteint | `services/shopping_devices.dart`, `ShoppingService.checkBudget` |
| Rapprochement liste ↔ ticket (cochés, oubliés, hors liste) | `logic/text_similarity.dart`, `logic/receipt_matcher.dart` |
| Hausses de prix (> +10 % vs moyenne 3 mois) | `logic/price_alerts.dart`, `ui/price_alerts_screen.dart` |
| Prévision de fin de mois | `logic/budget_forecast.dart` |
| Alimentation automatique (ruptures gestion 2, ingrédients gestion 3) | `ShoppingService.addRequests`, `integration/recipes_bridge.dart` |
| API Open Prices (comparaison + partage facultatif, cache) | `data/open_prices_api.dart` |
| Tri, recherche, statistiques | `logic/item_sorting.dart`, `viewmodels/receipts_view_model.dart`, `ui/budget_screen.dart` |
| Capteurs désactivables, jeton API sécurisé | `ui/shopping_settings_screen.dart`, `SecureTokenStore` |

Interfaces avec les autres gestions (`integration/gateways.dart`) : `UserGateway` (1), `ProductGateway` (2),
`StoreGateway` (4), avec des versions de démo dans `integration/demo_gateways.dart`.

## Gestion 3 — Recettes

| Exigence du cahier des charges | Où (`lib/features/recipes/`) |
|---|---|
| Tables `recipes`, `recipe_ingredients`, `recipe_steps`, `meal_plans` | `data/recipe_schema.dart`, `recipe_repository.dart` |
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

## Intégration entre gestions

Aucune gestion ne touche aux tables d'une autre : chacune passe par des interfaces (`integration/gateways.dart`
de chaque gestion). Pour brancher une gestion réelle, il suffit de passer son service à la place de la version
de démo dans `lib/main.dart`.

| Lien | État |
|---|---|
| Recettes (3) → Courses (5) : ingrédients manquants | **branché** (`RecipesShoppingBridge`) |
| Stock (2) → Courses (5) : ruptures prévues | `ShoppingService.addRequests` / `ProductGateway.upcomingShortages` |
| Courses (5) → Magasins (4) : prix payés ; Magasins (4) → Courses (5) : rayons, nombre d'articles | `StoreGateway`, `ShoppingService.pendingItemCount` |
| Recettes (3) → Activité (6) : calories consommées | `RecipeService.caloriesConsumedPerPerson(date)` |

Base de données : `lib/core/database/app_database.dart` ouvre la base unique (version 2) ; chaque gestion y
ajoute son `XxxSchema.create(db)`.
