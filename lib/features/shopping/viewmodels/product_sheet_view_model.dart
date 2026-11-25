import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/product_scan_service.dart';

/// Fiche produit : chargement, resynchronisation après une consultation
/// hors ligne, liste, surveillance.
class ProductSheetViewModel extends ChangeNotifier {
  ProductSheetViewModel(this.service, this.code, {this.retryEvery = const Duration(seconds: 20)});

  final ProductScanService service;
  final String code;

  /// Hors ligne : nouvel essai régulier tant que la fiche est ouverte.
  final Duration retryEvery;

  ProductSheet? sheet;
  bool loading = false;
  String? error;

  /// Vient d'être resynchronisée (données à jour après une période hors ligne).
  bool resynced = false;
  bool canContribute = false;
  Timer? _retry;
  bool _disposed = false;

  bool get needsResync => sheet != null && (sheet!.offline || sheet!.networkError != null);

  Future<void> load({bool silent = false}) async {
    final wasOffline = needsResync;
    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      sheet = await service.lookup(code);
      final s = await service.shopping.settings();
      canContribute = s.sharePrices;
      resynced = wasOffline && !needsResync;
    } catch (e) {
      if (!silent) error = '$e';
    } finally {
      loading = false;
      _notify();
    }
    _retry?.cancel();
    if (needsResync && !_disposed) {
      _retry = Timer(retryEvery, () => load(silent: true));
    }
  }

  Future<String> addToList(String label) => service.addToList(label);

  Future<bool> toggleWatch() async {
    final now = await service.toggleWatch(sheet!);
    await load(silent: true);
    return now;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}
