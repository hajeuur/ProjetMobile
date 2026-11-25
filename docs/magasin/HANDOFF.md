# HANDOFF — Gestion 4 « Magasins » (Amine)

> Update this file at the end of every work session / agent task. A fresh agent must be able to continue from here alone.

**Repo:** https://github.com/hajeuur/ProjetMobile — **Branch:** `Magasin/Amine`
**Last updated:** 2026-11-25 — **State:** Merged `origin/Recette` into `Magasin/Amine`; P2 database layer (schema, models, DAOs, `AppDatabase` hook, `sqflite_common_ffi` tests) implemented, awaiting `flutter analyze` & `flutter test` (Flutter SDK not installed on this machine).

## Context in 5 lines
PanierMalin: Flutter app, local SQLite, MVVM, 6 gestions, one owner each. I own Magasins:
reference stores, notify passively when near one (geofence), compass arrow to chosen store,
compute the cheapest basket store (prices + travel cost), sort shopping list by aisle.
Full requirements: `SPEC_MAGASIN.md`. Rules: `/AGENTS.md`.

## Status checklist
- [x] P0  Repo audit + environment check
- [x] P1  Architecture plan approved
- [ ] P2  DB layer (models, DAOs, migrations, tests)
- [ ] P3  Repositories + `StoreService` + ports/stubs
- [ ] P4  CRUD view models + screens (map, list, detail, aisles editor, price records)
- [ ] P5  Overpass import + cache
- [ ] P6  Geofencing notifications
- [ ] P7  Compass (magnetometer)
- [ ] P8  Optimal store algorithm + basket comparator screen
- [ ] P9  Missing price estimation + aisle sort
- [ ] P10 Sort / search / statistics (fl_chart)
- [ ] P11 Tests + hardening
- [ ] P12 Final review + integration with teammates

## Decisions taken
- **DB:** sqflite (not drift). `StoreSchema` omits `REFERENCES products(id)` on `store_prices.product_id` (matching `RecipeSchema`) so standalone mode works with `PRAGMA foreign_keys = ON`.
- **State management:** Provider (`origin/Recette` uses `provider: ^6.1.5+1` + `MultiProvider` + `*_module.dart`).
- **Naming:** Keep `AGENTS.md` folder names (`screens/`, `view_models/`, `ports/`, `data/dao/`, `data/repositories/`) inside `lib/features/magasin/`, while exposing `StoreSchema` and `MagasinModule` to match `origin/Recette`.
- **Map:** `flutter_map` + `latlong2` (OSM tiles, no API key).
- **Currency:** DT (TND, 3 decimals), stored as `REAL`. *(confirm with Gestion 5 owner)*

## Open questions (ask the team / teacher)
1. ~~Provider vs Riverpod — who decides, when?~~ *(Resolved on `origin/Recette`: `provider: ^6.1.5+1` is already used in `pubspec.yaml` and `lib/main.dart` via `MultiProvider`.)*
2. ~~Who writes the shared `DatabaseHelper` (weeks 1-2)?~~ *(Resolved on `origin/Recette`: `AppDatabase` in `lib/core/database/app_database.dart` already exists with `PRAGMA foreign_keys = ON`, `*_schema.dart` pattern, and `// TODO(intégration)` hooks in `_onCreate` / `_onUpgrade`.)*
3. ~~**Branching / base code:**~~ *(Resolved: `origin/Recette` merged into `Magasin/Amine`.)*
4. **Shared `main.dart` & navigation:** Currently `lib/main.dart` on `origin/Recette` boots directly into `RecipesHomeScreen()`. Who owns the shared app shell / bottom navigation or drawer to reach all 6 gestions?
5. **Conventions alignment:** `origin/Recette` uses `ui/` + `viewmodels/` + `integration/gateways.dart` + `*_schema.dart`, whereas `AGENTS.md` specifies `screens/` + `view_models/` + `ports/` + `data/dao/`. Keep `AGENTS.md` naming inside `lib/features/magasin/` (with a `StoreSchema` / `MagasinModule` integration point), or align with `Recette`?
6. Extra columns I want on `stores`: `user_id` (required by spec), `osm_id`, `source`, `created_at`. OK?
7. Interface I need from Gestion 2: `getProductById(id)`, `getProductsByIds(ids)`.
8. Interface I need from Gestion 5: `getActiveListItems(userId)` -> items with `product_id`, `quantity`, `label`; and count of unchecked items.
9. Date of the final defense (planning not dated).

## Interfaces I expose to other gestions (via StoreService)
_(fill as implemented)_
- `getStores(userId)`, `getStoreById(id)`, `getFavoriteStore(userId)`
- `getLatestPrice(storeId, productId)`, `getAisleOrder(storeId)`
- `rankStoresForBasket(userId, items)` -> ranked list with total, travel cost, estimated flags
- `sortItemsByAisle(storeId, items)`

## Interfaces I consume (ports, stubbed until delivered)
- `ProductReader` (Gestion 2) — stub: [ ]  real: [ ]
- `ShoppingListReader` (Gestion 5) — stub: [ ]  real: [ ]

## Session log
| Date | Model used | What was done | Files | Next |
|------|-----------|---------------|-------|------|
| 2026-11-25 | — | Created AGENTS.md, HANDOFF, SPEC, PROMPTS | docs/magasin/* | Run P0 |
| 2026-11-25 | Gemini 4 Hydrogen | P0 repo audit: `Magasin/Amine` has docs only; Flutter app (`AppDatabase`, `Provider`, `Recipes`) exists on `origin/Recette`; `flutter` not in PATH | docs/magasin/HANDOFF.md | Merge base Flutter project (`origin/Recette` or `main`), verify `flutter` SDK, then P1 |
| 2026-11-25 | Gemini 4 Hydrogen | P1 architecture plan drafted (folder tree, DDL, class list, data flows, algorithms, risks, P2–P12 tasks) | docs/magasin/ARCHITECTURE.md, docs/magasin/HANDOFF.md | Review & approve P1 plan, merge `origin/Recette` into `Magasin/Amine`, then start P2 |
| 2026-11-25 | Claude Sonnet 4.6 / Gemini 4 Hydrogen | Merged `origin/Recette`; implemented P2 DB layer (`StoreSchema`, `Store`/`StoreAisle`/`StorePrice`/`OverpassCandidate`, `StoreDao`/`StoreAisleDao`/`StorePriceDao`, `AppDatabase` v2 hook, `store_schema_test.dart`). Could not run `flutter analyze`/`flutter test` (Flutter SDK missing). | lib/features/magasin/data/*, lib/features/magasin/models/*, lib/core/database/app_database.dart, test/features/magasin/data/store_schema_test.dart, docs/magasin/HANDOFF.md | Install Flutter SDK, run `flutter pub get && flutter analyze && flutter test`, then start P3 |

## Known issues / tech debt
- **Flutter/Dart SDK not installed on current machine:** `flutter pub get`, `flutter analyze`, and `flutter test` failed (`flutter` not found in PATH or standard directories). P2 files are written but unverified by the analyzer/test runner.
