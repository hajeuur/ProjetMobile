import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/recipes/models/recipe.dart';
import 'package:panier_malin/features/recipes/services/cooking_devices.dart';
import 'package:panier_malin/features/recipes/viewmodels/cooking_view_model.dart';

class FakeProximity implements ProximitySource {
  final controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get events => controller.stream;
  @override
  Future<bool> isAvailable() async => true;
}

class FakeSpeech implements SpeechInput {
  @override
  Future<bool> initialize() async => true;
  @override
  bool get isListening => false;
  @override
  Future<void> listen({required void Function(String) onFinal, required VoidCallback onDone}) async {}
  @override
  Future<void> stop() async {}
}

class FakeSpeaker implements Speaker {
  final said = <String>[];
  int rings = 0;
  @override
  Future<void> ring() async => rings++;
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> stop() async {}
}

class FakeScreen implements ScreenKeeper {
  bool on = false;
  @override
  Future<void> keepOn(bool v) async => on = v;
}

void main() {
  const steps = [
    RecipeStep(number: 1, text: 'Couper'),
    RecipeStep(number: 2, text: 'Cuire', durationMin: 10),
    RecipeStep(number: 3, text: 'Servir'),
  ];

  test('geste de la main, voix, minuteur et écran allumé', () {
    fakeAsync((fa) {
      final prox = FakeProximity();
      final speaker = FakeSpeaker();
      final screen = FakeScreen();
      final vm = CookingViewModel(
        title: 'Test',
        steps: steps,
        ingredients: const [],
        devices: CookingDevices(proximity: prox, speech: FakeSpeech(), speaker: speaker, screen: screen),
        settingsStore: null,
        clock: () => fa.getClock(DateTime(2026, 11, 23)).now(),
      );
      vm.start();
      fa.flushMicrotasks();
      expect(screen.on, isTrue);
      expect(speaker.said.last, contains('Étape 1'));

      // Un passage de main -> étape suivante.
      prox.controller.add(true);
      fa.elapse(const Duration(milliseconds: 200));
      prox.controller.add(false);
      fa.elapse(const Duration(seconds: 1));
      expect(vm.index, 1);
      expect(speaker.said.last, contains('Cuire'));

      // Commande vocale.
      vm.handleSpoken('précédent');
      expect(vm.index, 0);
      vm.handleSpoken('suivant');
      vm.handleSpoken('minuteur 2 minutes');
      expect(vm.timers.single.total, const Duration(minutes: 2));

      fa.elapse(const Duration(minutes: 2, seconds: 1));
      expect(vm.timers.single.rang, isTrue);
      expect(speaker.rings, 1);

      vm.dispose();
      fa.flushMicrotasks();
      expect(screen.on, isFalse);
      fa.flushTimers();
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(minutes: 4, seconds: 30)), '04:30');
    expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1:05:00');
    expect(formatDuration(const Duration(minutes: 10), spoken: true), '10 minutes');
  });
}
