import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

/// Erreur lisible renvoyée à l'écran (réseau absent, refus du serveur…).
class OpenPricesException implements Exception {
  OpenPricesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Prix signalé par un utilisateur d'Open Prices.
class OpenPrice {
  const OpenPrice({
    required this.price,
    required this.currency,
    required this.date,
    this.locationName,
    this.productCode,
    this.productName,
    this.brands,
  });

  final double price;
  final String currency;
  final DateTime? date;
  final String? locationName;

  /// Produit du prix (champ `product_code`, et objet `product` imbriqué).
  final String? productCode;
  final String? productName;
  final String? brands;

  factory OpenPrice.fromJson(Map<String, dynamic> j) {
    final loc = j['location'];
    String? name;
    if (loc is Map) {
      name = (loc['osm_name'] ?? loc['osm_address_city']) as String?;
    }
    final product = j['product'];
    return OpenPrice(
      price: (j['price'] as num).toDouble(),
      currency: (j['currency'] as String?) ?? '?',
      date: DateTime.tryParse((j['date'] as String?) ?? ''),
      locationName: name,
      productCode: j['product_code'] as String?,
      productName: (product is Map ? product['product_name'] as String? : null) ?? j['product_name'] as String?,
      brands: product is Map ? product['brands'] as String? : null,
    );
  }
}

/// Liste `items` d'une réponse paginée d'Open Prices.
List<OpenPrice> parseOpenPrices(Object? json) {
  final items = json is Map ? json['items'] : null;
  if (items is! List) return const [];
  return [
    for (final i in items)
      if (i is Map<String, dynamic> && i['price'] is num) OpenPrice.fromJson(i),
  ];
}

/// Cache des réponses dans la table shopping_api_cache.
class ShoppingApiCache {
  ShoppingApiCache(this.db);
  final Database db;

  Future<(String body, DateTime fetchedAt)?> get(String key) async {
    final rows = await db.query('shopping_api_cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return (rows.first['body'] as String, DateTime.parse(rows.first['fetched_at'] as String));
  }

  Future<void> put(String key, String body, {DateTime? at}) => db.insert(
        'shopping_api_cache',
        {'key': key, 'body': body, 'fetched_at': (at ?? DateTime.now()).toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

/// Client de l'API Open Prices (projet d'Open Food Facts).
///
/// - lecture (sans compte) : prix signalés pour un code-barres ;
/// - partage facultatif : nécessite un jeton obtenu avec un compte Open Food
///   Facts ([login]) et l'identifiant OpenStreetMap du magasin (gestion 4).
///
/// Les réponses sont mises en cache : hors ligne, on renvoie la dernière
/// réponse connue, même ancienne.
class OpenPricesApi {
  OpenPricesApi({http.Client? client, this.cache, this.cacheTtl = const Duration(days: 1)})
      : _client = client ?? http.Client();

  static const base = 'https://prices.openfoodfacts.org/api/v1';
  static const _timeout = Duration(seconds: 10);
  static const _userAgent = 'PanierMalin/1.0 (application etudiante Flutter)';

  final http.Client _client;
  final ShoppingApiCache? cache;
  final Duration cacheTtl;

  Future<List<OpenPrice>> pricesFor(String barcode, {int size = 50}) async {
    final code = barcode.trim();
    if (!RegExp(r'^\d{8,14}$').hasMatch(code)) {
      throw OpenPricesException('Code-barres invalide : $barcode');
    }
    final url = '$base/prices?product_code=$code&order_by=-date&size=$size';
    final cached = await cache?.get(url);
    if (cached != null && DateTime.now().difference(cached.$2) < cacheTtl) {
      return _parse(cached.$1);
    }
    try {
      final res = await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent}).timeout(_timeout);
      if (res.statusCode != 200) {
        throw OpenPricesException('Open Prices a répondu ${res.statusCode}.');
      }
      final body = utf8.decode(res.bodyBytes);
      final prices = _parse(body);
      await cache?.put(url, body);
      return prices;
    } on OpenPricesException {
      if (cached != null) return _parse(cached.$1);
      rethrow;
    } catch (_) {
      if (cached != null) return _parse(cached.$1);
      throw OpenPricesException('Open Prices est injoignable (pas de réseau ?).');
    }
  }

  List<OpenPrice> _parse(String body) => parseOpenPrices(jsonDecode(body));

  /// Connexion avec un compte Open Food Facts ; renvoie le jeton d'accès.
  Future<String> login(String username, String password) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$base/auth'),
            headers: {'User-Agent': _userAgent},
            body: {'username': username, 'password': password},
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        throw OpenPricesException('Identifiants refusés par Open Food Facts.');
      }
      final token = (jsonDecode(res.body) as Map)['access_token'];
      if (token is! String) throw OpenPricesException('Réponse inattendue d\'Open Prices.');
      return token;
    } on OpenPricesException {
      rethrow;
    } catch (_) {
      throw OpenPricesException('Open Prices est injoignable (pas de réseau ?).');
    }
  }

