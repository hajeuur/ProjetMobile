# PROMPTS — Antigravity playbook for Gestion 4 « Magasins »

## Model strategy (based on the models currently available)
Quotas are weekly and split in two pools: **Gemini** (Hydrogen, 3.8 Flash) and **Claude + GPT-OSS**. The Claude pool is the scarce one, so spend it only where reasoning matters. You have 2 Google accounts: when a pool runs out, switch account and continue (HANDOFF + AGENTS.md make that painless — every new session starts with the "session starter" below).

| Role | Model | Use for |
|---|---|---|
| Architect / auditor | **Claude Opus 4.6 (Thinking)** | P1 plan, P8 algorithm, P12 audit. Few, high-value prompts. |
| Main implementer | **Claude Sonnet 4.6 (Thinking)** | P2, P3, P5, P6, P9 — data layer, services, API, background logic. |
| UI + sensors + volume | **Gemini 4 Hydrogen (Medium)** | P4, P7, P10 — screens, view models, charts, compass. |
| Quick fixes | **Gemini 3.8 Flash** | Small bugs, renames, formatting (it is "Leaving Soon", don't depend on it). |
| Cheap grunt work | **GPT-OSS 120B** | P11 extra tests, doc comments, README polish. |

Rules: Planning mode for P1-P3, P5, P6, P8, P12. Fast mode is fine for P4, P7, P10, P11.
Never put two different models on the same task at the same time (merge conflicts in one branch).

## Session starter (paste at the beginning of EVERY new conversation/account/model)
```
Read /AGENTS.md, docs/magasin/HANDOFF.md and docs/magasin/SPEC_MAGASIN.md.
Summarize in 6 lines: scope, current status, next step. Do not write code yet.
Then wait for my instruction.
```

---
## P0 — Repo audit (Gemini 4 Hydrogen, Fast)
```
Read /AGENTS.md, docs/magasin/HANDOFF.md and docs/magasin/SPEC_MAGASIN.md.
Then audit the repo on branch Magasin/Amine (read-only, change nothing):
1. Flutter/Dart versions, pubspec dependencies already present, folder structure under lib/.
2. Does a shared DatabaseHelper / lib/core exist? How are tables registered? Is there a navigation/theme/permission setup?
3. Which state management is already used (Provider or Riverpod)?
4. List anything that conflicts with AGENTS.md or blocks my work.
Output a short report and propose edits to the "Open questions" in HANDOFF.md. Do not modify files other than HANDOFF.md.
```

## P1 — Architecture plan (Claude Opus 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Using SPEC_MAGASIN.md and the P0 audit, produce a written implementation plan ONLY (no code):
1. Folder tree under lib/features/magasin/ and test/features/magasin/.
2. Final SQL schema (validate/adjust my proposed DDL), indexes, migration strategy, how my tables get registered in the shared DB without editing core logic.
3. Class list per layer (models, DAOs, repositories, StoreService public API with signatures, ports + stubs for ProductReader / ShoppingListReader, view models, screens).
4. Data flow for the 3 hard features: geofencing notification, optimal store ranking, compass target.
5. Algorithms in pseudo-code: ranking (cost = sum of prices + estimates + travel_coef * distance_km), missing-price estimation, aisle sort, Haversine + bearing.
6. Risks (background location on Android 10+, battery, geofence limits, Overpass timeouts) and mitigations.
7. Ordered task list matching P2..P12 with estimated effort.
Write the plan to docs/magasin/ARCHITECTURE.md and update HANDOFF.md decisions. Stop and wait for my approval.
```

## P2 — Database layer (Claude Sonnet 4.6 Thinking, Planning)
```
Follow /AGENTS.md and docs/magasin/ARCHITECTURE.md (approved).
Implement ONLY the data layer: models (Store, StoreAisle, StorePrice with fromMap/toMap/copyWith), enums, table DDL + migration hook, DAOs with full CRUD and the queries needed for: stores by user, search by name/type, latest price per (store, product), prices history, average price of a product across other stores, aisles ordered.
Add unit tests with sqflite_common_ffi (in-memory): CRUD, cascade delete, foreign keys, user_id isolation.
Run flutter analyze + flutter test. Update HANDOFF.md. Do not build UI.
```

## P3 — Repositories, service, ports (Claude Sonnet 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Implement repositories over the DAOs, the public StoreService (only entry point for writes to my tables), and the ports ProductReader and ShoppingListReader with in-memory stub implementations (fake data: a few Tunisian products and a 6-item list).
Add dependency injection with Provider. Unit-test the service with fake repositories.
Update HANDOFF.md "Interfaces I expose / consume".
```

## P4 — CRUD view models + screens (Gemini 4 Hydrogen, Fast)
```
Follow /AGENTS.md. Build view models (ChangeNotifier) and screens: store list, store detail, add/edit store form, aisle editor (reorderable list), price records (list + add/edit/delete). French UI, light/dark theme, empty/loading/error states, confirm dialogs on delete. Use flutter_map for the store map screen with long-press to add a store.
Screens only talk to view models; view models only to StoreService. Add simple widget tests for the list screen. Update HANDOFF.md.
```

## P5 — Overpass import + cache (Claude Sonnet 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Implement OverpassClient (http, 15 s timeout, retry once), query for shop=supermarket|convenience|greengrocer and amenity=marketplace around the current position (radius configurable, default 2 km), a parser to Store candidates, and an "import from API" flow: list candidates, user picks, they are saved with source=osm and unique osm_id (no duplicates on re-import). Fully handle offline/failure: friendly French message, local data still works. Unit-test the parser with a saved JSON fixture. Update HANDOFF.md.
```

## P6 — Passive geofencing (Claude Sonnet 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Implement passive geofencing with geolocator + geofence_service + flutter_local_notifications: register a geofence for each store using its notification_radius_m; on ENTER, send a notification "N articles dans ta liste" using ShoppingListReader (stub for now). Handle: permission flow incl. background location (Android 10+), reduced accuracy when far, re-registering geofences when stores change, a settings toggle to disable it, debounce so one visit = one notification. Document the Android manifest changes needed and test steps on a real phone (emulator mock locations). Update HANDOFF.md.
```

## P7 — Compass (Gemini 4 Hydrogen, Fast)
```
Follow /AGENTS.md. Implement the compass screen with sensors_plus magnetometer: pure-Dart helper for bearing and Haversine distance (unit-tested), heading with low-pass filter, a rotating arrow to the target store, remaining distance (m/km), calibration hint when the signal is unstable, target selectable (nearest / most profitable / any store). Subscribe only while the screen is visible. Update HANDOFF.md.
```

## P8 — Optimal store algorithm (Claude Opus 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Implement BasketRanker as pure Dart: input = list items (product_id, quantity), stores, latest prices, user position, travel coefficient (DT per km, configurable constant); output = ranked stores with itemsCost, travelCost, total, number of estimated prices, and missing items. Use missing-price estimation (average of other stores, flagged estimated; if no price anywhere, mark item "unpriced" and exclude from total but show it). Handle edge cases: empty list, no stores, no GPS, single store, quantity > 1, stale prices (> 90 days warn). Write thorough unit tests (table-driven) then the comparator screen (view model + UI) and feed the winner to the compass. Update HANDOFF.md with the formula.
```

## P9 — Aisle sort (Claude Sonnet 4.6 Thinking, Fast)
```
Follow /AGENTS.md. Implement sortItemsByAisle(storeId, items) in StoreService (pure sorter class + tests): items map to aisles via category/keyword matching defined in a small configurable map; unmatched items go last in original order; stable sort. Expose it for Gestion 5. Update HANDOFF.md.
```
> Open point: how does an item map to an aisle? Ask the team (product category from Gestion 2 vs. manual aisle assignment). Record the answer in HANDOFF.

## P10 — Sort, search, stats (Gemini 4 Hydrogen, Fast)
```
Follow /AGENTS.md. Add sorting (distance, name, average basket), search (name, type), and a statistics screen with fl_chart: most visited stores (use a lightweight visit counter incremented on geofence ENTER — propose the table/column change first, do not add it silently) and price evolution of a product per store (line chart). Update HANDOFF.md.
```

## P11 — Tests & hardening (GPT-OSS 120B, Fast)
```
Follow /AGENTS.md. Review test/features/magasin/ for gaps. Add unit tests for edge cases in services and pure logic, and fix only test-side issues. Run flutter analyze, flutter test, dart format. List any bug found instead of fixing production code, in HANDOFF.md > Known issues.
```

## P12 — Final audit (Claude Opus 4.6 Thinking, Planning)
```
Follow /AGENTS.md. Audit my whole feature against SPEC_MAGASIN.md line by line: missing requirements, ownership violations (writes outside my tables, edits outside my folders), offline behavior, permission flows, battery (listeners disposed), security, performance. Output a checklist with PASS/FAIL and a prioritized fix list. Then prepare an integration checklist for teammates and a 2-minute demo script for step 5 of the scenario.
```
