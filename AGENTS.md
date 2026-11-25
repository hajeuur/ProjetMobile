# AGENTS.md — PanierMalin / Gestion 4 « Magasins »

You are helping **Amine**, who owns **Gestion 4 — Magasins** of the PanierMalin Flutter app
(team project, 6 gestions, one owner each). Read this file fully before every task.
Then read `docs/magasin/HANDOFF.md` (current state) and `docs/magasin/SPEC_MAGASIN.md` (requirements).

## Scope — what I own
Tables: `stores`, `store_aisles`, `store_prices`. Nothing else.
Features: store CRUD, aisles + order, price records, Overpass (OpenStreetMap) import,
passive geofencing notification, magnetometer compass, optimal-store algorithm,
missing-price estimation, shopping-list sort by aisle, sort/search/stats, 7 screens.

## Hard rules (ownership)
1. Only create/update/delete rows in my own 3 tables, and only through `StoreService`.
2. Other gestions' data (`products`, `shopping_lists`, `shopping_items`, ...) is **read-only** for me,
   accessed through small abstract interfaces in `lib/features/magasin/ports/`
   (e.g. `ProductReader`, `ShoppingListReader`) with **stub implementations** until teammates deliver.
3. Never edit files outside `lib/features/magasin/` and `test/features/magasin/`, except:
   - adding my route(s)/menu entry, and my table DDL registration in the shared DB setup, in the minimal way possible;
   - `pubspec.yaml` dependencies I need (list them in the HANDOFF log).
   Anything in `lib/core/` belongs to the team: propose changes, do not make them silently.
4. Every root table carries `user_id`; every query for stores filters on the current user.
5. Do not push to `main`. Work on branch `Magasin/Amine`. Small commits, conventional messages (`feat(magasin): ...`).

## Stack & conventions
- Flutter/Dart, Android first. SQLite via **sqflite** (no drift). State: **Provider** (default; switch only if the team decides Riverpod — see HANDOFF open questions).
- Architecture MVVM: `models` → `data/dao` → `data/repositories` → `services` → `view_models` → `screens/widgets`.
- Screens never touch the DB or HTTP directly. View models call services; services call repositories.
- Packages: `geolocator`, `geofence_service`, `sensors_plus` (magnetometer), `flutter_local_notifications`,
  `http`, `fl_chart`, `flutter_map` + `latlong2` (OSM map; no API key needed). Ask before adding others.
- Code, identifiers, comments: **English**. UI strings: **French** (centralize in one file for later l10n). Currency: **DT** (TND, 3 decimals).
- Light + dark theme: use `Theme.of(context)`, no hard-coded colors.
- Dart null-safety, `flutter analyze` clean, `dart format` applied.
- Pure logic (optimal store, price estimation, aisle sort, distance, bearing) lives in plain Dart classes with **unit tests** — no Flutter imports.

## Database rules
- Schema versioned with `onCreate` / `onUpgrade` migrations; never edit a shipped migration, add a new one.
- Enable `PRAGMA foreign_keys = ON`. Deleting a store cascades to aisles and prices.
- Use parameterized queries only. Map rows <-> models in the model class (`fromMap` / `toMap`).
- Tests use `sqflite_common_ffi` with an in-memory DB.

## API rules
- Overpass: POST query, timeout 15 s, handle errors without blocking UI, cache result into `stores` (source = `osm`, unique `osm_id`) so the feature works offline afterwards.
- Never hard-code secrets. Network failure => friendly French message + continue with local data.

## Sensors / permissions
- Ask permission at first use with an explanatory sentence (French). Handle denied / permanently denied.
- Geofencing: reduced accuracy until near a store; low-frequency sampling; the sensor can be disabled in settings.
- Compass: magnetometer only while the compass screen is visible; low-pass filter on heading; cancel subscriptions in `dispose`.

## How to work (agent workflow)
1. **Plan first** for any task > 1 file: list files to touch, risks, and wait for approval.
2. Implement in small steps; run `flutter analyze` and `flutter test` after each step.
3. Never invent requirements. If the spec is ambiguous, add the question to HANDOFF > Open questions and ask.
4. After finishing a task, **update `docs/magasin/HANDOFF.md`** (status checklist, decisions, log entry, next step).
5. Don't refactor unrelated code; don't rename public service methods without noting it in HANDOFF.

## Definition of done (per task)
Compiles, analyzer clean, tests for new logic pass, works offline (except API calls), no touched files outside scope, HANDOFF updated.