  static String _day(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _detail(http.BaseResponse res, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return ' : ${j['detail']}';
      if (j is Map && j.isNotEmpty) return ' : ${j.entries.first.key} ${j.entries.first.value}';
    } catch (_) {}
    return '';
  }

  /// Envoie la preuve du prix (photo du ticket ou de l'étiquette) :
  /// `POST /api/v1/proofs/upload`, multipart (`file` obligatoire, `type`
  /// RECEIPT ou PRICE_TAG, `currency`, `date`, localisation facultative).
  /// Renvoie l'identifiant de la preuve (`id`).
  Future<int> uploadProof({
    required String token,
    required String filePath,
    required String type,
    required String currency,
    required DateTime date,
    int? locationOsmId,
    String? locationOsmType,
  }) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$base/proofs/upload'))
        ..headers.addAll({'User-Agent': _userAgent, 'Authorization': 'Bearer $token'})
        ..fields.addAll({
          'type': type,
          'currency': currency,
          'date': _day(date),
          if (locationOsmId != null && locationOsmType != null) ...{
            'location_osm_id': '$locationOsmId',
            'location_osm_type': locationOsmType,
          },
        })
        ..files.add(await http.MultipartFile.fromPath('file', filePath));
      final res = await _client.send(req).timeout(const Duration(seconds: 30));
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw OpenPricesException('Preuve refusée (${res.statusCode})${_detail(res, body)}');
      }
      final id = (jsonDecode(body) as Map)['id'];
      if (id is! int) throw OpenPricesException('Réponse inattendue d\'Open Prices.');
      return id;
    } on OpenPricesException {
      rethrow;
    } catch (_) {
      throw OpenPricesException('Open Prices est injoignable (pas de réseau ?).');
    }
  }

  /// Partage d'un prix payé : `POST /api/v1/prices` (jeton Bearer). Le
  /// serveur exige une preuve ([proofId], voir [uploadProof]) ; la
  /// localisation OpenStreetMap est facultative mais va par paire
  /// (`location_osm_id` + `location_osm_type` : NODE, WAY ou RELATION).
  Future<void> sharePrice({
    required String token,
    required String barcode,
    required double price,
    required String currency,
    required DateTime date,
    required int proofId,
    int? locationOsmId,
    String? locationOsmType,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$base/prices'),
            headers: {
              'User-Agent': _userAgent,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'product_code': barcode,
              'price': double.parse(price.toStringAsFixed(3)),
              'currency': currency,
              'date': _day(date),
              'proof_id': proofId,
              if (locationOsmId != null && locationOsmType != null) ...{
                'location_osm_id': locationOsmId,
                'location_osm_type': locationOsmType,
              },
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw OpenPricesException('Partage refusé (${res.statusCode})${_detail(res, utf8.decode(res.bodyBytes))}');
      }
    } on OpenPricesException {
      rethrow;
    } catch (_) {
      throw OpenPricesException('Open Prices est injoignable (pas de réseau ?).');
    }
  }
}

/// Comparaison du prix payé avec les prix de la communauté.
class PriceComparison {
  const PriceComparison({
    required this.paid,
    required this.currency,
    required this.sameCurrency,
    required this.allPrices,
  });

  final double paid;
  final String currency;

  /// Prix signalés dans la même devise que le prix payé.
  final List<OpenPrice> sameCurrency;
  final List<OpenPrice> allPrices;

  bool get hasData => sameCurrency.isNotEmpty;

  double? get median {
    if (sameCurrency.isEmpty) return null;
    final v = sameCurrency.map((p) => p.price).toList()..sort();
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
  }

  /// Prix moyen signalé par les autres utilisateurs.
  double? get mean =>
      sameCurrency.isEmpty ? null : sameCurrency.fold<double>(0, (s, p) => s + p.price) / sameCurrency.length;

  double? get min => sameCurrency.isEmpty ? null : sameCurrency.map((p) => p.price).reduce((a, b) => a < b ? a : b);

  /// Écart du prix payé par rapport au prix moyen (0,12 = 12 % plus cher).
  double? get difference {
    final m = mean;
    return (m == null || m == 0) ? null : (paid - m) / m;
  }

  /// Devises présentes quand aucune ne correspond (ex. produit importé, prix en EUR).
  Set<String> get otherCurrencies => allPrices.map((p) => p.currency).toSet()..remove(currency);
}

PriceComparison comparePrices(double paid, String currency, List<OpenPrice> prices) => PriceComparison(
      paid: paid,
      currency: currency,
      sameCurrency: prices.where((p) => p.currency.toUpperCase() == currency.toUpperCase()).toList(),
      allPrices: prices,
    );
