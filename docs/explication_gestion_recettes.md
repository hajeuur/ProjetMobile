# Gestion 3 — Recettes : explication complète

Ce document explique **tout** ce que fait la gestion Recettes, fichier par fichier, avec le chemin exact
que suit chaque action (du bouton jusqu'à la base de données). Les liens pointent vers le code.

---

## 1. Vue d'ensemble

### Ce que fait la gestion
La gestion Recettes permet de :
1. **gérer des recettes** (créer, lire, modifier, supprimer) avec leurs ingrédients et leurs étapes ;
2. **importer des recettes** depuis l'API **TheMealDB** ;
3. **planifier les repas** de la semaine (petit-déjeuner, déjeuner, dîner) ;
4. **générer automatiquement le menu** de la semaine ;
5. **cuisiner sans toucher l'écran** (mode cuisine) grâce au capteur de **proximité**, au **micro** et au **haut-parleur** ;
6. **échanger avec les autres gestions** : lire le profil du foyer (gestion 1), lire et diminuer le stock
   (gestion 2), envoyer des articles à la liste de courses (gestion 5), fournir les calories mangées (gestion 6).

### Architecture MVVM (imposée par le cahier des charges)

```
UI (écrans)  ──lit/écoute──▶  ViewModel  ──appelle──▶  Service  ──▶  Repository ──▶ SQLite (sqflite)
                                                         │      ──▶  API TheMealDB (http) + cache
                                                         │      ──▶  Logic (algorithmes purs)
                                                         └────▶  Gateways (autres gestions)
```

| Couche | Dossier | Rôle |
|---|---|---|
| **Model** | `lib/features/recipes/models/` | Les classes de données (`Recipe`, `RecipeIngredient`, `RecipeStep`, `MealPlan`) et leur conversion vers/depuis la base (`toMap` / `fromMap`). |
| **Data** | `lib/features/recipes/data/` | Accès à la base (`RecipeRepository`), création des tables (`RecipeSchema`), API (`TheMealDbApi`), recettes de démo. |
| **Logic** | `lib/features/recipes/logic/` | Les **algorithmes** (métier avancé). Fonctions pures : elles ne touchent ni la base ni l'écran, donc faciles à tester. |
| **Service** | `lib/features/recipes/services/` | `RecipeService` : le **chef d'orchestre**. Il combine repository + API + logique + autres gestions. Aussi les capteurs (`cooking_devices.dart`) et les réglages. |
| **ViewModel** | `lib/features/recipes/viewmodels/` | Garde l'**état de l'écran** (liste chargée, tri choisi, étape en cours…) et prévient l'écran quand ça change (`notifyListeners()`). |
| **View** | `lib/features/recipes/ui/` | Les écrans Flutter. Ils n'ont **aucune** logique métier : ils affichent le ViewModel et lui transmettent les clics. |

**Gestion d'état : Provider.** Les objets sont « fournis » en haut de l'application
([recipes_module.dart](../lib/features/recipes/recipes_module.dart)) et récupérés dans les écrans avec :
- `context.watch<X>()` → l'écran se **redessine** quand X appelle `notifyListeners()` ;
- `context.read<X>()` → on récupère X **sans** s'abonner (pour appeler une méthode dans un `onPressed`).

### Règle commune du cahier des charges
> « Chaque gestion possède sa propre entité et en fait seule le CRUD. Les autres gestions peuvent lire ses
> données, jamais les créer ni les modifier directement : elles passent par le service. »

C'est pour ça qu'il y a les **gateways** ([gateways.dart](../lib/features/recipes/integration/gateways.dart)) :
la gestion Recettes ne fait **jamais** de requête SQL sur les tables `products` ou `stock_items`. Elle appelle
`StockGateway.consume(...)`, et c'est la gestion 2 qui modifie son stock.

---

## 2. Démarrage de l'application

Fichier : [main.dart](../lib/main.dart)

1. `WidgetsFlutterBinding.ensureInitialized()` : obligatoire avant d'utiliser des plugins (sqflite) avant `runApp`.
2. `initializeDateFormatting('fr_FR')` : charge les noms de jours/mois en français (« lundi 23 »).
3. `AppDatabase.open()` ([app_database.dart](../lib/core/database/app_database.dart)) :
   - ouvre le fichier `panier_malin.db` dans le dossier des bases du téléphone ;
   - `onConfigure` : `PRAGMA foreign_keys = ON` → active les clés étrangères (sinon SQLite les ignore et le `ON DELETE CASCADE` ne marche pas) ;
   - `onCreate` (seulement au **tout premier** lancement) : appelle `RecipeSchema.create(db)` qui crée les tables ;
   - `onUpgrade` : pour les futures versions du schéma (migrations).
4. Création des **passerelles de démo** (foyer, stock, courses simulés), en attendant les vraies gestions.
5. `RecipesModule.createService(...)` construit le `RecipeService`.
6. `seedDemoRecipesIfEmpty` : si l'utilisateur n'a **aucune** recette, insère les 10 recettes de démo
   ([demo_recipes.dart](../lib/features/recipes/data/demo_recipes.dart)).
7. `runApp(PanierMalinApp)` : `MultiProvider` + `MaterialApp` en français, thème clair **et** sombre
   (`themeMode: ThemeMode.system` suit le réglage du téléphone), écran d'accueil `RecipesHomeScreen`.

L'écran d'accueil ([recipes_home_screen.dart](../lib/features/recipes/ui/recipes_home_screen.dart)) a 3 onglets
(`NavigationBar`) : **Recettes**, **Planning**, **Stats**. `IndexedStack` garde les 3 écrans en mémoire ;
à chaque changement d'onglet, on recharge les données de l'onglet (`load()`), car un autre onglet a pu les modifier.

---

## 3. La base de données (sqflite, package pub.dev)

Fichier : [recipe_schema.dart](../lib/features/recipes/data/recipe_schema.dart)

### Les 4 tables du cahier des charges

**`recipes`**
| Colonne | Type | Sens |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | identifiant |
| user_id | INTEGER NOT NULL | propriétaire (séparation des données par utilisateur, §10 du cahier) |
| title | TEXT NOT NULL | titre |
| category | TEXT | Plat, Soupe, Breakfast… |
| prep_time_min | INTEGER | temps de préparation |
| base_servings | INTEGER | nombre de portions de la recette d'origine |
| calories_per_serving | REAL | calories par portion |
| photo | TEXT | URL ou chemin |
| source | TEXT | `personal` ou `themealdb` |
| external_id | TEXT | l'`idMeal` de TheMealDB (pour ne pas importer 2 fois) |
| created_at | TEXT | date ISO |

Index unique `(user_id, external_id)` : un même utilisateur ne peut pas avoir deux fois la même recette TheMealDB.

**`recipe_ingredients`** : id, **recipe_id → recipes (ON DELETE CASCADE)**, name, quantity (peut être NULL : « sel »),
unit, product_id (lien facultatif vers `products` de la gestion 2), position (ordre d'affichage).

**`recipe_steps`** : id, **recipe_id → recipes (CASCADE)**, number, text, duration_min (facultatif).

**`meal_plans`** : id, date (`'2026-11-23'`), meal (`breakfast`/`lunch`/`dinner`), **recipe_id → recipes (CASCADE)**,
servings, status (`planned`/`cooked`), cooked_at.

> `product_id` n'est **pas** déclaré comme clé étrangère SQL : la table `products` appartient à la gestion 2 et
> n'existe pas encore dans ce projet. On garde juste la colonne.

> `ON DELETE CASCADE` : quand on supprime une recette, SQLite supprime **automatiquement** ses ingrédients,
> ses étapes et ses repas planifiés.

### 2 tables techniques propres à la gestion
- **`recipe_api_cache`** (key, body, fetched_at) : les réponses de TheMealDB, pour fonctionner **hors ligne**
  (§10 : « les réponses des API sont mises en cache dans les tables de la gestion qui les appelle »).
- **`recipe_settings`** (key, value) : les réglages des capteurs (activés ou non).

### Les modèles ↔ la base
Dans [recipe.dart](../lib/features/recipes/models/recipe.dart) et [meal_plan.dart](../lib/features/recipes/models/meal_plan.dart) :
- `toMap()` transforme l'objet Dart en `Map<String, Object?>` (une ligne SQL) ;
- `fromMap()` fait l'inverse ;
- les `enum` (`RecipeSource`, `MealType`, `MealStatus`) ont un `dbValue` (ce qu'on stocke) et un `label` (ce qu'on affiche).
  `MealType` a aussi `calorieShare` : la part des calories du jour pour ce repas (**25 % / 40 % / 35 %**).

---

## 4. Le CRUD, étape par étape

Fichiers : [recipe_repository.dart](../lib/features/recipes/data/recipe_repository.dart) (SQL),
[recipe_service.dart](../lib/features/recipes/services/recipe_service.dart) (règles).

### 4.1 CREATE — créer une recette personnelle
1. Écran **Recettes** → bouton **Ajouter** → « Créer une recette personnelle »
   → ouvre [recipe_edit_screen.dart](../lib/features/recipes/ui/recipe_edit_screen.dart).
2. L'utilisateur remplit titre, catégorie, temps, portions, calories (bouton **Estimer** possible),
   photo, puis les lignes d'ingrédients (Qté / Unité / Nom) et d'étapes (texte / minutes).
3. Bouton **Enregistrer** → `_save()` :
   - `_form.currentState!.validate()` vérifie les champs (titre obligatoire, nombres valides) ;
   - construit un objet `Recipe` (les lignes vides sont ignorées, les étapes sont renumérotées 1, 2, 3…) ;
   - appelle `RecipeService.saveRecipe(recipe)`.
4. `saveRecipe` → `_validate()` (titre non vide, au moins 1 portion, au moins 1 ingrédient,
   sinon `ArgumentError` affiché en bas de l'écran) → comme `id == null`, appelle `repository.insertRecipe`.
5. `insertRecipe` fait tout dans **une transaction** (`db.transaction`) :
   1. `INSERT INTO recipes` → récupère le nouvel `id` ;
   2. `_writeChildren` : un **batch** qui insère tous les ingrédients (avec `position`) et toutes les étapes.
   - Transaction = **tout ou rien** : si une insertion échoue, rien n'est enregistré (pas de recette sans ingrédients).
6. L'écran se ferme avec `Navigator.pop(context, true)` ; la liste voit `true` et recharge (`load()`).

### 4.2 READ — lire les recettes
- **Liste** : `RecipeListViewModel.load()` → `service.recipes()` → `repository.listRecipes(userId)` :
  - `SELECT * FROM recipes WHERE user_id = ? ORDER BY title` ;
  - puis `_hydrate` charge **tous** les ingrédients et **toutes** les étapes en **2 requêtes seulement**
    (`WHERE recipe_id IN (?, ?, …)`) et les range par recette.
    → C'est plus rapide que 1 requête par recette (on évite le problème « N+1 requêtes »).
- **Fiche** : `RecipeDetailScreen` → `service.recipe(id)` → `repository.getRecipe(id)`.

### 4.3 UPDATE — modifier
1. Fiche recette → icône ✏️ → même écran d'édition, pré-rempli (`widget.recipe`).
2. `_save()` garde l'`id`, la source, l'`externalId` et la date de création d'origine.
3. `saveRecipe` voit `id != null` → `repository.updateRecipe` (transaction) :
   1. `UPDATE recipes SET … WHERE id = ?` ;
   2. `DELETE` des anciens ingrédients et étapes ;
   3. ré-insertion des nouveaux.
   - Supprimer puis réinsérer les enfants est plus simple et plus sûr que de comparer ligne par ligne.

### 4.4 DELETE — supprimer
Fiche → icône 🗑 → dialogue de confirmation (`confirm`) → `service.deleteRecipe(id)` →
`DELETE FROM recipes WHERE id = ?`. Le `CASCADE` supprime ingrédients, étapes et repas planifiés.

### 4.5 Importer depuis l'API (CRUD « Importer une recette depuis l'API »)
`RecipeService.importFromApi(externalId)` :
1. cherche si la recette est **déjà importée** (`findByExternalId`) → si oui, renvoie son id (pas de doublon) ;
2. sinon `api.fetchRecipe(id)` (voir §6) → `repository.insertRecipe`.

### 4.6 CRUD des repas planifiés (`meal_plans`)
Écran [week_plan_screen.dart](../lib/features/recipes/ui/week_plan_screen.dart) + [meal_plan_view_model.dart](../lib/features/recipes/viewmodels/meal_plan_view_model.dart).

| Action | Chemin |
|---|---|
| **Planifier** | Clic sur « + Ajouter » d'un créneau → liste des recettes compatibles (triées par anti-gaspi) → `vm.plan()` → si le créneau est occupé, l'ancien repas est supprimé → `service.planMeal` → `INSERT INTO meal_plans`. Aussi possible depuis la fiche (bouton **Planifier** → dialogue jour/repas/portions, [slot_picker.dart](../lib/features/recipes/ui/slot_picker.dart)). |
| **Lire la semaine** | `service.week(lundi)` → `mealPlansBetween(user, lundi, dimanche)` : `SELECT mp.* FROM meal_plans mp JOIN recipes r … WHERE r.user_id = ? AND mp.date BETWEEN ? AND ?` puis chargement des recettes complètes. Le `JOIN` sert à filtrer par utilisateur (meal_plans n'a pas de user_id, on passe par la recette). |
| **Déplacer** | Clic sur un repas → « Déplacer / portions » → `vm.move()` : si le créneau cible est occupé, les deux repas sont **échangés** → `UPDATE meal_plans`. |
| **Modifier les portions** | Même dialogue → `changeServings` → `UPDATE`. |
| **Supprimer** | « Retirer du planning » → `DELETE FROM meal_plans WHERE id = ?`. |
| **Marquer cuisiné** | voir §5.5. |

Les dates : `weekStartOf(d)` donne le lundi de la semaine ; `addDays(d, n)` ajoute des jours **calendaires**
(`DateTime(année, mois, jour + n)`) pour éviter les décalages au changement d'heure.

---

## 5. Le métier avancé (algorithmes)

### 5.1 Contrôle allergies et régimes du foyer
Fichier : [dietary_checker.dart](../lib/features/recipes/logic/dietary_checker.dart)

Le profil commun vient de la gestion 1 (`HouseholdProfile`) : **union** des allergies de tous les membres et
**intersection** des régimes (c'est la gestion 1 qui calcule ça ; nous on le lit).

`DietaryChecker.check(recette, profil)` :
1. **normalise** tous les noms d'ingrédients + le titre (minuscules, sans accents, sans ponctuation) ;
2. pour chaque **allergie** : prend la liste de mots-clés (ex. `arachide` → `arachide, cacahuete, peanut`)
   et cherche si un ingrédient contient ce **mot entier** (`containsWord`, pluriel accepté) ;
3. pour chaque **régime** : liste d'ingrédients interdits (ex. `halal` → porc, jambon, vin, gélatine… ;
   `vegetarien` → toutes les viandes et poissons) ;
4. renvoie un `DietaryVerdict` avec la liste des raisons. `allowed` = aucune raison.

Mots-clés **français ET anglais**, car TheMealDB est en anglais.

**Effet dans l'app :** la liste masque par défaut les recettes non compatibles (filtre « Compatibles foyer
(1 masquées) ») ; le menu automatique ne les propose jamais ; la fiche affiche un encadré rouge avec la raison.
Exemple : « Poulet sauce cacahuète » → *Allergie « arachide » : cacahuete*.

### 5.2 Score anti-gaspi (métier avancé n°1)
Fichier : [stock_analysis.dart](../lib/features/recipes/logic/stock_analysis.dart)

**Formule :**
```
score = 100 × (en_stock + bientôt_périmés) / (total + bientôt_périmés)
```
- `total` = nombre d'ingrédients de la recette ;
- `en_stock` = ingrédients trouvés dans le stock (non périmés, quantité > 0) ;
- `bientôt_périmés` = parmi eux, ceux dont le produit périme dans **3 jours ou moins**.

Ajouter `bientôt_périmés` en haut **et** en bas revient à donner un **poids double** aux produits urgents
(cahier : « avec un poids plus fort pour ceux qui périment dans les 3 jours »).

**Exemple réel (Chakchouka, score affiché 80 avec ⏱2) :**
8 ingrédients (tomate, poivron, oignon, ail, œuf, huile, sel, cumin). Stock de démo : tomate (périme dans 2 j),
poivron (1 j), oignon, ail, œuf, huile → **6 en stock**, dont **2 bientôt périmés**. Sel et cumin absents.
→ 100 × (6 + 2) / (8 + 2) = **80**.

**Comment on sait qu'un ingrédient « est » un produit du stock** (`matchingStock`) :
- si les deux ont un `product_id` → on compare les id ;
- sinon `sameIngredient(nom1, nom2)` ([text_matching.dart](../lib/features/recipes/logic/text_matching.dart)) :
  normalisation, singulier (« tomates » → « tomate », « tomatoes » → « tomato »), traduction français → anglais
  (« poulet » → « chicken »), et inclusion de mots (« chicken breast » contient « chicken »).

Couleur de la pastille : vert ≥ 70, orange ≥ 40, gris sinon. Tri par défaut de la liste : anti-gaspi décroissant.

### 5.3 Menu hebdomadaire automatique (métier avancé n°2)
Fichier : [menu_generator.dart](../lib/features/recipes/logic/menu_generator.dart), appelé par
`RecipeService.proposeWeekMenu`, écran [menu_generation_screen.dart](../lib/features/recipes/ui/menu_generation_screen.dart).

**Entrées :** toutes les recettes, profil du foyer, stock, liste des créneaux à remplir, objectif calorique.

**Algorithme (glouton, créneau par créneau) :**
1. **Filtre strict** : on ne garde que les recettes **compatibles** (allergies / régimes, §5.1).
2. On trie les créneaux **dans l'ordre chronologique** (lundi petit-déj, lundi déj, …).
3. Pour chaque créneau :
   1. **Cible calorique** du repas = objectif journalier × part du repas
      (ex. 2200 kcal × 40 % = **880 kcal** pour un déjeuner) ;
   2. candidates = recettes **pas encore utilisées cette semaine** (**variété** : jamais 2 fois la même) ;
   3. petit-déjeuner → on préfère les catégories « Breakfast / dessert » ; déjeuner et dîner → l'inverse
      (si possible) ;
   4. on calcule pour chaque candidate :
      ```
      score = 0,55 × anti_gaspi + 0,45 × adéquation_calories × 100
      adéquation_calories = 1 − |calories − cible| / cible   (minimum 0 ; 0,5 si calories inconnues)
      ```
   5. on prend la **meilleure** ; on la marque « utilisée » ;
   6. les produits bientôt périmés qu'elle utilise sont ajoutés à `claimed` (« réservés ») : pour les créneaux
      suivants, ils ne comptent plus comme urgents → on ne choisit pas 3 recettes qui « sauvent » la même tomate.
4. Si plus aucune recette disponible → le créneau va dans `unfilled` (affiché : « créneau laissé vide »).

**Pourquoi chronologique ?** Comme l'anti-gaspi pèse dans le score, les recettes qui utilisent les produits
urgents sont choisies **en premier**, donc **en début de semaine** : on les mange avant qu'ils périment.

**Options de l'écran :**
- « Garder les repas déjà planifiés » : ne remplit que les créneaux vides (et les recettes déjà planifiées comptent
  pour la variété). Sinon, les repas « prévus » sont remplacés (les « cuisinés » sont toujours gardés).
- Les créneaux **passés** (avant aujourd'hui) ne sont jamais remplis.
- Nombre de portions (par défaut = nombre de membres du foyer).
- **Appliquer** → `applyMenu` → un `INSERT INTO meal_plans` par repas.

Avec les 10 recettes de démo (dont 1 interdite), on obtient **9 repas** maximum : il faut importer des recettes
pour remplir les 21 créneaux.

### 5.4 Ajustement des portions (métier avancé n°3)
Fichier : [portion_scaler.dart](../lib/features/recipes/logic/portion_scaler.dart)

```
facteur = portions_voulues / portions_de_base
nouvelle_quantité = quantité × facteur   (arrondie à 2 décimales)
```
Ex. Chakchouka pour 3 → 4 œufs. Pour 6 → facteur 2 → 8 œufs.
- Les ingrédients sans quantité (« sel ») restent tels quels.
- Les **calories par portion ne changent pas** ; le **total** = calories par portion × portions.

Dans la fiche, le sélecteur − / + recalcule tout en direct (et l'état stock/manquant aussi).

### 5.5 Marquer un repas comme cuisiné → sortie de stock
`RecipeService.markCooked(mealPlanId)` :
1. charge le repas ; s'il est **déjà** « cuisiné » → ne fait rien (renvoie 0) : on ne retire jamais 2 fois du stock ;
2. `consumeIngredients(recette, portions)` :
   - ajuste les quantités aux portions (§5.4) ;
   - pour chaque ingrédient chiffré, trouve les lignes de stock correspondantes, **triées par date de péremption**
     (on puise d'abord dans ce qui périme le plus tôt : principe **FEFO**, *first expired, first out*) ;
   - convertit les unités (`toBase` : kg → g, l/cl/cuillère → ml, pièce) pour comparer ;
   - appelle `stock.consume(...)` (= le **service de la gestion 2**) pour chaque sortie ;
3. met le repas à `status = cooked`, `cooked_at = maintenant`.

Accessible : Planning → clic sur un repas → « Marquer comme cuisiné », ou bouton **Terminé** à la dernière étape
du mode cuisine (si on cuisine sans planning, un repas est créé pour aujourd'hui puis marqué cuisiné, pour que les
calories soient comptées pour la gestion 6).

### 5.6 Ingrédients manquants → liste de courses (métier avancé n°4)
`missingIngredients` dans [stock_analysis.dart](../lib/features/recipes/logic/stock_analysis.dart) :
- ingrédient **absent** du stock → manque toute la quantité ;
- présent mais **sans quantité** (sel) → considéré OK ;
- présent avec unités comparables → si on a moins que nécessaire, on achète **la différence** ;
- unités **incomparables** (« 2 gousses » contre « 100 g ») → considéré disponible (pour ne pas acheter en double).

Puis `sendMissingToShopping` transforme chaque manque en `ShoppingRequest(origin: 'recette')` et appelle
`ShoppingGateway.addItems` (= service de la gestion 5). « En un clic » : bouton **Manquants → liste de courses**
de la fiche.

**Version semaine** (icône 🛒 du Planning, `sendWeekMissingToShopping`) : parcourt les repas prévus dans l'ordre et
**simule** la consommation du stock au fur et à mesure (si 2 recettes utilisent 4 tomates et qu'on en a 6, la
2ᵉ en manque 2), puis **fusionne** les demandes identiques (même nom + même unité → quantités additionnées).

### 5.7 Pour la gestion 6 : calories consommées
`caloriesConsumedPerPerson(date)` = somme des `calories_per_serving` des repas **cuisinés** ce jour-là
(chaque membre mange une portion). La gestion 6 l'utilise pour le **bilan énergétique**.

### 5.8 Estimation des calories
Fichier : [calorie_estimator.dart](../lib/features/recipes/logic/calorie_estimator.dart)
TheMealDB ne donne pas de calories. On a une table de kcal pour 100 g (riz 360, œuf 155, huile 884…) et un poids
moyen par pièce (œuf 55 g, oignon 110 g…). Pour chaque ingrédient reconnu : grammes × kcal / 100, puis total ÷
portions. L'estimation est dite « fiable » si au moins la moitié des ingrédients est reconnue.
Ex. 100 g de riz + 2 œufs = 360 + 2 × 55 × 1,55 ≈ **530 kcal**. Bouton **Estimer** dans l'écran d'édition.

---

## 6. L'API TheMealDB

Fichier : [themealdb_api.dart](../lib/features/recipes/data/themealdb_api.dart), écran
[recipe_import_screen.dart](../lib/features/recipes/ui/recipe_import_screen.dart). Package `http` (pub.dev).

URL de base : `https://www.themealdb.com/api/json/v1/1` (la clé de test « 1 » est publique et gratuite).

| Fonction | Endpoint | Renvoie |
|---|---|---|
| `searchByName("chicken")` | `search.php?s=chicken` | recettes complètes |
| `filterByCategory("Seafood")` | `filter.php?c=Seafood` | id, nom, vignette |
| `filterByIngredient("chicken breast")` | `filter.php?i=chicken_breast` | id, nom, vignette |
| `categories()` | `list.php?c=list` | liste des catégories |
| `fetchRecipe("52772")` | `lookup.php?i=52772` | 1 recette complète |

### Cache hors ligne (`_get`)
1. cherche l'URL dans `recipe_api_cache` ;
2. si trouvée et **moins de 7 jours** → on l'utilise **sans réseau** ;
3. sinon requête HTTP (délai max 10 s) ; si OK → on enregistre la réponse dans le cache ;
4. si **pas de réseau** → on renvoie le cache même s'il est vieux ; s'il n'y en a pas → `RecipeApiException`
   avec un message en français, affiché à l'écran **sans bloquer** l'application (exigence non fonctionnelle §11).

### Conversion JSON → `Recipe` (`mealToRecipe`)
- TheMealDB a 20 champs `strIngredient1…20` et `strMeasure1…20` → on garde les non vides ;
- chaque mesure texte est découpée par `parseMeasure` ([measure_parser.dart](../lib/features/recipes/logic/measure_parser.dart)) :
  `"1/2 cup"` → 0,5 cup ; `"200g"` → 200 g ; `"1 1/2 tsp"` → 1,5 tsp ; `"Pinch"` → pas de quantité ;
- `strInstructions` est découpé en étapes par `splitInstructions` (une ligne = une étape, lignes « STEP 1 »
  supprimées ; si tout est sur une ligne, découpe par phrases) ; les durées citées (« bake for 1 hour ») sont
  détectées → minuteur proposé dans le mode cuisine ;
- portions = **4** (supposé) ; calories = **estimées** (§5.8) ; temps = somme des durées + 10 min ;
- `source = themealdb`, `externalId = idMeal`.

### L'écran d'import
3 modes (Nom / Catégorie / Ingrédient), grille de résultats. Appui sur une carte → importe et ouvre la fiche ;
bouton **Importer** → importe seulement. Les recettes déjà importées affichent « ✓ Importée ».

---

## 7. Les capteurs (mode cuisine)

Écran : [cooking_mode_screen.dart](../lib/features/recipes/ui/cooking_mode_screen.dart) —
ViewModel : [cooking_view_model.dart](../lib/features/recipes/viewmodels/cooking_view_model.dart) —
Accès au matériel : [cooking_devices.dart](../lib/features/recipes/services/cooking_devices.dart).

Le matériel est caché derrière des **interfaces** (`ProximitySource`, `SpeechInput`, `Speaker`, `ScreenKeeper`) :
- en vrai : implémentations qui utilisent les packages ;
- dans les tests : fausses implémentations → on teste la logique **sans téléphone**.

Au démarrage du mode cuisine (`start()`) : chargement des réglages, **écran maintenu allumé** (`wakelock_plus`),
activation de la proximité si disponible, lecture à voix haute de l'étape 1.

### 7.1 Capteur de proximité — « passer la main » (package `proximity_sensor`)
`ProximitySensor.events` envoie un entier : > 0 = un objet est **proche**. On le transforme en `true/false`.

Fichier : [hand_wave_detector.dart](../lib/features/recipes/logic/hand_wave_detector.dart) — une petite
**machine à états** :
1. proche → loin = **un passage** (si la main est restée **moins de 1,5 s** ; sinon ce n'est pas un geste :
   par ex. téléphone posé à l'envers) ;
2. après un 1er passage, on lance un minuteur de **800 ms** ;
3. si un **2ᵉ passage** arrive avant la fin → geste **PRÉCÉDENT** ;
4. si le minuteur expire sans 2ᵉ passage → geste **SUIVANT** ;
5. après un geste, on ignore tout pendant **400 ms** (anti-rebond).

### 7.2 Micro — commandes vocales (package `speech_to_text`)
1. Appui sur 🎤 → la 1ʳᵉ fois, un dialogue explique **pourquoi** on veut le micro (exigence §11 sur les permissions),
   puis Android demande la permission ;
2. `initialize()` choisit une langue **française** si disponible ;
3. écoute max 8 s, s'arrête après 3 s de silence ; seul le **résultat final** est utilisé ;
4. le texte passe dans `parseVoiceCommand` ([voice_commands.dart](../lib/features/recipes/logic/voice_commands.dart)) :
   - normalisation (sans accents, minuscules) ;
   - « minuteur / timer » + durée → `StartTimerCommand` ; avec « arrête / stop » → `StopTimerCommand` ;
   - « précédent / retour » → précédent ; « répète / relis » → répéter ; « suivant / ensuite » → suivant ;
     « ingrédients » → lit les ingrédients ;
   - la durée comprend les chiffres **et les mots** : « vingt cinq minutes », « une heure et demie »,
     « 1 heure 30 minutes », « 30 secondes ».
5. Option « Écoute continue » : relance le micro après chaque commande.

### 7.3 Haut-parleur — lecture à voix haute (package `flutter_tts`)
Langue `fr-FR`, vitesse 0,45. À chaque changement d'étape : « Étape 2. Ajouter les poivrons… ».
Fin de minuteur (`ring`) : 3 × son d'alerte système + vibration, puis « Le minuteur est terminé ».

### 7.4 Minuteurs
Plusieurs minuteurs en même temps. Chacun garde son **heure de fin** (`endsAt`) ; un `Timer.periodic` d'1 s
rafraîchit l'affichage et sonne quand le temps restant atteint 0. Lancés par la voix ou par le bouton
« Minuteur X min » quand l'étape a une durée.

### 7.5 Réglages (« chaque capteur peut être désactivé »)
Bouton ⚙ Capteurs : geste de la main, commandes vocales, écoute continue, lecture à voix haute, texte grand format.
Enregistrés dans `recipe_settings` ([cooking_settings.dart](../lib/features/recipes/services/cooking_settings.dart)).

### 7.6 Permissions Android
Dans `android/app/src/main/AndroidManifest.xml` : `INTERNET` (TheMealDB), `RECORD_AUDIO` (micro),
`WAKE_LOCK` (écran allumé), et les `<queries>` pour que l'app « voie » les services de reconnaissance vocale et
de synthèse vocale (obligatoire depuis Android 11).

---

## 8. Fonctions de base (tri, recherche, statistiques)

Fichier : [recipe_list_view_model.dart](../lib/features/recipes/viewmodels/recipe_list_view_model.dart)

- **Tri** (icône ⇅) : score anti-gaspi (défaut, décroissant), temps de préparation, calories (croissants,
  valeurs inconnues à la fin), titre.
- **Recherche** (barre) : par **titre** ou par **ingrédient**, sans tenir compte des accents ; « poulet » trouve
  aussi une recette TheMealDB avec « chicken ».
- **Filtres** : « Compatibles foyer » et puces de catégories.
- **Statistiques** ([recipe_stats_view_model.dart](../lib/features/recipes/viewmodels/recipe_stats_view_model.dart)) :
  - recettes **les plus cuisinées** : `SELECT r.title, COUNT(*) … WHERE status = 'cooked' GROUP BY r.id ORDER BY n DESC LIMIT 5` ;
  - **calories moyennes par repas** pour chaque jour de la semaine (graphique en barres `fl_chart`) ;
  - nombre de recettes, personnelles / importées, repas cuisinés dans la semaine.

---

## 9. Lien avec les autres gestions (intégration)

Fichier : [gateways.dart](../lib/features/recipes/integration/gateways.dart)

| Interface | Gestion | Méthodes | Simulation actuelle |
|---|---|---|---|
| `HouseholdGateway` | 1 Utilisateurs | `currentUserId`, `commonProfile()` | foyer de 3, allergie arachide, régime halal, 2200 kcal/j |
| `StockGateway` | 2 Produits | `currentStock()`, `consume(...)` | 11 produits (tomates qui périment dans 2 j…) |
| `ShoppingGateway` | 5 Courses | `addItems(...)` | liste en mémoire + message dans la console |

Fichier de simulation : [demo_gateways.dart](../lib/features/recipes/integration/demo_gateways.dart).
**À l'intégration**, on remplace ces 3 objets dans `main.dart` par les vrais services des coéquipiers : le reste
du code ne change pas. C'est l'intérêt des interfaces.

Dans l'autre sens, la gestion 6 appelle `RecipeService.caloriesConsumedPerPerson(date)`.

---

## 10. Les tests

Lancer : `flutter test` (20 tests).
- [logic_test.dart](../test/recipes/logic_test.dart) : mesures, traduction, découpage des étapes, conversion
  TheMealDB, calories, commandes vocales, geste de la main (avec `fake_async` pour simuler le temps),
  menu automatique.
- [service_test.dart](../test/recipes/service_test.dart) : CRUD sur une vraie base SQLite **en mémoire**
  (`sqflite_common_ffi`), marquer cuisiné (le stock diminue, une seule fois), courses, menu, import avec une
  **fausse API** (`MockClient`) et vérification du cache.
- [cooking_view_model_test.dart](../test/recipes/cooking_view_model_test.dart) : mode cuisine avec faux capteurs.
- [widget_test.dart](../test/widget_test.dart) : l'application démarre et masque la recette aux cacahuètes.

---

## 11. Limites connues (à savoir dire à l'examen)

- Les gestions 1, 2 et 5 sont **simulées** tant que l'intégration n'est pas faite.
- TheMealDB est **en anglais** ; les portions (4) et les calories sont **estimées**.
- La correspondance ingrédient ↔ stock se fait par le **nom** (dictionnaire de traductions limité) quand il
  n'y a pas de `product_id`.
- Unités incomparables (gousse vs gramme) : l'ingrédient est considéré disponible.
- Le menu est un algorithme **glouton** : bon et rapide, mais pas forcément l'optimum absolu.
- La reconnaissance vocale Android a besoin des services Google ; sur émulateur, la proximité se simule dans
  *Extended controls → Virtual sensors*.

---

## 12. Questions probables à l'examen (avec réponses courtes)

1. **Pourquoi MVVM ?** Séparer l'affichage (View), l'état (ViewModel) et les données/règles (Model/Service) ;
   on peut tester la logique sans écran et changer un écran sans toucher aux règles.
2. **Rôle de Provider ?** Rendre les objets (service, view models) accessibles partout ; `watch` redessine
   l'écran quand le ViewModel appelle `notifyListeners()`.
3. **Pourquoi une transaction pour enregistrer une recette ?** Recette + ingrédients + étapes = plusieurs
   `INSERT` ; la transaction garantit tout ou rien.
4. **À quoi sert `ON DELETE CASCADE` ?** Supprimer automatiquement ingrédients, étapes et repas d'une recette
   supprimée. Il faut `PRAGMA foreign_keys = ON`.
5. **Comment marche le score anti-gaspi ?** Formule §5.2, poids double pour ce qui périme sous 3 jours.
6. **Comment le menu respecte-t-il les 4 contraintes ?** Allergies/régimes = filtre strict ; variété = recettes
   « utilisées » exclues ; calories = adéquation à la cible du repas ; anti-gaspi = dans le score, créneaux
   chronologiques, produits « réservés ».
7. **Comment éviter de retirer 2 fois du stock ?** `markCooked` ne fait rien si le statut est déjà « cuisiné ».
8. **Pourquoi ne pas modifier directement la table du stock ?** Règle commune : seule la gestion 2 modifie ses
   tables ; on passe par `StockGateway`.
9. **Comment l'app fonctionne-t-elle sans internet ?** Données en SQLite local ; réponses TheMealDB en cache
   (7 jours, ou plus si hors ligne) ; erreur affichée sans bloquer.
10. **Comment distinguer 1 et 2 passages de main ?** Fenêtre de 800 ms après le 1er passage (§7.1).
11. **Comment le micro comprend « minuteur vingt cinq minutes » ?** Normalisation + mots-clés + lecture des
    nombres en lettres (§7.2).
12. **Comment as-tu testé sans téléphone ?** Interfaces pour le matériel + fausses implémentations, SQLite en
    mémoire, `MockClient` pour l'API, `fake_async` pour le temps.
