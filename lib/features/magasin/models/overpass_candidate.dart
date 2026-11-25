import 'store.dart';

/// A store candidate returned by the Overpass (OpenStreetMap) API, before
/// being persisted as a [Store].
class OverpassCandidate {
  const OverpassCandidate({
    required this.osmId,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.openingHours,
  });

  final String osmId;
  final String name;
  final StoreType type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? openingHours;

  /// Convert to a [Store] ready for insertion (without an [id]).
  Store toStore({required int userId}) => Store(
        userId: userId,
        name: name,
        type: type,
        latitude: latitude,
        longitude: longitude,
        address: address,
        openingHours: openingHours,
        osmId: osmId,
        source: StoreSource.osm,
        createdAt: DateTime.now().toIso8601String(),
      );

  @override
  String toString() =>
      'OverpassCandidate(osmId: $osmId, name: $name, type: ${type.value})';
}
