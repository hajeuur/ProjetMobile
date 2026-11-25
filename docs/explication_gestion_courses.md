# Gestion 5 — Courses et Budget : explication complète

Ce document explique ce que fait la gestion Courses et Budget, où se trouve chaque fonction dans le code,
et le chemin que suit chaque action (du bouton jusqu'à la base de données). Il sert aussi de support pour la
soutenance.

---

## 1. Vue d'ensemble

### Ce que fait la gestion
La gestion suit l'achat de bout en bout :
1. **avant le magasin** : des listes de courses, remplies à la main ou automatiquement par les autres gestions
   (ruptures de stock prévues, ingrédients manquants des recettes) ;
2. **après le magasin** : la photo du ticket de caisse est lue (caméra + reconnaissance de texte), les articles
   achetés se cochent tout seuls dans la liste et l'app signale ceux qui ont été oubliés ;
3. **tout le mois** : le budget est suivi, le téléphone **vibre** au seuil d'alerte puis au dépassement, et une
   prévision de fin de mois prévient *avant* que le budget soit dépassé ;
4. **les prix** : chaque hausse de plus de 10 % est détectée, et le prix payé peut être comparé à ceux de la
   communauté sur **Open Prices**.

### Architecture MVVM

```
UI (écrans)  ──écoute──▶  ViewModel  ──appelle──▶  ShoppingService ──▶ ShoppingRepository ──▶ SQLite
                                                        │          ──▶ OpenPricesApi (http) + cache
                                                        │          ──▶ logic/ (algorithmes purs)
                                                        │          ──▶ capteurs (caméra/OCR, vibreur)
                                                        └────────▶ gateways (gestions 1, 2, 4)
```

| Couche | Dossier | Rôle |
|---|---|---|
| Model | [models/](../lib/features/shopping/models/) | `ShoppingList`, `ShoppingItem`, `Receipt`, `ReceiptLine`, `Budget` + conversion base (`toMap`/`fromMap`). |
| Data | [data/](../lib/features/shopping/data/) | Tables (`ShoppingSchema`), accès SQL (`ShoppingRepository`), API Open Prices, données de démo. |
| Logic | [logic/](../lib/features/shopping/logic/) | Algorithmes du métier avancé, sans base ni écran : faciles à tester. |
| Service | [services/](../lib/features/shopping/services/) | `ShoppingService`, le chef d'orchestre ; `shopping_devices.dart` pour la caméra, l'OCR, le vibreur et le stockage sécurisé. |
| ViewModel | [viewmodels/](../lib/features/shopping/viewmodels/) | État des écrans (liste chargée, tri, brouillon de ticket…), `notifyListeners()`. |
| View | [ui/](../lib/features/shopping/ui/) | Les écrans. Aucune logique métier. |

Gestion d'état : **Provider** (comme la gestion 3). Le branchement est dans
[shopping_module.dart](../lib/features/shopping/shopping_module.dart).

### Règle commune
La gestion 5 ne fait **jamais** de requête SQL sur les tables des autres gestions. Elle passe par des
interfaces ([integration/gateways.dart](../lib/features/shopping/integration/gateways.dart)) :

| Interface | Fournie par | Utilisée pour |
|---|---|---|
| `UserGateway` | Gestion 1 | utilisateur connecté (`user_id` des tables racines) |
| `ProductGateway` | Gestion 2 | rapprocher une ligne de ticket d'un produit, code-barres, ruptures prévues, entrée en stock après achat |
| `StoreGateway` | Gestion 4 | liste des magasins et ordre de leurs rayons, envoi des « prix payés » |

En attendant les vraies gestions, [demo_gateways.dart](../lib/features/shopping/integration/demo_gateways.dart)
fournit des versions en mémoire.

Dans l'autre sens, les autres gestions appellent `ShoppingService` :

| Gestion | Méthode | Pour |
|---|---|---|
| 2 — Stock | `addRequests(...)` / `importShortages()` | ruptures prévues → liste en cours (origine « rupture prévue ») |
| 3 — Recettes | `RecipesShoppingBridge` → `addRequests(...)` | ingrédients manquants → liste en cours (origine « recette ») — **déjà branché** dans `main.dart` |
| 4 — Magasins | `pendingItemCount()` | notification de géofencing « N articles sur votre liste » |
| 4 — Magasins | `activeListItems()` | calcul du magasin optimal pour la liste en cours |

---

## 2. Base de données

Fichier : [shopping_schema.dart](../lib/features/shopping/data/shopping_schema.dart). La base passe en
**version 2** ([app_database.dart](../lib/core/database/app_database.dart)) : un téléphone qui avait la version 1
(gestion 3 seule) reçoit les nouvelles tables par `onUpgrade`.

| Table | Colonnes principales |
|---|---|
| `shopping_lists` | id, user_id, name, created_at, store_id (facultatif), status (`active`/`done`) |
| `shopping_items` | id, list_id → shopping_lists, label, product_id, quantity, unit, checked, origin (`manual`/`shortage`/`recipe`), aisle (rayon), position (ordre d'ajout) |
| `receipts` | id, user_id, store_id, store_name, date, total, photo, list_id (liste rapprochée) |
| `receipt_lines` | id, receipt_id → receipts, label (libellé lu), product_id, barcode, quantity, price (prix de la ligne), category |
| `budgets` | id, user_id, month (`2026-11`), amount (DT), alert_threshold (%) — unique par mois |
| `shopping_api_cache` | réponses Open Prices (hors ligne) |
| `shopping_settings` | capteurs activés, alertes déjà envoyées ce mois-ci |

`store_id` et `product_id` ne sont pas déclarés en clés étrangères : les tables `stores` et `products`
appartiennent aux gestions 4 et 2 et n'existent pas encore dans ce dépôt (même choix que la gestion 3).
La suppression d'une liste supprime ses articles (`ON DELETE CASCADE`) ; celle d'un ticket, ses lignes.

---

## 3. CRUD (cahier des charges)

| Exigence | Écran | Méthode du service |
|---|---|---|
| Créer, renommer, archiver, supprimer une liste | Listes de courses, menu ⋮ | `createList`, `renameList`, `archiveList`, `deleteList` |
| Ajouter, cocher, retirer des articles | Détail d'une liste (barre du bas, case, bouton corbeille ou glisser vers la gauche ; « Annuler » remet l'article) | `addItem`, `setChecked`, `removeItem`, `restoreItem` |
| Créer un ticket par photo ou à la main | Scan du ticket → Validation | `draftFromText` puis `saveDraft` |
| Corriger une ligne mal lue | Validation, ou Détail du ticket → « Corriger » | `saveLine` (le total suit s'il était la somme des lignes) |
| Supprimer un ticket | Historique (glisser) ou Détail | `deleteReceipt` |
| Définir et modifier le budget du mois | Budget → crayon | `setBudget` |

**Anti-doublon** : ajouter « tomate » alors que « Tomates » (non coché) est déjà dans la liste additionne les
quantités au lieu de créer une deuxième ligne (`_findSame` / `_merge` dans le service). Une rupture prévue déjà
présente n'est jamais ajoutée deux fois.

---

## 4. Capteurs

### Caméra — lecture du ticket de caisse
Fichier : [shopping_devices.dart](../lib/features/shopping/services/shopping_devices.dart), classe `MlKitReceiptReader`.

1. `image_picker` ouvre l'appareil photo (ou la galerie) ; la photo est copiée dans le dossier de l'app
   (`receipt_photos/`) et son chemin est gardé dans `receipts.photo`.
2. `google_mlkit_text_recognition` reconnaît le texte **sur le téléphone** (pas de réseau).
3. ML Kit renvoie souvent le libellé (à gauche) et le prix (à droite) dans des blocs séparés.
   [ocr_rows.dart](../lib/features/shopping/logic/ocr_rows.dart) les regroupe par ligne en comparant la position
   verticale de leur centre, puis les lit de gauche à droite.
4. [receipt_parser.dart](../lib/features/shopping/logic/receipt_parser.dart) transforme le texte en lignes :
   - prix en fin de ligne, 2 ou 3 décimales (`1,350` = 1 dinar 350 millimes) ;
   - quantité : `2 x 1,350` sur la ligne suivante, `YAOURT 4 x 0,600` dans la ligne, pesée `1,250 kg x 2,000` ;
   - libellé sur une ligne et prix seul sur la suivante (lecture découpée) ;
   - `REMISE` → ligne négative ; code-barres en tête de ligne → colonne `barcode` ;
   - `NET A PAYER` > `TOTAL TTC` > `TOTAL` ; `SOUS TOTAL`, `TVA`, `ESPECES`, `RENDU`… sont ignorés ;
   - la date (`23/11/2026`) et l'en-tête (nom du magasin) sont repérés.
5. Le service reconnaît le magasin dans l'en-tête, rapproche chaque ligne d'un produit de la gestion 2 et devine
   sa catégorie ([categories.dart](../lib/features/shopping/logic/categories.dart)).
6. **L'utilisateur n'a qu'à valider** : l'écran de validation montre la somme des lignes et le total lu ; un
   écart signale une ligne probablement mal lue.

### Caméra en direct — scan du ticket sans photo
Bouton « Scanner en direct » (écran « Scanner un ticket », proposé seulement si « Lecture automatique des
tickets » est activée dans les Réglages). La caméra filme, le texte est lu en continu :

| Étape | Où | Ce qui se passe |
|---|---|---|
| Flux caméra | `DeviceLiveReceiptCamera` (packages `camera` + `google_mlkit_text_recognition`) | images NV21 (Android) / BGRA (iOS), **~3 par seconde** maximum (`FrameGate` : une image n'est lue que si la précédente est terminée et date d'au moins 333 ms) ; luminosité moyenne calculée sur la luminance |
| Rangées | `groupRows` (`ocr_rows.dart`) | fragments ML Kit regroupés en rangées avec leur rectangle (pour la surbrillance) et leur confiance |
| Lecture d'une image | `LiveReceiptParser` (`logic/live_receipt_parser.dart`), classe dédiée et testée seule | lignes (libellé, quantité, prix), total (`TOTAL`, `TTC`, `À PAYER`, `NET À PAYER` ; sous-total/TVA exclus), en-tête, date ; formats tunisiens : virgule ou point, 3 décimales, `DT`/`TND` avant ou après, milliers `1 250,000` ; confusions `O→0`, `S→5`, `I→1`, `B→8` corrigées mais pénalisées |
| Suivi entre images | `LiveScanTracker` (`logic/live_scan_tracker.dart`) | une ligne est confirmée après 2 images (puis s'affiche) ; vote sur le libellé, le prix, la quantité ; bruit vu une seule fois oublié ; ordre du ticket conservé quand on fait défiler ; somme comparée au total |
| Stabilité | `LiveScanTracker.isStable` | mêmes lignes et même total sur 3 images d'affilée → « Terminer le scan » mis en avant + **retour haptique** (une fois) |
| Écran | `LiveReceiptScanScreen` + `LiveScanViewModel` | aperçu plein écran, cadre guide, lignes en surbrillance animées (vert sûr / orange douteuse / bleu total), « Lignes lues » qui se remplit, « Total validé » (vert) ou « Écart de X DT » (orange), lampe |
| Validation | `ReceiptValidationScreen` | lignes modifiables (toucher) ou supprimables (corbeille), douteuses en orange, magasin et date, photo du ticket prise à la fin du scan et conservée ; enregistrement dans `receipts` / `receipt_lines` |

**Score de confiance** (0 à 1, douteux sous 0,6) : format du montant (3 décimales = attendu, chiffre deviné =
forte pénalité), qualité du libellé (assez de lettres, peu de caractères parasites), cohérence quantité × prix,
confiance de ML Kit (Android) ; puis, entre images, part des images d'accord sur le prix.

**Jamais d'impasse** : permission refusée (« Réessayer »), refusée définitivement (« Ouvrir les réglages »),
caméra indisponible ; image trop sombre (« Trop sombre : Rapproche-toi / ajoute de la lumière », + lampe) ;
texte trop petit (« rapproche-toi ») ; aucune ligne après 10 s → « Ticket illisible ». Chaque cas propose
« Saisir à la main » (et « Choisir une photo » si la caméra ne démarre pas).

**Caméra libérée** dans `dispose()` (flux arrêté, contrôleur et lecteur ML Kit fermés), et aussi quand l'app
passe en arrière-plan (rouverte au retour). L'écran est bloqué en portrait pendant le scan. Permission Android
`CAMERA` déclarée ; iOS : `NSCameraUsageDescription` déjà présent.

### Vibreur et notification — alerte de seuil du budget
Fichiers : [budget_alert_center.dart](../lib/features/shopping/viewmodels/budget_alert_center.dart),
[budget_alert_banner.dart](../lib/features/shopping/ui/budget_alert_banner.dart), `checkBudget` dans
[shopping_service.dart](../lib/features/shopping/services/shopping_service.dart).

- **Jauge circulaire animée** (écran Budget) : se remplit à l'ouverture ; vert sous le seuil, orange au seuil,
  rouge au budget atteint, avec un **dégradé doux** juste avant chaque palier. Elle se met à jour (animée) à
  chaque ticket enregistré, corrigé ou supprimé (`receiptsChanged`).
- **À chaque enregistrement / correction d'un ticket**, la dépense du mois est recalculée. **Une seule alerte
  par franchissement** : le niveau déjà signalé est mémorisé par mois (`budget_level_AAAA-MM`) ; ouvrir
  l'écran ne déclenche rien ; si la dépense redescend (ticket supprimé), un nouveau franchissement alerte
  de nouveau.
  - seuil franchi → vibration **courte** (`[0, 180, 120, 180]`), bannière **orange** ;
  - budget atteint ou dépassé → vibration **longue** (3 × 700 ms), bannière **rouge**.
- **Bannière** au-dessus de tous les écrans (`MaterialApp.builder`) : mini-jauge qui s'anime de la dépense
  d'avant le ticket vers la nouvelle, titre, « 86 % du budget utilisé », phrase intelligente, et **animation
  « téléphone qui vibre »** pendant la durée du motif — visible même sur émulateur (« simulée : pas de
  vibreur »). Se referme seule après 12 s ou avec ×.
- **Phrase intelligente** (`budgetSentence`) : « À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à
  3,9 DT/jour. » ; ou « Budget dépassé de 5,6 DT… », « Il te reste 35 DT, soit 17,5 DT/jour… ».
- **App en arrière-plan** : notification locale (`flutter_local_notifications`, canal « Alertes de budget »),
  puis bannière au retour dans l'app. L'autorisation (Android 13+, iOS) est demandée quand on définit un budget.
- **Interrupteur Vibreur** respecté (alerte visuelle seulement s'il est coupé) ; `Vibration.hasVibrator()`
  vérifié (appareil sans vibreur : alerte visuelle) ; motifs personnalisés si `hasCustomVibrationsSupport`,
  sinon vibration simple de même durée. **« Tester la vibration »** (Réglages) : vibration courte + bannière
  de démonstration.
- Versions : `flutter_local_notifications` **22.3.3** (la 23 impose compileSdk 37, le projet est en 36) ;
  le plugin exige le *core library desugaring* (`android/app/build.gradle.kts`).

### Accéléromètre — secouer pour annuler
Dans le détail d'une liste, secouer le téléphone annule la dernière action sur les articles (cocher/décocher,
suppression, ajout). Un message « Dernière action annulée : lait décoché » propose **Rétablir** ; un léger
retour haptique confirme l'annulation ; si rien n'est à annuler : « Rien à annuler ».

| Élément | Fichier |
|---|---|
| Détection : norme de l'accélération en g (1 g au repos), seuil 2,7 g, anti-rebond 800 ms | [shake_detector.dart](../lib/features/shopping/logic/shake_detector.dart) |
| Pile d'historique (10 actions max) : type, article, état avant / après ; pile de rétablissement | [undo_history.dart](../lib/features/shopping/logic/undo_history.dart) |
| Annuler / rétablir (réinsertion à la même position, fusion de quantités défaite…) | `ListDetailViewModel.undo` / `redo` |
| Capteur (`sensors_plus`, échantillonnage ~15 Hz) derrière l'interface `ShakeSource` | [shopping_devices.dart](../lib/features/shopping/services/shopping_devices.dart) |
| Écoute **seulement quand l'écran est visible** : abonnement coupé quand un autre écran ou un dialogue passe par-dessus (`RouteAware`), quand l'app passe en arrière-plan, et libéré dans `dispose()` | [list_detail_screen.dart](../lib/features/shopping/ui/list_detail_screen.dart) |
| Interrupteur « Secouer pour annuler » (activé par défaut) | Réglages — Courses |
| Sans secouer (émulateur) : menu ⋮ → « Annuler la dernière action » | détail d'une liste |

Sur l'émulateur, on peut aussi simuler une vraie secousse : `adb emu sensor set acceleration 25:20:9.8`
(puis `0:9.81:0` pour revenir au repos).

### Microphone — ajout d'articles par la voix
Bouton micro dans la barre d'ajout d'une liste. L'app écoute en français, affiche le texte reconnu **en direct**
avec des ondes sonores qui suivent le niveau du micro, puis découpe la phrase en articles.

| Élément | Fichier |
|---|---|
| Découpage : « ajoute lait, pain et 6 œufs » → Lait · Pain · 6 Œufs. Séparateurs (virgule, « et », « puis »…), mots d'introduction ignorés (« ajoute », « mets », « je veux », « il me faut »…), quantités en chiffres ou en lettres (« deux », « vingt-quatre », « une douzaine », « un demi »), unités (kilo, litre, paquet, bouteille…), « de / du / des » retirés | [voice_parser.dart](../lib/features/shopping/logic/voice_parser.dart) (`VoiceItemParser`, testé seul) |
| Écoute : permission micro (`permission_handler`), reconnaissance `speech_to_text` en fr_FR, texte partiel, niveau sonore | `DeviceVoiceInput` dans [shopping_devices.dart](../lib/features/shopping/services/shopping_devices.dart) |
| Feuille d'écoute et erreurs | [voice_input_sheet.dart](../lib/features/shopping/ui/voice_input_sheet.dart) |
| Confirmation : chaque ligne modifiable (nom, quantité) ou supprimable, ligne ajoutable, « Ajouter à la liste » | [voice_confirm_screen.dart](../lib/features/shopping/ui/voice_confirm_screen.dart) |
| Déjà dans la liste : « Augmenter la quantité : 2 L → 3 L » (activé par défaut) au lieu d'un doublon ; unités incompatibles (1 kg + 3) → ajouté à part, avec explication | `mergedQuantity`, `ListDetailViewModel.addVoiceItems` |
| Origine « voix » (badge micro) dans `shopping_items.origin` ; chaque ajout reste annulable par secousse | `ItemOrigin.voice` |

Erreurs, toutes avec repli « Saisir à la main » (le champ d'ajout prend le focus) :
permission refusée (message + « Réessayer »), refusée définitivement (message + **« Ouvrir les réglages »**),
aucun son détecté, reconnaissance indisponible hors ligne (pas de réseau ni de pack de langue), reconnaissance
absente du téléphone. Interrupteur « Ajout vocal » dans Réglages — Courses.

Permissions : Android `RECORD_AUDIO` (déjà déclarée, partagée avec la gestion 3) ; iOS
`NSMicrophoneUsageDescription` et `NSSpeechRecognitionUsageDescription` dans `Info.plist`. Pour iOS, il faudra
ajouter `PERMISSION_MICROPHONE=1` et `PERMISSION_SPEECH_RECOGNIZER=1` dans le Podfile (généré au premier build iOS),
comme l'exige `permission_handler`.

`permission_handler` est fixé en version 12 : la version 13 impose de compiler avec Android 37, alors que le
projet (plugin Gradle) est en 36.

### Désactivation (ergonomie)
Écran Réglages (icône ⚙ dans « Listes ») : vibreur, lecture automatique des tickets, secouer pour annuler, ajout vocal, Open Prices.
Sans lecture automatique, la photo est jointe et les lignes sont saisies à la main.

---

## 5. Métier avancé

### 5.1 Rapprochement liste ↔ ticket
Fichiers : [receipt_reconciler.dart](../lib/features/shopping/logic/receipt_reconciler.dart) (classe dédiée
`ReceiptReconciler`, testée seule), [text_similarity.dart](../lib/features/shopping/logic/text_similarity.dart)
(normalisation), écran [reconciliation_screen.dart](../lib/features/shopping/ui/reconciliation_screen.dart).

Problème : la liste dit « Lait », le ticket dit « LAIT DEMI ECR 1L ».

1. **Normalisation** : minuscules, sans accents ; mots vides (de, la, x…) et contenances (1L, 500G) retirés,
   singulier ; abréviations de ticket développées (YAOU → yaourt, ECR → écrémé, HLE → huile…).
2. **Ressemblance de deux mots** : 1 s'ils sont égaux ; 0,9 si l'un est le début de l'autre (abréviation) ;
   sinon le meilleur de **Jaro-Winkler** (≥ 0,9) et de **Levenshtein** (1 − distance/longueur, ≥ 0,8), pour
   tolérer une lettre mal lue (« FRMAGE » / « fromage ») sans confondre « lait » et « laid ».
3. **Score article/ligne** = 0,75 × part des mots de l'article retrouvés dans la ligne + 0,15 × l'inverse
   + 0,10 si le premier mot correspond. Même produit de la gestion 2 → 1.
4. **Décision** (constantes réglables `sureMatchScore` = 0,75 et `askMatchScore` = 0,5) :
   - score ≥ 0,75 → **coché tout seul**, et la ligne du ticket reçoit le `product_id` de l'article ;
   - 0,5 à 0,75 → **« oui / non ? »** sur l'écran résumé (« JUS POMME 1L » est-ce votre « Jus d'orange » ?) ;
   - < 0,5 → pas de rapprochement.
5. **Affectation gloutonne** : couples triés du plus sûr au moins sûr ; chaque article et chaque ligne ne sert
   qu'une fois (« Lait » va à « LAIT DELICE », « CHOCOLAT AU LAIT » reste hors liste).
6. **Apprentissage** : chaque réponse oui/non est mémorisée (`CorrectionMemory`, clé « ligne | article »
   normalisée, 300 dernières, réglage `match_corrections`). Oui → la paire devient sûre ; non → plus jamais
   proposée.
7. **Liste ciblée** : celle choisie sur l'écran de validation ; par défaut la **liste en cours** (la plus récente
   liste active avec des articles à prendre).

**Écran résumé** (après « Valider le ticket », ou « Rapprocher » depuis le détail d'un ticket) :
« 6 achetés, 2 oubliés : lait, pain » ; les achetés se cochent un à un avec une animation ; les cas incertains
avec Oui / Non ; chaque oublié avec « Garder pour la prochaine liste » (copié dans « Prochaines courses »,
origine « Oublié », sans doublon, annulable) et « Tout garder » ; les **achats hors liste** ; puis budget et
hausses de prix. Réglage « Reporter les oubliés » : les oubliés partent tout seuls dans « Prochaines courses ».

**8 cas de référence** ([reconciler_test.dart](../test/shopping/reconciler_test.dart)) :

| # | Liste | Ticket | Résultat attendu |
|---|---|---|---|
| 1 | Lait | LAIT DEMI ECR 1L | sûr → coché |
| 2 | Pâtes | PATES | sûr (score 1 : majuscules, accents) |
| 3 | Yaourt nature | YAOU NAT VITALAIT 4X125G | sûr (abréviations) |
| 4 | Fromage | FRMAGE BLANC | sûr (lettre manquante : Levenshtein / Jaro-Winkler) |
| 5 | Lait | CHOCOLAT AU LAIT + LAIT DELICE 1L | Lait ↔ LAIT DELICE ; chocolat hors liste |
| 6 | Jus d'orange | JUS POMME 1L | incertain (≈ 0,55) → oui / non |
| 7 | Pain (+ Œufs déjà cochés) | SAVON DE MARSEILLE | pain oublié, savon hors liste, œufs ni l'un ni l'autre |
| 8 | Jus d'orange, Mouchoirs | JUS POMME 1L, KLEENEX BOITE X100 | après « non » / « oui » : jus oublié sans question, mouchoirs sûr |

### 5.2 Détection des hausses de prix
Fichier : [price_alerts.dart](../lib/features/shopping/logic/price_alerts.dart).

Pour chaque produit (clé `p:<id produit>` s'il est rapproché, sinon `l:<libellé normalisé>`) :
dernier prix unitaire payé comparé à la **moyenne des prix payés dans les 90 jours précédant cet achat**
(les lignes du même ticket sont exclues). Au-delà de **+10 %**, une alerte affiche le pourcentage.
Écran « Prix » ; un appui ouvre le graphique d'évolution avec la moyenne en pointillé.

### 5.3 Prévision de fin de mois
Fichier : [budget_forecast.dart](../lib/features/shopping/logic/budget_forecast.dart).

```
prévision = dépensé ÷ jours écoulés × jours du mois
```
Si la prévision dépasse le budget alors qu'il n'est pas encore atteint, l'app **avertit avant** : jour estimé
du dépassement et montant possible par jour pour rester dans le budget
(`reste ÷ jours restants`). Exemple : 150 DT dépensés le 10 novembre pour 300 DT → prévision 450 DT,
budget atteint vers le 20, limite de 7,500 DT par jour.

### 5.4 Alimentation automatique
`addRequests` reçoit les articles des autres gestions et les place dans la **liste en cours** (créée si besoin),
avec leur origine affichée par une pastille : « Rupture prévue » (gestion 2) ou « Recette » (gestion 3).
Le bouton 📦 de l'écran Listes importe les ruptures prévues sous 2 jours.

---

## 6. API — Open Food Facts et Open Prices (scan de code-barres)

Points d'accès **vérifiés** dans la documentation et le code source officiels (dépôt
`openfoodfacts/open-prices`, schéma `https://prices.openfoodfacts.org/api/schema`) et sur l'API réelle :

| Usage | Requête | Réponse |
|---|---|---|
| Fiche produit | `GET https://world.openfoodfacts.org/api/v2/product/{code}?fields=product_name,brands,quantity,image_front_small_url,nutriscore_grade,allergens_tags,categories_tags` | `{code, product, status: 1}` ; produit inconnu : `status: 0` |
| Prix d'un produit | `GET https://prices.openfoodfacts.org/api/v1/prices?product_code={code}&order_by=-date&size=100` | `{items, page, pages, size, total}` |
| Alternative | `GET …/api/v1/prices?product__categories_tags__contains={catégorie}&currency=TND&order_by=price&size=50` | idem |
| Connexion | `POST …/api/v1/auth` (formulaire `username`, `password`) | `access_token` (Bearer) |
| Preuve | `POST …/api/v1/proofs/upload` (multipart : `file`, `type` PRICE_TAG/RECEIPT, `currency`, `date`) | `id` |
| Partage | `POST …/api/v1/prices` (JSON : `product_code`, `price`, `currency`, `date`, `proof_id` **obligatoire**, localisation OSM facultative mais par paire) | 201 |

Règles respectées : User-Agent identifiant l'app (`PanierMalin/1.0 (…)`, demandé par Open Food Facts, sans
donnée personnelle), 15 lectures/min max (le cache évite les appels répétés), délai d'attente de 10 s, réponse
429/503 → « limite de requêtes, réessayez dans une minute ».

**Architecture** : `CachedJsonClient` (délai, User-Agent, cache `shopping_api_cache`, repli hors ligne) →
`ProductScanRepository` (OFF + Open Prices + mode démo) → `ProductScanService` (historique, verdict,
alternative, liste, surveillance, contribution) → `ProductSheetViewModel` → écrans.

**Parcours** : onglet Prix → « Scanner un produit » → scanner `mobile_scanner` (cadre animé, lampe, saisie
manuelle avec contrôle de la clé EAN, raccourcis démo) → fiche produit :
- nom, marque, photo, Nutri-Score, allergènes (Open Food Facts) ;
- **mon dernier prix payé** (tickets, même code-barres) et **courbe** de mon prix (ligne pointillée : moyenne
  communauté) ; **prix moyen de la communauté** en DT et nombre de prix comparés ;
- **verdict** : « Tu paies 9 % de plus que la moyenne » (rouge), « Bon prix » (vert, jusqu'à +5 %) ;
- **alternative moins chère** de la même catégorie (prix communautaire), sinon le même produit payé moins cher
  dans un autre de mes magasins, avec « Ajouter à ma liste » ;
- boutons « Ajouter à ma liste » (liste en cours), « Surveiller ce produit » (liste dans l'onglet Prix),
  « Contribuer mon prix » (si « Partager mes prix » est activé : connexion, photo de l'étiquette ou du ticket,
  remerciement et compteur de prix partagés).

**Erreurs** : produit inconnu (carte dédiée, l'historique reste affiché) ; aucun prix en DT (« n prix dans
d'autres devises ») ; pas de réseau → dernier résultat en cache avec la mention **« Données hors ligne · date »**,
code mémorisé et **resynchronisé** (nouvel essai toutes les 20 s tant que la fiche est ouverte, message
« Réseau revenu : données resynchronisées ») ; rien en cache → « Pas de réseau » + « Réessayer ».

**Réglages** : « Comparer avec Open Prices » désactivé → plus aucun appel à Open Prices (seule la fiche
produit et mon historique) ; « Partager mes prix » → bouton « Contribuer mon prix » ; « Mode démo ».

**Mode démo** (soutenance sans réseau) : Nutella `3017620422003` (payé plus cher → rouge + alternative),
Coca-Cola `5449000000996` (bon prix), Spaghetti Barilla `8076800195057` (prix seulement en euros). Fiches au
format exact des API, **prix fictifs** signalés à l'écran (« Mode démo · prix fictifs »).

Partage depuis le détail d'un ticket : la photo du ticket sert de preuve (type RECEIPT) ; sans photo, message
clair. Correction : l'ancien envoi sans `proof_id` aurait été refusé par le serveur.

## 6 ter. Panier type par magasin

Fichier : [habitual_basket.dart](../lib/features/shopping/logic/habitual_basket.dart) (logique testée seule),
écran [habitual_basket_screen.dart](../lib/features/shopping/ui/habitual_basket_screen.dart).

1. **Panier habituel** : produits achetés au moins **3 fois** (tickets différents) sur les **90 derniers jours** ;
   quantité moyenne par achat (deux lignes du même ticket = un achat).
2. **Coût dans chaque magasin** : quantité moyenne × **dernier prix payé dans ce magasin** ; prix jamais payé
   là → moyenne des autres magasins, affichée « estimation ».
3. **Classement** du moins cher au plus cher : « Ton panier habituel coûte 12,8 DT chez Carrefour La Marsa,
   14 DT chez Monoprix Lafayette », le moins cher en vert avec « Tu économises 1,3 DT par rapport à Monoprix
   Lafayette ». Un magasin dont moins de 40 % des prix sont connus n'est **pas classé** (son total serait
   surtout fait d'estimations) : il est cité à part (ex. Marché central, qui ne vend que des légumes).
4. **Affichage** : carte résumé en tête des listes (accueil Courses), carte avec barres horizontales animées
   dans l'écran Prix ; toucher une barre déplie le détail (quantité × prix, « estimation ») ; écran détaillé
   avec la composition du panier. Mise à jour à chaque ticket.
5. **Données insuffisantes** : « Pas encore de panier habituel » ou « Un seul magasin à comparer » (écran Prix),
   rien sur l'accueil. Interrupteur « Panier type par magasin » dans les Réglages.

Données de démo : un panier de 6 produits (lait, café, harissa, poulet, tomates, yaourt) comparé entre
Carrefour et Monoprix ; Aziza et le Marché central non classés.

## 6 quater. Meilleur moment pour acheter

Fichier : [best_time.dart](../lib/features/shopping/logic/best_time.dart) (logique testée seule), écran
[best_time_screen.dart](../lib/features/shopping/ui/best_time_screen.dart).

- Analyse par produit à partir de **6 achats** (sur un an) selon trois critères : **moment du mois** (début
  1–10, milieu 11–20, fin 21–31), **jour de la semaine**, **magasin**. Pour chaque critère, le groupe le moins
  cher (au moins 2 achats) est comparé à tous les autres achats.
- **Conclusion seulement si l'écart dépasse 5 %** ; sinon « le prix varie peu ». Moins de 6 achats : produit
  « en observation » (« 4 achats sur 6 nécessaires »). Aucune conclusion inventée.
- Moment du mois et magasin significatifs tous les deux, et au moins 2 achats dans la combinaison : phrase
  réunie, « Pour « Tomates », c'est moins cher en début de mois au Marché central (-13 %) ».
- Fiabilité : « basé sur 8 achats » (faible sous 8, moyenne de 8 à 11, élevée à partir de 12) ; mini-graphiques
  (prix moyen par groupe, le meilleur en vert).
- **« Me rappeler »** : notification locale programmée au prochain moment favorable (1er, 11 ou 21 du mois,
  ou prochain jour de la semaine) à 9 h, via `zonedSchedule` en mode `inexactAllowWhileIdle` (pas de permission
  d'alarme exacte). Android : `RECEIVE_BOOT_COMPLETED` et les deux récepteurs du plugin dans le manifeste.
- Interrupteur « Meilleur moment pour acheter ». Démo : 4 tickets de juin–juillet (tomates au Marché central
  en début de mois), sans effet sur les alertes de prix, le panier type et le budget.

## 6 bis. Fonctions en plus du cahier des charges

| Fonction | Où | Ce qu'elle fait |
|---|---|---|
| **Jauge budget animée** | `BudgetGauge` dans [budget_screen.dart](../lib/features/shopping/ui/budget_screen.dart) | Cercle qui se remplit à l'ouverture : vert, puis orange au seuil, rouge au budget. Un trait marque le seuil, un arc pâle la prévision de fin de mois. La vibration au passage du seuil vient de `checkBudget`. |
| **Conseil du jour** | [advice.dart](../lib/features/shopping/logic/advice.dart) | Phrase calculée par règles : montant possible par jour, achats non essentiels à éviter, premier poste de dépense, plus forte hausse de prix. |
| **Comparateur de magasins** | [store_comparison.dart](../lib/features/shopping/logic/store_comparison.dart), [store_comparison_screen.dart](../lib/features/shopping/ui/store_comparison_screen.dart) | D'après les prix réellement payés (90 jours) : coût de la liste en cours dans chaque magasin (prix inconnu = moyenne des autres, signalé « estimé ») et, produit par produit, le magasin le moins cher. Accès : détail d'une liste, écran Prix, bouton « Où le payer moins cher ? » d'une alerte. La gestion 4 garde le « magasin optimal » complet (relevés + coût du trajet). |
| **Alertes intelligentes** | [price_alerts_screen.dart](../lib/features/shopping/ui/price_alerts_screen.dart) | Chaque hausse propose « Où le payer moins cher ? », « Ajouter à ma liste » (sans doublon) et « Évolution » (courbe). Indicateur de fiabilité : faible (1 achat), moyenne (2-3), bonne (4 et plus). |
| **Badges et défis** | [badges.dart](../lib/features/shopping/logic/badges.dart) | Budget tenu 3 mois de suite, Zéro oubli, Archiviste (10 tickets), Liste bouclée, Chasseur de prix (3 comparaisons Open Prices), avec barre de progression. |

Le message de budget est cohérent avec la jauge : « Seuil d'alerte de 80 % franchi : 86 % du budget utilisé (…) »,
suivi de « Dépassement prévu : à ce rythme, 144,660 DT en fin de mois (budget atteint vers le 30). Limitez-vous à
3,890 DT par jour. » quand la prévision dépasse le budget.

Graphiques : mois abrégés tous distincts (juin, juil., août…), graduation ronde (`niceAxis` : 0, 50, 100, 150),
légende « Dépensé / Dépensé (budget dépassé) / Budget ». Camembert : au plus 4 catégories, les petites
regroupées dans « Autres » ; toucher une part ou une ligne de légende affiche le détail.

Tickets : regroupés par mois avec le total (« Novembre 2026 : 120,550 DT »), icône selon le type de magasin.

## 7. Fonctions de base

| Exigence | Où |
|---|---|
| Tri des tickets par date ou par montant | Historique : puces « Date » / « Montant » (re-toucher inverse l'ordre) — `ReceiptsViewModel` |
| Tri des articles par rayon ou par ordre d'ajout | Détail d'une liste — [item_sorting.dart](../lib/features/shopping/logic/item_sorting.dart). Par rayon, l'ordre est celui du magasin choisi (gestion 4) ; les articles cochés vont en bas |
| Recherche d'un ticket par magasin | Historique, champ de recherche |
| Recherche d'un article par libellé | Détail d'une liste, loupe |
| Dépenses par mois et par catégorie | Budget : histogramme 6 mois (budget en gris, mois dépassés en rouge) et camembert par catégorie |
| Respect du budget, panier moyen | Budget : « Budget respecté x / n mois », « Panier moyen (3 mois) » |

---

## 8. Écrans

| Écran du cahier des charges | Fichier |
|---|---|
| Listes de courses | [shopping_lists_screen.dart](../lib/features/shopping/ui/shopping_lists_screen.dart) |
| Détail d'une liste | [list_detail_screen.dart](../lib/features/shopping/ui/list_detail_screen.dart) |
| Scan du ticket + Validation des lignes | [receipt_scan_screen.dart](../lib/features/shopping/ui/receipt_scan_screen.dart) |
| Historique des tickets | [receipts_history_screen.dart](../lib/features/shopping/ui/receipts_history_screen.dart), détail : [receipt_detail_screen.dart](../lib/features/shopping/ui/receipt_detail_screen.dart) |
| Budget du mois | [budget_screen.dart](../lib/features/shopping/ui/budget_screen.dart) |
| Alertes de prix | [price_alerts_screen.dart](../lib/features/shopping/ui/price_alerts_screen.dart) |
| Réglages | [shopping_settings_screen.dart](../lib/features/shopping/ui/shopping_settings_screen.dart) |

L'accueil de l'application ([app_home_screen.dart](../lib/core/ui/app_home_screen.dart)) donne accès aux
gestions présentes (Courses, Recettes) ; les autres apparaissent grisées en attendant l'intégration.

---

## 9. Parcours complet : « Photo d'un vrai ticket : les articles se cochent tout seuls »

1. Détail de la liste → **Scanner le ticket** → `ReceiptScanScreen(listId)`.
2. **Prendre le ticket en photo** → `ReceiptScanViewModel.capture` → `MlKitReceiptReader.capture` (caméra) puis
   `readText` (ML Kit + `rowsFromFragments`).
3. `ShoppingService.draftFromText` → `parseReceiptText`, magasin reconnu, produits rapprochés → brouillon.
4. Écran **Validation** : corriger une ligne si besoin, puis **Valider le ticket** → `saveDraft` :
   - insertion de `receipts` + `receipt_lines` (une transaction) ;
   - `reconcile` → `matchReceipt` → les articles achetés sont cochés ;
   - prix payés envoyés à la gestion 4, entrées en stock à la gestion 2 ;
   - `checkBudget` → vibration si le seuil ou le budget vient d'être franchi ;
   - hausses de prix sur les produits du ticket.
5. Le **bilan** s'affiche : cochés, oubliés, hors liste, budget, hausses de prix.

---

## 10. Données de démo et tests

Au premier lancement, [demo_shopping.dart](../lib/features/shopping/data/demo_shopping.dart) crée une liste en cours
(avec articles « rupture prévue » et « recette »), quatre mois de tickets dans quatre magasins (avec des hausses
sur l'huile d'olive, le café et les tomates) et des budgets (un mois dépassé ; le mois en cours a passé le seuil
de 80 % et la prévision dépasse le budget). Ainsi chaque écran a quelque chose à montrer pendant la démo.

```
flutter test test/shopping
```

| Fichier | Ce qui est vérifié |
|---|---|
| [logic_test.dart](../test/shopping/logic_test.dart) | lecture de tickets (quantités, remise, total, date), regroupement OCR, similarité, rapprochement, catégories, hausses de prix, prévision du budget, tri par rayon |
| [service_test.dart](../test/shopping/service_test.dart) | CRUD avec SQLite en mémoire, anti-doublon, ruptures et pont Recettes, ticket complet (rapprochement, gestions 2 et 4, vibration une seule fois par niveau, réglage vibreur), correction de ligne, statistiques, Open Prices simulé (cache hors ligne) |
| [shopping_ui_test.dart](../test/shopping/shopping_ui_test.dart) | parcours à l'écran : liste → scan (faux lecteur) → validation → bilan → articles cochés ; écrans Budget et Prix |
| [shopping_flows_test.dart](../test/shopping/shopping_flows_test.dart) | jauge, conseil, légende, camembert, badges, tickets par mois, actions des alertes, comparateur ; et **tous les boutons, menus et dialogues** sur un petit écran (360 de large) : créer/renommer/archiver/remettre en cours/supprimer une liste, ajout et fusion d'articles, modification, magasin et tri par rayon, recherche, ruptures prévues ; ticket saisi à la main, total, correction, validation, bilan, détail, rapprochement, ajout/suppression de ligne, Open Prices sans code-barres, suppression ; budget, mois précédent, alertes de prix, réglages. Le test échoue à la moindre erreur Flutter (écran rouge, débordement). |

---

## 11. Bugs trouvés et corrigés

| Symptôme | Cause | Correction |
|---|---|---|
| Écran rouge `'_dependents.isEmpty': is not true` après « Nouvelle liste » (la liste était quand même créée) | Le champ texte du dialogue était détruit (`TextEditingController.dispose()`) juste après sa fermeture, alors que l'animation de fermeture l'affichait encore | Chaque dialogue est un `StatefulWidget` qui libère son contrôleur dans son propre `dispose()` ([widgets.dart](../lib/features/shopping/ui/widgets.dart) `promptText`, connexion Open Prices des réglages) |
| Plantage en ouvrant un écran depuis Listes ou Tickets | Deux boutons flottants avec le même tag Hero dans l'`IndexedStack` | `heroTag` distinct pour chaque bouton |
| Bandes jaunes et noires sur petit écran | Barre de tri des tickets, listes déroulantes (magasin, liste, rayon, catégorie), lignes de la carte Budget trop larges | `Wrap`, `isExpanded: true`, textes coupés avec « … », valeurs souples |
| « Scanner le ticket » cachait le titre de la liste | Bouton placé en haut à droite | Bouton en bas, au-dessus de la barre d'ajout |
| Le nom proposé d'une nouvelle liste se complétait au lieu d'être remplacé | Texte proposé non sélectionné | Il est sélectionné à l'ouverture du dialogue |
| Bannière « seuil de 80 % atteint » à côté de « 86 % utilisé » : on croyait à une incohérence ; le dépassement prévu n'apparaissait pas en même temps | Deux messages calculés séparément | Un seul message, qui donne le % utilisé, le seuil franchi et le dépassement prévu |
| Mois « juin » et « juillet » tous deux affichés « jui » ; axe « 161 » collé à « 150 » | Abréviation = 3 premières lettres ; maximum de l'axe non arrondi | Abréviations usuelles distinctes ; graduation ronde |
| « Ajouter à ma liste » disait « ajouté » pour un produit déjà présent | L'article était fusionné mais compté comme ajouté | Renvoie « Déjà dans la liste en cours » |

## 12. Limites connues

- La lecture dépend de la qualité de la photo (ticket froissé, encre pâle). L'écran de validation et la
  comparaison somme/total servent de filet de sécurité.
- Le seuil de rapprochement (0,6) est un compromis : un libellé très abrégé peut ne pas être reconnu ; il reste
  « hors liste » et l'article se coche à la main.
- iOS : ML Kit demande iOS 15.5 minimum (`platform :ios, '15.5'` dans le Podfile, généré au premier build iOS).
- Le partage Open Prices nécessite l'identifiant OpenStreetMap du magasin, disponible une fois la gestion 4
  intégrée (le magasin de démo « Carrefour La Marsa » a un identifiant fictif : le partage sera refusé par le
  serveur).
