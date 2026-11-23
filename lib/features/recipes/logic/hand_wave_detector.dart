import 'dart:async';

enum HandGesture { next, previous }

/// Transforme les événements du capteur de proximité en gestes :
/// - un passage de la main (proche puis loin) -> étape suivante ;
/// - deux passages rapprochés -> étape précédente.
///
/// Après un premier passage on attend [doubleWaveWindow] : si un second
/// passage arrive, c'est un retour ; sinon c'est une avance. Une main laissée
/// plus de [maxHoldDuration] au-dessus du capteur (téléphone posé face contre
/// le plan de travail, par exemple) n'est pas un geste.
class HandWaveDetector {
  HandWaveDetector({
    required this.onGesture,
    this.doubleWaveWindow = const Duration(milliseconds: 800),
    this.maxHoldDuration = const Duration(milliseconds: 1500),
    this.cooldown = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final void Function(HandGesture gesture) onGesture;
  final Duration doubleWaveWindow;
  final Duration maxHoldDuration;

  /// Délai pendant lequel on ignore tout après un geste émis.
  final Duration cooldown;
  final DateTime Function() _clock;

  bool _near = false;
  DateTime? _nearSince;
  DateTime? _lastEmit;
  int _pendingWaves = 0;
  Timer? _timer;

  /// À appeler à chaque événement du capteur.
  void onProximity(bool near) {
    final now = _clock();
    if (near == _near) return;
    _near = near;
    if (near) {
      _nearSince = now;
      return;
    }
    final since = _nearSince;
    _nearSince = null;
    if (since == null || now.difference(since) > maxHoldDuration) return;
    if (_lastEmit != null && now.difference(_lastEmit!) < cooldown) return;

    _pendingWaves++;
    if (_pendingWaves >= 2) {
      _emit(HandGesture.previous);
      return;
    }
    _timer?.cancel();
    _timer = Timer(doubleWaveWindow, () => _emit(HandGesture.next));
  }

  void _emit(HandGesture g) {
    _timer?.cancel();
    _timer = null;
    _pendingWaves = 0;
    _lastEmit = _clock();
    onGesture(g);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
