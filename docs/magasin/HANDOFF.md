# HANDOFF — Gestion 4 « Magasins » (Amine)

> Update this file at the end of every work session / agent task. A fresh agent must be able to continue from here alone.

**Repo:** https://github.com/hajeuur/ProjetMobile — **Branch:** `Magasin/Amine`
**Last updated:** 2026-11-25 — **State:** project start, no code yet.

## Context in 5 lines
PanierMalin: Flutter app, local SQLite, MVVM, 6 gestions, one owner each. I own Magasins:
reference stores, notify passively when near one (geofence), compass arrow to chosen store,
compute the cheapest basket store (prices + travel cost), sort shopping list by aisle.
Full requirements: `SPEC_MAGASIN.md`. Rules: `/AGENTS.md`.

## Status checklist
- [ ] P0  Repo audit + environment check
- [ ] P1  Architecture plan approved
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
- DB: sqflite (not drift).
- State management: Provider (provisional, team not decided).
- Map: flutter_map + OSM tiles (no API key). *(provisional)*
- Currency in DT, stored as REAL. *(provisional — confirm with Gestion 5 owner so receipts use the same type)*

## Open questions (ask the team / teacher)
1. Provider vs Riverpod — who decides, when?
2. Who writes the shared `DatabaseHelper` (weeks 1-2)? I need a hook to register my 3 tables.
3. Extra columns I want on `stores`: `user_id` (required by spec), `osm_id`, `source`, `created_at`. OK?
4. Interface I need from Gestion 2: `getProductById(id)`, `getProductsByIds(ids)`.
5. Interface I need from Gestion 5: `getActiveListItems(userId)` -> items with `product_id`, `quantity`, `label`; and count of unchecked items.
6. Date of the final defense (planning not dated).

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

## Known issues / tech debt
_(none yet)_
