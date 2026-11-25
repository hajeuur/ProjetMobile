# SPEC — Gestion 4 « Magasins » (extracted from the cahier des charges PanierMalin, 9 oct. 2026)

Purpose: list neighborhood stores, notify the user when passing near one, point to the chosen store,
and designate the most profitable store for a given basket.

## Entities (owned)
- `stores`: id, nom, type (supermarché | épicerie | marché), latitude, longitude, adresse, horaires, rayon de notification (m), favori.
- `store_aisles`: id, store_id, nom du rayon, ordre de passage.
- `store_prices`: id, store_id, product_id, prix relevé, date du relevé.
- Root table rule: `user_id` on `stores` (data separated per logged user).

### Proposed SQLite DDL (to validate with team)
```sql
CREATE TABLE stores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('supermarket','grocery','market')),
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  address TEXT,
  opening_hours TEXT,
  notification_radius_m INTEGER NOT NULL DEFAULT 200,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  osm_id TEXT,                          -- proposed: dedupe Overpass imports
  source TEXT NOT NULL DEFAULT 'manual',-- proposed: manual | osm
  created_at TEXT NOT NULL,
  UNIQUE (user_id, osm_id)
);
CREATE TABLE store_aisles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);
CREATE TABLE store_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id),
  price REAL NOT NULL,
  recorded_at TEXT NOT NULL
);
CREATE INDEX idx_prices_store_product ON store_prices(store_id, product_id, recorded_at DESC);
```

## CRUD
- Add a store: manually, from the map (long-press), or from the Overpass result list.
- Edit hours, aisles and their order; delete a store.
- Record, edit, delete a price.

## Sensors
- **GPS — passive geofencing:** entering a registered store's radius => local notification with the number of items in the current shopping list. No user action.
- **Magnetometer — compass:** arrow oriented in real time toward the chosen store (nearest or most profitable) + remaining distance.

## Advanced logic
1. **Optimal store:** for the current shopping list, estimate total cost in each store from latest recorded prices, add travel cost proportional to distance, rank stores.
2. **Missing prices:** unknown price => average of other stores' prices for that product; flagged as *estimate*.
3. **Aisle sort:** reorder list items following the chosen store's aisle order.

## API
OpenStreetMap Overpass: supermarkets, groceries, markets within a radius of the current position (name + coordinates). Cache results locally.

## Basic functions
- Sort by distance, name, or average basket. Search by name or type.
- Stats: most visited stores; price evolution of a product per store.

## Screens (7)
Store map, list, store detail, aisle editor, price records, basket comparator, compass.

## Non-functional (relevant)
Offline for everything except API calls; failed API calls reported without blocking; reduced-accuracy location until near a store; low-frequency passive sampling; sensor can be disabled in settings; permissions asked at first use with a French explanation; French UI, light/dark theme; background location permission required.

## Demo contribution (step 5)
"Boussole vers le magasin le plus rentable" — the comparator result must feed the compass target.
