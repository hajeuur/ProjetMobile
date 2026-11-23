import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/hand_wave_detector.dart';
import '../logic/voice_commands.dart';
import '../models/recipe.dart';
import '../services/cooking_devices.dart';
import '../services/cooking_settings.dart';

class CookingTimer {
  CookingTimer({required this.id, required this.label, required this.total, required this.endsAt});
  final int id;
  final String label;
  final Duration total;
  final DateTime endsAt;
  bool rang = false;

  Duration remaining(DateTime now) {
    final r = endsAt.difference(now);
    return r.isNegative ? Duration.zero : r;
  }
}

/// Mode cuisine sans les mains : étapes, geste de la main, voix, minuteurs.
class CookingViewModel extends ChangeNotifier {
  CookingViewModel({
    required this.title,
    required this.steps,
    required this.ingredients,
    required this.devices,
    required this.settingsStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String title;
  final List<RecipeStep> steps;

  /// Ingrédients déjà ajustés au nombre de portions.
  final List<RecipeIngredient> ingredients;
  final CookingDevices devices;
  final CookingSettingsStore? settingsStore;
  final DateTime Function() _clock;

  CookingSettings settings = const CookingSettings();
  int index = 0;
  bool proximityAvailable = false;
  bool speechAvailable = false;
  bool listening = false;
  String? lastHeard;

  /// Message bref affiché (geste détecté, commande non comprise…).
  String? feedback;
  final List<CookingTimer> timers = [];

  StreamSubscription<bool>? _proxSub;
  HandWaveDetector? _detector;
  Timer? _ticker;
  int _timerSeq = 0;
  bool _disposed = false;

  RecipeStep? get current => steps.isEmpty ? null : steps[index];
  bool get isFirst => index == 0;
  bool get isLast => index >= steps.length - 1;
  DateTime get now => _clock();

  Future<void> start() async {
    settings = await settingsStore?.load() ?? const CookingSettings();
    await devices.screen.keepOn(true);
    proximityAvailable = await devices.proximity.isAvailable();
    await _applyProximity();
    _notify();
    _readCurrent();
  }

  // ------------------------------------------------------------- Étapes

  void next() {
    if (isLast) {
      _say('C\'est la dernière étape. Bon appétit !');
      _setFeedback('Dernière étape');
      return;
    }
    index++;
    _notify();
    _readCurrent();
  }

  void previous() {
    if (isFirst) {
      _setFeedback('Première étape');
      _readCurrent();
      return;
    }
    index--;
    _notify();
    _readCurrent();
  }

  void repeat() => _readCurrent();

  void goTo(int i) {
    if (i < 0 || i >= steps.length) return;
    index = i;
    _notify();
    _readCurrent();
  }

  void _readCurrent() {
    final s = current;
    if (s == null) return;
    _say('Étape ${s.number}. ${s.text}');
  }

  void _say(String text) {
    if (settings.readAloud) devices.speaker.speak(text);
  }

  void readIngredients() {
    final list = ingredients.map((i) => i.display).join(', ');
    devices.speaker.speak('Ingrédients : $list');
  }

  // ------------------------------------------------------------- Geste

  Future<void> _applyProximity() async {
    await _proxSub?.cancel();
    _proxSub = null;
    _detector?.dispose();
    _detector = null;
    if (!settings.proximityEnabled || !proximityAvailable) return;
    final d = HandWaveDetector(onGesture: _onGesture, clock: _clock);
    _detector = d;
    _proxSub = devices.proximity.events.listen(d.onProximity, onError: (_) {});
  }

  void _onGesture(HandGesture g) {
    if (g == HandGesture.next) {
      _setFeedback('✋ Étape suivante');
      next();
    } else {
      _setFeedback('✋✋ Étape précédente');
      previous();
    }
  }

  /// Pour les tests et le bouton de démonstration.
  @visibleForTesting
  void simulateProximity(bool near) => _detector?.onProximity(near);

  // ------------------------------------------------------------- Voix

  Future<bool> ensureSpeech() async {
    if (speechAvailable) return true;
    speechAvailable = await devices.speech.initialize();
    _notify();
    return speechAvailable;
  }

  Future<void> listen() async {
    if (!settings.voiceEnabled || listening) return;
    if (!await ensureSpeech()) {
      _setFeedback('Reconnaissance vocale indisponible');
      return;
    }
    await devices.speaker.stop();
    listening = true;
    _notify();
    await devices.speech.listen(
      onFinal: handleSpoken,
      onDone: () {
        listening = false;
        _notify();
        if (settings.continuousListening && settings.voiceEnabled && !_disposed) {
          Future.delayed(const Duration(milliseconds: 600), listen);
        }
      },
    );
  }

  Future<void> stopListening() async {
    await devices.speech.stop();
    listening = false;
    _notify();
  }

  /// Exécute la commande reconnue dans [text].
  void handleSpoken(String text) {
    lastHeard = text;
    final cmd = parseVoiceCommand(text);
    switch (cmd) {
      case NextStepCommand():
        next();
      case PreviousStepCommand():
        previous();
      case RepeatStepCommand():
        repeat();
      case StartTimerCommand(:final duration):
        startTimer(duration);
      case StopTimerCommand():
        stopAllTimers();
      case IngredientsCommand():
        readIngredients();
      case null:
        _setFeedback('Commande non comprise : « $text »');
    }
    _notify();
  }

  // ---------------------------------------------------------- Minuteurs

  CookingTimer startTimer(Duration d, {String? label}) {
    final t = CookingTimer(
      id: ++_timerSeq,
      label: label ?? 'Étape ${current?.number ?? ''}'.trim(),
      total: d,
      endsAt: now.add(d),
    );
    timers.add(t);
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    devices.speaker.speak('Minuteur de ${formatDuration(d, spoken: true)} lancé.');
    _notify();
    return t;
  }

  void cancelTimer(CookingTimer t) {
    timers.remove(t);
    _stopTickerIfIdle();
    _notify();
  }

  void stopAllTimers() {
    timers.clear();
    _stopTickerIfIdle();
    devices.speaker.speak('Minuteurs arrêtés.');
    _notify();
  }

  void _stopTickerIfIdle() {
    if (timers.every((t) => t.rang)) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @visibleForTesting
  void tick() {
    final n = now;
    for (final t in timers) {
      if (!t.rang && t.remaining(n) == Duration.zero) {
        t.rang = true;
        devices.speaker.ring();
        _setFeedback('⏰ ${t.label} : minuteur terminé');
      }
    }
    _stopTickerIfIdle();
    _notify();
  }

  // ------------------------------------------------------------ Réglages

  Future<void> updateSettings(CookingSettings s) async {
    final proxChanged = s.proximityEnabled != settings.proximityEnabled;
    settings = s;
    if (!s.voiceEnabled && listening) await stopListening();
    if (!s.readAloud) await devices.speaker.stop();
    if (proxChanged) await _applyProximity();
    await settingsStore?.save(s);
    _notify();
  }

  // -------------------------------------------------------------- Divers

  Timer? _feedbackTimer;
  void _setFeedback(String text) {
    feedback = text;
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      feedback = null;
      _notify();
    });
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _proxSub?.cancel();
    _detector?.dispose();
    _ticker?.cancel();
    _feedbackTimer?.cancel();
    devices.speaker.stop();
    devices.speech.stop();
    devices.screen.keepOn(false);
    super.dispose();
  }
}

/// « 1:05:00 », « 4:30 » ; parlé : « 1 heure 5 minutes ».
String formatDuration(Duration d, {bool spoken = false}) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (spoken) {
    final parts = <String>[
      if (h > 0) '$h heure${h > 1 ? 's' : ''}',
      if (m > 0) '$m minute${m > 1 ? 's' : ''}',
      if (s > 0) '$s seconde${s > 1 ? 's' : ''}',
    ];
    return parts.isEmpty ? '0 seconde' : parts.join(' ');
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
