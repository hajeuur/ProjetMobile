/// Vibreur « battement de cœur » : un motif « tou-toum » dont le rythme suit
/// le remplissage du budget.
///
/// | Remplissage | Niveau | Rythme | Intensité |
/// |---|---|---|---|
/// | < 50 % | calme | aucun battement | — |
/// | 50 à 80 % | lent | 60 battements/min | douce |
/// | 80 à 100 % | rapide | 100 battements/min | moyenne |
/// | ≥ 100 % | affolé | 150 battements/min | forte |
///
/// Le motif suit le format Android `createWaveform` : durées alternées
/// pause / vibration (ms), avec une intensité 0–255 par segment (0 pour les
/// pauses). Les instants des « tou » et « toum » servent à animer le cœur
/// à l'écran en même temps que la vibration.
library;

enum HeartLevel {
  calm('Cœur calme', 0),
  slow('Battement lent', 60),
  fast('Battement rapide', 100),
  panic('Cœur affolé', 150);

  const HeartLevel(this.label, this.bpm);
  final String label;

  /// Battements par minute.
  final int bpm;

  /// Palier franchi : 0 (aucun), 1 (50 %), 2 (80 %), 3 (100 %).
  int get palier => index;

  static HeartLevel of(double ratio) => ratio >= 1
      ? panic
      : ratio >= 0.8
          ? fast
          : ratio >= 0.5
              ? slow
              : calm;
}

/// Une impulsion (« tou » ou « toum ») : début, durée, intensité.
class Pulse {
  const Pulse(this.start, this.length, this.intensity);
  final Duration start;
  final Duration length;
  final int intensity;
}

class HeartbeatPattern {
  const HeartbeatPattern({required this.level, required this.timings, required this.intensities, required this.pulses});

  final HeartLevel level;

  /// pause, vibration, pause, vibration… (ms).
  final List<int> timings;

  /// Une intensité par segment (0 pour les pauses).
  final List<int> intensities;

  /// Impulsions, pour synchroniser l'animation du cœur.
  final List<Pulse> pulses;

  bool get isEmpty => pulses.isEmpty;
  Duration get total => Duration(milliseconds: timings.fold(0, (s, t) => s + t));
  int get beats => pulses.length ~/ 2;
}

/// Paramètres de chaque rythme : (tou, pause entre tou et toum, toum, intensités).
const _shape = {
  HeartLevel.slow: (lub: 70, gap: 140, dub: 90, i1: 110, i2: 80),
  HeartLevel.fast: (lub: 60, gap: 100, dub: 80, i1: 180, i2: 140),
  HeartLevel.panic: (lub: 50, gap: 70, dub: 70, i1: 255, i2: 230),
};

/// Motif pour un remplissage [ratio] (dépensé / budget) sur [duration].
HeartbeatPattern heartbeatFor(double ratio, {Duration duration = const Duration(seconds: 5)}) =>
    heartbeatForLevel(HeartLevel.of(ratio), duration: duration);

HeartbeatPattern heartbeatForLevel(HeartLevel level, {Duration duration = const Duration(seconds: 5)}) {
  final s = _shape[level];
  if (s == null) return HeartbeatPattern(level: level, timings: const [], intensities: const [], pulses: const []);
  final period = 60000 ~/ level.bpm; // durée d'un battement
  final timings = <int>[];
  final intensities = <int>[];
  final pulses = <Pulse>[];
  var t = 0;
  var wait = 0; // pause avant le prochain « tou »
  // Le battement suivant doit se terminer dans la durée demandée.
  while (t + wait + s.lub + s.gap + s.dub <= duration.inMilliseconds) {
    // pause, tou, pause, toum
    timings.addAll([wait, s.lub, s.gap, s.dub]);
    intensities.addAll([0, s.i1, 0, s.i2]);
    final beatStart = t + wait;
    pulses.add(Pulse(Duration(milliseconds: beatStart), Duration(milliseconds: s.lub), s.i1));
    pulses.add(Pulse(Duration(milliseconds: beatStart + s.lub + s.gap), Duration(milliseconds: s.dub), s.i2));
    t = beatStart + s.lub + s.gap + s.dub;
    wait = period - (s.lub + s.gap + s.dub);
  }
  return HeartbeatPattern(level: level, timings: timings, intensities: intensities, pulses: pulses);
}

/// Gonflement du cœur à l'instant [t] (0 au repos, 1 au sommet d'un « tou »),
/// pour une animation synchronisée avec la vibration.
double heartPulseAt(HeartbeatPattern p, Duration t) {
  var v = 0.0;
  for (final pulse in p.pulses) {
    final d = (t - pulse.start).inMilliseconds;
    final len = pulse.length.inMilliseconds + 120; // le cœur dégonfle après la vibration
    if (d < 0 || d > len) continue;
    // Monte vite, redescend doucement.
    final x = d / len;
    final shape = x < 0.25 ? x / 0.25 : 1 - (x - 0.25) / 0.75;
    v = [v, shape * pulse.intensity / 255].reduce((a, b) => a > b ? a : b);
  }
  return v;
}
