import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'open_prices_api.dart' show ShoppingApiCache;

/// Réponse JSON, fraîche ou tirée du cache.
class CachedJson {
  const CachedJson({required this.json, required this.statusCode, required this.fetchedAt, this.offline = false});

  final Object? json;
  final int statusCode;
  final DateTime fetchedAt;

  /// Le réseau a échoué : c'est la dernière réponse connue (« données hors ligne »).
  final bool offline;
}

/// Pas de réseau et rien en cache.
class ApiUnreachable implements Exception {
  const ApiUnreachable(this.service);
  final String service;
  @override
  String toString() => '$service est injoignable (pas de réseau ?).';
}

/// Réponse HTTP inattendue (5xx, 429…).
class ApiHttpError implements Exception {
  const ApiHttpError(this.service, this.statusCode);
  final String service;
  final int statusCode;
  @override
  String toString() => statusCode == 429 || statusCode == 503
      ? '$service limite le nombre de requêtes : réessayez dans une minute.'
      : '$service a répondu $statusCode.';
}

/// Client HTTP des API Open Food Facts / Open Prices : délai d'attente,
/// User-Agent identifiant l'application (demandé par Open Food Facts), cache
/// local des réponses (table shopping_api_cache) et repli sur le cache hors
/// ligne.
class CachedJsonClient {
  CachedJsonClient({
    http.Client? client,
    this.cache,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// Forme demandée par Open Food Facts : NomApp/Version (contact). Nom
  /// générique, sans donnée personnelle.
  static const userAgent = 'PanierMalin/1.0 (application etudiante Flutter)';

  final http.Client _client;
  final ShoppingApiCache? cache;
  final Duration timeout;
  final DateTime Function() _clock;

  http.Client get raw => _client;

  /// GET JSON. Une réponse en cache plus récente que [maxAge] est servie
  /// sans réseau. Les réponses 200 et 404 sont mises en cache (un produit
  /// inconnu reste inconnu hors ligne).
  Future<CachedJson> get(Uri url, {required String service, Duration maxAge = const Duration(hours: 6)}) async {
    final key = url.toString();
    final cached = await cache?.get(key);
    if (cached != null && _clock().difference(cached.$2) < maxAge) {
      return _decode(cached.$1, cached.$2, offline: false);
    }
    http.Response res;
    try {
      res = await _client.get(url, headers: {'User-Agent': userAgent, 'Accept': 'application/json'}).timeout(timeout);
    } catch (_) {
      // Pas de réseau, délai dépassé : dernière réponse connue.
      if (cached != null) return _decode(cached.$1, cached.$2, offline: true);
      throw ApiUnreachable(service);
    }
    if (res.statusCode == 200 || res.statusCode == 404) {
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      final wrapped = jsonEncode({'status': res.statusCode, 'body': body});
      await cache?.put(key, wrapped, at: _clock());
      return CachedJson(json: _tryJson(body), statusCode: res.statusCode, fetchedAt: _clock());
    }
    if (cached != null) return _decode(cached.$1, cached.$2, offline: true);
    throw ApiHttpError(service, res.statusCode);
  }

  CachedJson _decode(String stored, DateTime at, {required bool offline}) {
    final w = _tryJson(stored);
    if (w is Map && w['status'] is int && w['body'] is String) {
      return CachedJson(json: _tryJson(w['body'] as String), statusCode: w['status'] as int, fetchedAt: at, offline: offline);
    }
    // Ancienne entrée (corps brut) : considérée comme une réponse 200.
    return CachedJson(json: w, statusCode: 200, fetchedAt: at, offline: offline);
  }

  static Object? _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
