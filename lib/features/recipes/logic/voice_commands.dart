import 'text_matching.dart';

sealed class VoiceCommand {
  const VoiceCommand();
}

class NextStepCommand extends VoiceCommand {
  const NextStepCommand();
}

class PreviousStepCommand extends VoiceCommand {
  const PreviousStepCommand();
}

class RepeatStepCommand extends VoiceCommand {
  const RepeatStepCommand();
}

class StartTimerCommand extends VoiceCommand {
  const StartTimerCommand(this.duration);
  final Duration duration;
}

class StopTimerCommand extends VoiceCommand {
  const StopTimerCommand();
}

class IngredientsCommand extends VoiceCommand {
  const IngredientsCommand();
}

const _numberWords = {
  'zero': 0, 'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5, 'six': 6, 'sept': 7,
  'huit': 8, 'neuf': 9, 'dix': 10, 'onze': 11, 'douze': 12, 'treize': 13, 'quatorze': 14,
  'quinze': 15, 'seize': 16, 'vingt': 20, 'trente': 30, 'quarante': 40, 'cinquante': 50,
  'soixante': 60, 'demi': 0, 'demie': 0,
};

/// Lit un nombre écrit en chiffres ou en lettres (« vingt cinq », « dix sept »).
/// Tous les mots doivent faire partie du nombre.
int? _readNumber(List<String> words) {
  if (words.isEmpty) return null;
  if (words.length == 1 && int.tryParse(words.first) != null) return int.parse(words.first);
  if (words.first == 'et' || words.last == 'et') return null;
  var total = 0;
  for (final w in words) {
    if (w == 'et') continue;
    final v = _numberWords[w];
    if (v == null || v == 0) return null;
    total += v;
  }
  return total;
}

Duration? _parseDuration(String text) {
  final words = text.split(' ');
  var total = Duration.zero;
  var found = false;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    Duration Function(int)? unit;
    if (w.startsWith('heure') || w == 'h') {
      unit = (n) => Duration(hours: n);
    } else if (w.startsWith('minute') || w == 'min' || w == 'mn') {
      unit = (n) => Duration(minutes: n);
    } else if (w.startsWith('seconde') || w == 's' || w == 'sec') {
      unit = (n) => Duration(seconds: n);
    }
    if (unit == null) continue;
    // Cherche le nombre juste avant l'unité (jusqu'à 3 mots : « vingt et un »).
    int? n;
    for (var back = 3; back >= 1; back--) {
      if (i - back < 0) continue;
      final v = _readNumber(words.sublist(i - back, i));
      if (v != null) {
        n = v;
        break;
      }
    }
    if (n == null && i > 0 && (words[i - 1] == 'une' || words[i - 1] == 'un')) n = 1;
    if (n == null) continue;
    total += unit(n);
    found = true;
    // « une heure et demie », « 5 minutes et demie »
    if (i + 2 < words.length && words[i + 1] == 'et' && words[i + 2].startsWith('demi')) {
      total += unit(1) ~/ 2;
    }
  }
  return found && total > Duration.zero ? total : null;
}

/// Reconnaît une commande dans la phrase dictée (insensible aux accents).
/// Renvoie null si rien n'est reconnu.
VoiceCommand? parseVoiceCommand(String spoken) {
  final t = normalize(spoken);
  if (t.isEmpty) return null;
  bool has(List<String> keys) => keys.any((k) => containsWord(t, k));

  if (has(['minuteur', 'minuterie', 'timer', 'chrono', 'chronometre'])) {
    if (has(['arrete', 'arreter', 'stop', 'stoppe', 'annule', 'annuler'])) return const StopTimerCommand();
    final d = _parseDuration(t);
    return d == null ? null : StartTimerCommand(d);
  }
  if (has(['precedent', 'precedente', 'retour', 'arriere', 'reviens', 'recule'])) {
    return const PreviousStepCommand();
  }
  if (has(['repete', 'repeter', 'relis', 'relire', 'encore', 'quoi', 'pardon'])) {
    return const RepeatStepCommand();
  }
  if (has(['suivant', 'suivante', 'apres', 'continue', 'ensuite', 'next', 'avance'])) {
    return const NextStepCommand();
  }
  if (has(['ingredient', 'ingredients'])) return const IngredientsCommand();
  return null;
}
