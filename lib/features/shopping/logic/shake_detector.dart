/// Détection d'une secousse à partir de l'accéléromètre.
///
/// L'accéléromètre mesure aussi la pesanteur : immobile, la norme du vecteur
/// (x, y, z) vaut environ 9,81 m/s², soit 1 g. On calcule cette norme en g ;
/// au-delà de [thresholdG] (2,7 g par défaut, un geste franc), c'est une
/// secousse. Un délai anti-rebond ([debounce], 800 ms) évite qu'un même
/// geste, qui produit plusieurs pics, déclenche plusieurs annulations.
library;

import 'dart:math' as math;

class ShakeDetector {
  ShakeDetector({this.thresholdG = 2.7, this.debounce = const Duration(milliseconds: 800)});

  static const gravity = 9.80665;

  final double thresholdG;
  final Duration debounce;
  DateTime? _last;

  /// Intensité d'une mesure, en g (1 = téléphone immobile).
  static double gForce(double x, double y, double z) => math.sqrt(x * x + y * y + z * z) / gravity;

  /// Traite une mesure ; renvoie vrai si elle déclenche une secousse.
  bool add(double x, double y, double z, DateTime at) {
    if (gForce(x, y, z) < thresholdG) return false;
    final last = _last;
    if (last != null && at.difference(last) < debounce) return false;
    _last = at;
    return true;
  }

  void reset() => _last = null;
}
