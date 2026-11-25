# ARCHITECTURE — Gestion 4 « Magasins »

> **Status:** Approved (P1)  
> **Branch:** `Magasin/Amine`  
> **Scope:** `stores`, `store_aisles`, `store_prices` — CRUD, Overpass import, passive geofencing, magnetometer compass, optimal-store ranking, missing-price estimation, aisle sort, stats, and 7 screens.  
> **Conventions:** Follows `/AGENTS.md` (MVVM: `models` → `data/dao` → `data/repositories` → `services` → `view_models` → `screens/widgets`, `ports/` for read-only cross-gestion interfaces) and integrates into the `origin/Recette` base project via `StoreSchema` and `MagasinModule`.

---

## 1. Folder Tree

All Magasin code lives under `lib/features/magasin/` and `test/features/magasin/`.
The only external touches (post-merge of `origin/Recette`) are minimal hooks in `lib/core/database/app_database.dart` (2 lines: `StoreSchema.create` / `upgrade`), `lib/main.dart` (route/navigation + `MagasinModule.providers`), `pubspec.yaml` (dependencies), and `android/app/src/main/AndroidManifest.xml` (location/notification permissions).

```text
lib/features/magasin/
├── magasin_module.dart                  # Provider wiring & service factory (matches RecipesModule)
├── l10n/
│   └── magasin_strings.dart             # Centralized French UI strings & error messages
├── models/
│   ├── store.dart                       # Store, StoreType enum (supermarket|grocery|market), StoreSource enum (manual|osm)
│   ├── store_aisle.dart                 # StoreAisle
│   ├── store_price.dart                 # StorePrice
│   ├── store_visit.dart                 # Optional lightweight visit/stats DTOs (BasketRankResult, PricePoint, StoreStats)
│   └── overpass_candidate.dart          # Parsed OSM store candidate before persistence
├── ports/
│   ├── product_reader.dart              # Abstract ProductReader + ProductSummary DTO (Gestion 2)
│   ├── shopping_list_reader.dart        # Abstract ShoppingListReader + ShoppingItemSummary DTO (Gestion 5)
│   └── stubs/
│       ├── stub_product_reader.dart     # In-memory Tunisian grocery products stub
│       └── stub_shopping_list_reader.dart # In-memory 6-item shopping list stub
├── logic/                               # Pure Dart only — NO Flutter/sqflite imports
│   ├── geo_math.dart                    # Haversine distance (km/m) + initial bearing (deg) + low-pass heading filter
│   ├── price_estimator.dart             # Missing-price estimation (average across other stores)
│   ├── optimal_store_ranker.dart        # Basket total + travel cost + ranking + tie-breaking
│   └── aisle_sorter.dart                # Reorder ShoppingItemSummary list by store_aisles.sort_order
├── data/
│   ├── store_schema.dart                # StoreSchema.create(db) & StoreSchema.upgrade(db, from, to)
│   ├── dao/
│   │   ├── store_dao.dart               # Parameterized SQLite queries for `stores`
│   │   ├── store_aisle_dao.dart         # Parameterized SQLite queries for `store_aisles`
│   │   └── store_price_dao.dart         # Parameterized SQLite queries for `store_prices` + stats/history
│   ├── repositories/
│   │   ├── store_repository.dart        # Wraps DAOs, transactions (e.g. reorder aisles, upsert OSM)
│   │   └── price_repository.dart        # Wraps StorePriceDao + latest/average/history queries
│   └── remote/
│       └── overpass_client.dart         # HTTP POST to Overpass API (15s timeout, 1 retry, JSON->OverpassCandidate)
├── services/
│   ├── store_service.dart               # Single write entry point for all 3 tables + public API for other gestions
│   ├── location_service.dart            # Wrapper over geolocator (permissions, reduced-accuracy/live position)
│   ├── geofence_manager.dart            # Wrapper over geofence_service + flutter_local_notifications + debounce + toggle
│   └── compass_service.dart             # Wrapper over sensors_plus magnetometer (active only when screen visible)
├── view_models/                         # ChangeNotifier classes; call StoreService/sensors, never DB/HTTP directly
│   ├── store_list_view_model.dart       # List, search, sort (distance/name/avg basket), delete, geofence toggle
│   ├── store_map_view_model.dart        # Map markers, long-press add, Overpass import flow
│   ├── store_detail_view_model.dart     # Single store info, favorite toggle, quick stats
│   ├── aisle_editor_view_model.dart     # Add/rename/delete/reorder aisles
│   ├── price_records_view_model.dart    # List/add/edit/delete prices + price evolution chart data
│   ├── basket_comparator_view_model.dart# Runs optimal-store ranking + aisle-sorted preview + "Go to compass" handoff
│   └── compass_view_model.dart          # Target store, smoothed heading, bearing, distance, calibration hint
└── screens/                             # 7 screens + shared widgets; light/dark Theme.of(context), French UI
    ├── store_list_screen.dart           # Screen 1: List + search/sort + Overpass import trigger + nav to map/comparator/stats
    ├── store_map_screen.dart            # Screen 2: flutter_map OSM tiles, markers, long-press add, Overpass candidates sheet
    ├── store_detail_screen.dart         # Screen 3: Store metadata, favorite, links to aisles/prices/compass, edit/delete
    ├── aisle_editor_screen.dart         # Screen 4: ReorderableListView for aisles
    ├── price_records_screen.dart        # Screen 5: Price history per store + fl_chart evolution + add/edit/delete dialog
    ├── basket_comparator_screen.dart    # Screen 6: Ranked stores (total, estimated count, travel cost) + aisle-sorted list + launch compass
    ├── compass_screen.dart              # Screen 7: Real-time rotated arrow toward target store + remaining distance
    └── widgets/
        ├── store_form_dialog.dart       # Create/edit store form (manual or prefilled from map/OSM)
        ├── store_stats_sheet.dart       # Most visited / price stats summary (fl_chart)
        └── permission_rationale_dialog.dart # French explanation before requesting location/background/notification perms

test/features/magasin/
├── logic/
│   ├── geo_math_test.dart
│   ├── price_estimator_test.dart
│   ├── optimal_store_ranker_test.dart
│   └── aisle_sorter_test.dart
├── data/
│   ├── store_schema_test.dart           # sqflite_common_ffi in-memory: DDL, FK cascade, user_id isolation
│   ├── store_dao_test.dart
│   ├── store_price_dao_test.dart
│   └── overpass_client_test.dart        # Fixture JSON + timeout/error handling
├── services/
│   └── store_service_test.dart          # Fake repositories + stub ports
└── screens/
    └── store_list_screen_test.dart      # Widget test with mock/stub ViewModel
```

