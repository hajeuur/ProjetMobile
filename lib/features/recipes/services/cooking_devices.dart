import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Capteurs et haut-parleur du mode cuisine, derrière des interfaces pour
/// pouvoir tester la logique sans téléphone.

abstract interface class ProximitySource {
  Future<bool> isAvailable();

  /// true quand un objet (la main) est proche du capteur.
  Stream<bool> get events;
}

abstract interface class SpeechInput {
  Future<bool> initialize();
  bool get isListening;

  /// Écoute une phrase ; [onFinal] reçoit le texte reconnu.
  Future<void> listen({required void Function(String text) onFinal, required VoidCallback onDone});
  Future<void> stop();
}

abstract interface class Speaker {
  Future<void> speak(String text);
  Future<void> stop();

  /// Sonnerie de fin de minuteur.
  Future<void> ring();
}

abstract interface class ScreenKeeper {
  Future<void> keepOn(bool on);
}

// ---------------------------------------------------------------- Réel

class DeviceProximitySource implements ProximitySource {
  @override
  Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await ProximitySensor.isProximitySensorAvailable();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<bool> get events => ProximitySensor.events.map((v) => v > 0);
}

class DeviceSpeechInput implements SpeechInput {
  final SpeechToText _stt = SpeechToText();
  String? _localeId;
  VoidCallback? _onDone;

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<bool> initialize() async {
    try {
      final ok = await _stt.initialize(
        onStatus: (s) {
          if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) {
            final cb = _onDone;
            _onDone = null;
            cb?.call();
          }
        },
        onError: (SpeechRecognitionError e) {
          final cb = _onDone;
          _onDone = null;
          cb?.call();
        },
      );
      if (!ok) return false;
      final locales = await _stt.locales();
      _localeId = locales
              .where((l) => l.localeId.toLowerCase().startsWith('fr'))
              .map((l) => l.localeId)
              .firstOrNull ??
          (await _stt.systemLocale())?.localeId;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({required void Function(String text) onFinal, required VoidCallback onDone}) async {
    _onDone = onDone;
    await _stt.listen(
      onResult: (r) {
        if (r.finalResult) onFinal(r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        partialResults: false,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

class DeviceSpeaker implements Speaker {
  DeviceSpeaker() {
    _ready = _init();
  }

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready;

  Future<void> _init() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.45);
    } catch (_) {}
  }

  @override
  Future<void> speak(String text) async {
    await _ready;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> ring() async {
    for (var k = 0; k < 3; k++) {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    await speak('Le minuteur est terminé.');
  }
}

class DeviceScreenKeeper implements ScreenKeeper {
  @override
  Future<void> keepOn(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }
}

/// Regroupe le matériel du mode cuisine (injecté par Provider).
class CookingDevices {
  const CookingDevices({required this.proximity, required this.speech, required this.speaker, required this.screen});

  factory CookingDevices.device() => CookingDevices(
        proximity: DeviceProximitySource(),
        speech: DeviceSpeechInput(),
        speaker: DeviceSpeaker(),
        screen: DeviceScreenKeeper(),
      );

  final ProximitySource proximity;
  final SpeechInput speech;
  final Speaker speaker;
  final ScreenKeeper screen;
}
