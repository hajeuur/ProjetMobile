/// Store type as defined in the DDL CHECK constraint.
enum StoreType {
  supermarket('supermarket'),
  grocery('grocery'),
  market('market');

  const StoreType(this.value);
  final String value;

  static StoreType fromString(String s) =>
      StoreType.values.firstWhere((e) => e.value == s,
          orElse: () => throw ArgumentError('Unknown StoreType: $s'));
}

/// Data source: entered manually or imported from OpenStreetMap/Overpass.
enum StoreSource {
  manual('manual'),
  osm('osm');

  const StoreSource(this.value);
  final String value;

  static StoreSource fromString(String s) =>
      StoreSource.values.firstWhere((e) => e.value == s,
          orElse: () => throw ArgumentError('Unknown StoreSource: $s'));
}

/// Represents a row in the `stores` table.
class Store {
  const Store({
    this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.openingHours,
    this.notificationRadiusM = 200,
    this.isFavorite = false,
    this.osmId,
    this.source = StoreSource.manual,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String name;
  final StoreType type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? openingHours;
  final int notificationRadiusM;
  final bool isFavorite;
  final String? osmId;
  final StoreSource source;
  final String createdAt; // ISO-8601

  // ── Serialization ──────────────────────────────────────────────────────────

  factory Store.fromMap(Map<String, dynamic> m) => Store(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        name: m['name'] as String,
        type: StoreType.fromString(m['type'] as String),
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        address: m['address'] as String?,
        openingHours: m['opening_hours'] as String?,
        notificationRadiusM: m['notification_radius_m'] as int? ?? 200,
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
        osmId: m['osm_id'] as String?,
        source: StoreSource.fromString(m['source'] as String? ?? 'manual'),
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'type': type.value,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'opening_hours': openingHours,
        'notification_radius_m': notificationRadiusM,
        'is_favorite': isFavorite ? 1 : 0,
        'osm_id': osmId,
        'source': source.value,
        'created_at': createdAt,
      };

  // ── copyWith ───────────────────────────────────────────────────────────────

  Store copyWith({
    int? id,
    int? userId,
    String? name,
    StoreType? type,
    double? latitude,
    double? longitude,
    String? address,
    String? openingHours,
    int? notificationRadiusM,
    bool? isFavorite,
    String? osmId,
    StoreSource? source,
    String? createdAt,
  }) =>
      Store(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        type: type ?? this.type,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        address: address ?? this.address,
        openingHours: openingHours ?? this.openingHours,
        notificationRadiusM: notificationRadiusM ?? this.notificationRadiusM,
        isFavorite: isFavorite ?? this.isFavorite,
        osmId: osmId ?? this.osmId,
        source: source ?? this.source,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  String toString() =>
      'Store(id: $id, name: $name, type: ${type.value}, userId: $userId)';
}