---

## 2. Database Schema, Indexes & Migration Strategy

### 2.1 Validated SQLite DDL (`StoreSchema`)

Adjustments from `SPEC_MAGASIN.md` after P0 audit of `origin/Recette`:
1. **`store_prices.product_id`**: Keep `product_id INTEGER NOT NULL` **without** `REFERENCES products(id)` in `StoreSchema` (matching `RecipeSchema` in `origin/Recette`). With `PRAGMA foreign_keys = ON`, referencing an uncreated table owned by Gestion 2 would fail during standalone execution/tests until all 6 schemas are merged.
2. **Partial unique index for Overpass deduplication**: Use `CREATE UNIQUE INDEX idx_stores_user_osm ON stores(user_id, osm_id) WHERE osm_id IS NOT NULL;` so manual stores (`osm_id IS NULL`) never collide while OSM imports are idempotent per user.
3. **Additional indexes** for `user_id` filtering, `store_aisles(store_id, sort_order)`, and `store_prices(product_id)` (needed for cross-store average price estimation).

```sql
CREATE TABLE stores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('supermarket', 'grocery', 'market')),
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  address TEXT,
  opening_hours TEXT,
  notification_radius_m INTEGER NOT NULL DEFAULT 200 CHECK (notification_radius_m > 0),
  is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
  osm_id TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'osm')),
  created_at TEXT NOT NULL
);

CREATE INDEX idx_stores_user ON stores(user_id);
CREATE UNIQUE INDEX idx_stores_user_osm ON stores(user_id, osm_id) WHERE osm_id IS NOT NULL;

CREATE TABLE store_aisles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE INDEX idx_aisles_store_order ON store_aisles(store_id, sort_order);

CREATE TABLE store_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL,
  price REAL NOT NULL CHECK (price >= 0),
  recorded_at TEXT NOT NULL
);

CREATE INDEX idx_prices_store_product ON store_prices(store_id, product_id, recorded_at DESC);
CREATE INDEX idx_prices_product ON store_prices(product_id);
```

### 2.2 Registration & Migration Strategy
- `StoreSchema.create(DatabaseExecutor db)` executes the DDL above.
- `StoreSchema.upgrade(DatabaseExecutor db, int from, int to)` handles incremental `if (from < N)` migrations (never mutating a shipped version).
- In `lib/core/database/app_database.dart` (post-merge):
  - Increment `AppDatabase.version` when integrating `StoreSchema` into an existing DB.
  - Call `await StoreSchema.create(db);` in `_onCreate` and `await StoreSchema.upgrade(db, from, to);` in `_onUpgrade`.
- `PRAGMA foreign_keys = ON` is already configured in `AppDatabase.open()`, guaranteeing `ON DELETE CASCADE` from `stores` to `store_aisles` and `store_prices`.

---

## 3. Class List per Layer & Public APIs

### 3.1 Models (`models/`)
- `StoreType` (`supermarket`, `grocery`, `market`), `StoreSource` (`manual`, `osm`)
- `Store`: `id`, `userId`, `name`, `type`, `latitude`, `longitude`, `address`, `openingHours`, `notificationRadiusM`, `isFavorite`, `osmId`, `source`, `createdAt`; `fromMap`, `toMap`, `copyWith`.
- `StoreAisle`: `id`, `storeId`, `name`, `sortOrder`; `fromMap`, `toMap`, `copyWith`.
- `StorePrice`: `id`, `storeId`, `productId`, `price` (DT, 3 decimals), `recordedAt` (ISO-8601); `fromMap`, `toMap`, `copyWith`.
- `OverpassCandidate`: `osmId`, `name`, `type`, `latitude`, `longitude`, `address`, `openingHours`.
- `BasketItemEstimate`, `StoreBasketRank`, `PricePoint` (value objects for ranking & stats).

### 3.2 Ports & Stubs (`ports/`)
- `ProductSummary`: `id`, `name`, `category`, `defaultAisle` (nullable).
- `ProductReader`:
  - `Future<ProductSummary?> getProductById(int id);`
  - `Future<List<ProductSummary>> getProductsByIds(List<int> ids);`
  - `Future<List<ProductSummary>> searchProducts(String query);`
- `ShoppingItemSummary`: `id`, `productId`, `label`, `quantity`, `isChecked`, `aisleHint`.
- `ShoppingListReader`:
  - `Future<List<ShoppingItemSummary>> getActiveListItems(int userId);`
  - `Future<int> getUncheckedItemCount(int userId);`
- `StubProductReader` & `StubShoppingListReader`: deterministic Tunisian grocery dataset (e.g., Lait, Pain, Huile d'olive, Tomates, Pâtes, Sucre) so Magasin runs standalone and offline.

### 3.3 DAOs & Repositories (`data/`)
- `StoreDao`: `insert`, `update`, `delete(id, userId)`, `findById(id, userId)`, `findByUser(userId, {query, type})`, `findByOsmId(userId, osmId)`, `setFavorite(id, userId, isFavorite)`.
- `StoreAisleDao`: `insert`, `update`, `delete(id)`, `findByStore(storeId)`, `updateOrders(List<StoreAisle>)`.
- `StorePriceDao`: `insert`, `update`, `delete(id)`, `findByStore(storeId)`, `findLatestForStore(storeId, productIds)`, `findLatestAcrossOtherStores(excludeStoreId, productIds, userId)`, `findHistory(storeId, productId)`.
- `StoreRepository` & `PriceRepository`: wrap DAOs, manage DB transactions (e.g., atomic aisle reorder, idempotent OSM upsert).

### 3.4 `StoreService` Public API (`services/store_service.dart`)
Only entry point for all writes to `stores`, `store_aisles`, `store_prices` and public contract for other gestions:
- **Store CRUD**:
  - `Future<List<Store>> getStores(int userId, {String? query, StoreType? type})`
  - `Future<Store?> getStoreById(int id, int userId)`
  - `Future<Store?> getFavoriteStore(int userId)`
  - `Future<Store> createStore(Store store)`
  - `Future<void> updateStore(Store store)`
  - `Future<void> deleteStore(int id, int userId)`
  - `Future<void> toggleFavorite(int id, int userId)`
  - `Future<List<Store>> importOverpassCandidates(int userId, List<OverpassCandidate> candidates)`
- **Aisles**:
  - `Future<List<StoreAisle>> getAisleOrder(int storeId)`
  - `Future<StoreAisle> addAisle(int storeId, String name)`
  - `Future<void> renameAisle(int aisleId, String name)`
  - `Future<void> deleteAisle(int aisleId)`
  - `Future<void> reorderAisles(int storeId, List<int> orderedAisleIds)`
- **Prices**:
  - `Future<List<StorePrice>> getStorePrices(int storeId)`
  - `Future<StorePrice?> getLatestPrice(int storeId, int productId)`
  - `Future<List<PricePoint>> getPriceHistory(int storeId, int productId)`
  - `Future<StorePrice> recordPrice(StorePrice price)`
  - `Future<void> updatePrice(StorePrice price)`
  - `Future<void> deletePrice(int priceId)`
- **Advanced Logic (delegating to pure `logic/` classes)**:
  - `Future<List<StoreBasketRank>> rankStoresForBasket(int userId, {double? userLat, double? userLng, double travelCostPerKm = 0.500})`
  - `Future<List<ShoppingItemSummary>> sortItemsByAisle(int storeId, List<ShoppingItemSummary> items)`

### 3.5 Sensors, API & UI Layers
- **Remote**: `OverpassClient` (`fetchNearbyStores(lat, lng, radiusMeters)` — POST Overpass QL, 15s timeout, 1 retry).
- **Sensors**: `LocationService`, `GeofenceManager`, `CompassService`.
- **ViewModels**: `StoreListViewModel`, `StoreMapViewModel`, `StoreDetailViewModel`, `AisleEditorViewModel`, `PriceRecordsViewModel`, `BasketComparatorViewModel`, `CompassViewModel`.
- **Screens (7)**: `StoreListScreen`, `StoreMapScreen`, `StoreDetailScreen`, `AisleEditorScreen`, `PriceRecordsScreen`, `BasketComparatorScreen`, `CompassScreen`.

---

## 4. Data Flows for the 3 Hard Features

### 4.1 Passive Geofencing Notification
1. User enables geofencing (settings toggle) → `LocationService` shows French rationale dialog, requests `locationWhenInUse`, then `locationAlways` (Android 10+) + notification permission.
2. `StoreService.getStores(userId)` provides registered stores with `(id, name, latitude, longitude, notificationRadiusM)`.
3. `GeofenceManager` registers regions with `geofence_service` (low-frequency polling, reduced accuracy until near a store). Whenever stores are added/edited/deleted, `StoreListViewModel` / `StoreDetailViewModel` triggers `GeofenceManager.syncRegions(stores)`.
4. On `GeofenceStatus.ENTER` for `storeId` → check per-store cooldown/debounce (e.g., 30 min) → query `ShoppingListReader.getUncheckedItemCount(userId)` → if count > 0, fire local notification via `flutter_local_notifications`: *"Vous passez près de {store.name} — {count} articles dans votre liste."*

### 4.2 Optimal Store Ranking
1. `BasketComparatorViewModel` requests `StoreService.rankStoresForBasket(userId, userLat, userLng)`.
2. `StoreService` fetches:
   - `items = await shoppingListReader.getActiveListItems(userId)` (unchecked items)
   - `stores = await storeRepository.findByUser(userId)`
   - For each store: latest recorded prices for `items.map((i) => i.productId)` via `priceRepository.findLatestForStore`.
   - For any missing `(store, productId)`: average of latest prices across other user stores via `priceRepository.findLatestAcrossOtherStores`, flagged `isEstimated = true`.
3. `OptimalStoreRanker` computes `totalCost = itemsCost + travelCost` and sorts ascending.
4. `BasketComparatorScreen` displays ranked stores, estimated-price badges, and aisle-sorted items for the selected store.

### 4.3 Compass Target ("Boussole vers le magasin le plus rentable")
1. From `BasketComparatorScreen` (or `StoreDetailScreen`), user taps *"Aller au magasin (Boussole)"* → navigates to `CompassScreen(targetStore: bestStore)`.
2. `CompassScreen.initState` starts `CompassViewModel.start(targetStore)`:
   - Subscribes to `LocationService.positionStream` (high accuracy while screen is open) to compute Haversine distance + target bearing.
   - Subscribes to `CompassService.headingStream` (`sensors_plus` magnetometer + accelerometer/heading, smoothed with low-pass filter `α = 0.15`).
   - Arrow rotation angle = `(bearingDeg - smoothedHeadingDeg) * pi / 180`.
3. `CompassScreen.dispose` cancels both subscriptions immediately so battery/sensors are freed.

---

## 5. Algorithms (Pseudo-Code)

### 5.1 Haversine Distance & Bearing (`geo_math.dart`)
```text
function haversineKm(lat1, lon1, lat2, lon2):
  R = 6371.0
  dLat = degToRad(lat2 - lat1)
  dLon = degToRad(lon2 - lon1)
  a = sin(dLat/2)^2 + cos(degToRad(lat1)) * cos(degToRad(lat2)) * sin(dLon/2)^2
  c = 2 * atan2(sqrt(a), sqrt(1 - a))
  return R * c

function bearingDeg(lat1, lon1, lat2, lon2):
  y = sin(dLon) * cos(degToRad(lat2))
  x = cos(degToRad(lat1)) * sin(degToRad(lat2)) - sin(degToRad(lat1)) * cos(degToRad(lat2)) * cos(dLon)
  return (radToDeg(atan2(y, x)) + 360) % 360

function lowPassHeading(prevDeg, newDeg, alpha = 0.15):
  // Shortest-angle delta in [-180, 180] to handle 359° -> 1° wraparound
  delta = ((newDeg - prevDeg + 540) % 360) - 180
  return (prevDeg + alpha * delta + 360) % 360
```

### 5.2 Missing-Price Estimation (`price_estimator.dart`)
```text
function estimateUnitPrice(storeId, productId, latestByStoreAndProduct):
  if (storeId, productId) in latestByStoreAndProduct:
    return (price: latestByStoreAndProduct[storeId][productId], isEstimated: false, isUnknown: false)

  otherPrices = [p for (s, prod, p) in latestByStoreAndProduct where prod == productId and s != storeId]
  if otherPrices is not empty:
    avg = sum(otherPrices) / len(otherPrices)
    return (price: round3(avg), isEstimated: true, isUnknown: false)

  return (price: 0.0, isEstimated: true, isUnknown: true)
```

### 5.3 Optimal Store Ranking (`optimal_store_ranker.dart`)
```text
function rankStores(stores, items, priceLookup, userLat, userLng, travelCostPerKm):
  results = []
  for store in stores:
    itemsCost = 0.0
    estimatedCount = 0
    unknownCount = 0
    for item in items:
      est = estimateUnitPrice(store.id, item.productId, priceLookup)
      itemsCost += est.price * item.quantity
      if est.isEstimated: estimatedCount += 1
      if est.isUnknown: unknownCount += 1

    distanceKm = (userLat != null && userLng != null)
      ? haversineKm(userLat, userLng, store.latitude, store.longitude)
      : 0.0
    travelCost = round3(travelCostPerKm * distanceKm)
    totalCost = round3(itemsCost + travelCost)
    results.add(StoreBasketRank(store, itemsCost, travelCost, totalCost, distanceKm, estimatedCount, unknownCount))

  sort results by:
    1. unknownCount ascending (prefer stores with fewer completely unknown prices)
    2. totalCost ascending
    3. distanceKm ascending
  return results
```

### 5.4 Aisle Sort (`aisle_sorter.dart`)
```text
function sortItemsByAisle(aislesOrdered, items, productAisleHints):
  aisleIndex = { normalize(a.name): a.sortOrder for a in aislesOrdered }
  return items sorted stably by:
    hint = normalize(item.aisleHint ?? productAisleHints[item.productId] ?? '')
    order = aisleIndex[hint] ?? INFINITY   // unmatched items placed at the end
    then original index
```

---

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Android 10+ background location & battery drain** | OS kills geofence service or denies `ACCESS_BACKGROUND_LOCATION` | Two-step permission flow with French explanation; low-frequency sampling + reduced accuracy until near a store; settings toggle to disable geofencing; debounce notifications (30 min/store). |
| **Android geofence count limit (~100 regions)** | Registration fails if user imports many OSM stores | Register up to nearest/favorite 50 stores sorted by distance, and re-sync when user moves significantly or edits stores. |
| **Overpass API timeouts / rate limits (429/504)** | Import hangs or crashes UI | Strict 15 s timeout, 1 retry on transient network error, friendly French error banner, local SQLite cache always works offline. |
| **Magnetometer noise & gimbal wraparound** | Jittery compass arrow or 359°↔0° spin | Shortest-angle low-pass filter (`α = 0.15`), cancel stream in `dispose()`, show calibration hint if sensor is unreliable. |
| **Cross-gestion table absence (`products`)** | FK failure on `store_prices.product_id` before team integration | Omit SQL `REFERENCES products(id)` in `StoreSchema` (same pattern as `RecipeSchema`); access products via `ProductReader` port + stub. |
| **Branch divergence (`Magasin/Amine` vs `origin/Recette`)** | Missing `pubspec.yaml` and `AppDatabase` | Merge `origin/Recette` into `Magasin/Amine` before starting P2. |

---

## 7. Ordered Task List (P2 → P12)

| Phase | Scope | Est. Effort |
|---|---|---|
| **Prep** | Merge `origin/Recette` into `Magasin/Amine`, verify `flutter analyze` & `flutter test` | 0.5 h |
| **P2** | `StoreSchema`, models (`Store`, `StoreAisle`, `StorePrice`), DAOs, `sqflite_common_ffi` unit tests | 3 h |
| **P3** | Repositories, `StoreService`, `ProductReader` / `ShoppingListReader` ports + stubs, `MagasinModule`, service tests | 2.5 h |
| **P4** | CRUD ViewModels + 5 CRUD/Map screens (`flutter_map`), French strings, light/dark theme, widget test | 5 h |
| **P5** | `OverpassClient` (15 s timeout, retry, fixture tests) + OSM import UI + deduplication | 2.5 h |
| **P6** | Passive geofencing (`geolocator`, `geofence_service`, `flutter_local_notifications`), permissions, AndroidManifest notes | 3.5 h |
| **P7** | `CompassService` (magnetometer + low-pass filter) + `CompassScreen` | 2 h |
| **P8** | Pure `geo_math`, `optimal_store_ranker`, `BasketComparatorScreen` + "comparator → compass" handoff | 3 h |
| **P9** | `price_estimator` + `aisle_sorter` + unit tests + integration in comparator/detail | 2 h |
| **P10** | Sort/search polish + `fl_chart` price evolution & most-visited stats | 2.5 h |
| **P11** | Hardening, edge-case & widget tests, `flutter analyze` + `dart format` | 2 h |
| **P12** | Final review, `AppDatabase` & `main.dart` minimal integration hooks, team port swap | 1.5 h |
