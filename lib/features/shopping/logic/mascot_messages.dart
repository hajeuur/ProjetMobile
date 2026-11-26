/// Mascotte « Malin » : humeur selon le budget, et banques de messages
/// (plusieurs variantes par situation, ton bienveillant, jamais culpabilisant).
library;

import 'dart:math';

import 'budget_forecast.dart';

enum MascotMood {
  /// Moins de 50 % du budget.
  happy('content'),

  /// 50 à 80 %.
  calm('serein'),

  /// 80 à 100 %.
  worried('inquiet'),

  /// Budget dépassé.
  panicked('paniqué'),

  /// Budget respecté (fin de mois, badge, course sans oubli).
  proud('fier');

  const MascotMood(this.label);
  final String label;
}

/// Humeur selon l'état du budget. Fier quand le mois se termine (3 derniers
/// jours ou mois passé) dans le budget.
MascotMood moodFor(BudgetSnapshot s) {
  if (s.budget == null) return MascotMood.happy;
  if (s.level == BudgetLevel.exceeded) return MascotMood.panicked;
  if (s.daysLeft <= 3 && s.level != BudgetLevel.exceeded && !s.forecastOverrun) return MascotMood.proud;
  if (s.level == BudgetLevel.threshold) return MascotMood.worried;
  if (s.ratio >= 0.5) return MascotMood.calm;
  return MascotMood.happy;
}

/// Ce qui s'est passé avec un ticket (la mascotte réagit au plus marquant).
enum MascotEvent {
  budgetExceeded,
  threshold,
  shrinkflation,
  priceIncrease,
  forgotten,
  badge,
  perfectTrip,
}

/// Humeur associée à un événement.
MascotMood moodForEvent(MascotEvent e) => switch (e) {
      MascotEvent.budgetExceeded => MascotMood.panicked,
      MascotEvent.threshold || MascotEvent.shrinkflation || MascotEvent.priceIncrease => MascotMood.worried,
      MascotEvent.forgotten => MascotMood.calm,
      MascotEvent.badge || MascotEvent.perfectTrip => MascotMood.proud,
    };

/// Mots interdits : la mascotte ne culpabilise jamais.
const mascotForbiddenWords = ['honte', 'nul', 'coupable', 'gaspill', 'irresponsable', 'faute', 'mauvais', 'idiot'];

class MascotMessages {
  MascotMessages({Random? random}) : _random = random ?? Random();
  final Random _random;

  String _pick(List<String> pool) => pool[_random.nextInt(pool.length)];

  /// Commentaire d'un ticket : « 57 DT chez Monoprix… mon portefeuille a eu chaud ! »
  String receipt({required double total, String? store}) {
    final t = shortDt(total);
    final at = store == null ? '' : ' chez $store';
    final pool = total < 20
        ? receiptSmall
        : total < 50
            ? receiptMedium
            : receiptBig;
    return _pick(pool).replaceAll('{t}', t).replaceAll('{at}', at);
  }

  /// Réaction à un événement ; [name] : produit concerné, [pct] : pourcentage.
  String event(MascotEvent e, {String? name, int? pct}) => _pick(eventPools[e]!)
      .replaceAll('{name}', name ?? 'un produit')
      .replaceAll('{pct}', pct == null ? '' : '$pct %');

  /// Bulle d'accueil (écran Courses, Budget) selon l'humeur.
  String greeting(MascotMood mood, {required int percent, double? perDay}) => _pick(greetingPools[mood]!)
      .replaceAll('{pct}', '$percent %')
      .replaceAll('{jour}', perDay == null ? '' : shortDt(perDay));

  // ------------------------------------------------------------ Banques

  static const receiptSmall = [
    '{t}{at}, léger comme une plume !',
    'Petit ticket de {t}{at} : je valide avec le sourire.',
    '{t}{at} ? Mon portefeuille n\'a même pas senti passer.',
  ];

  static const receiptMedium = [
    '{t}{at}, correct ! On garde le cap.',
    '{t}{at} : ni trop, ni trop peu. Bien joué.',
    'Va pour {t}{at}. Je range ça dans le carnet.',
  ];

  static const receiptBig = [
    '{t}{at}… mon portefeuille a eu chaud !',
    '{t}{at} d\'un coup ? J\'ai dû m\'asseoir, mais ça va aller.',
    'Gros panier de {t}{at} ! Le frigo te dit merci.',
  ];

  static const eventPools = <MascotEvent, List<String>>{
    MascotEvent.budgetExceeded: [
      'Le budget est dépassé… pas de panique, on respire et on lève le pied jusqu\'à la fin du mois.',
      'Oups, on a franchi la ligne ! Le mois prochain, on prendra notre revanche.',
      'Budget dépassé : je transpire un peu, mais on va s\'en sortir ensemble.',
    ],
    MascotEvent.threshold: [
      'On arrive au seuil d\'alerte : encore quelques jours, on choisit bien ses achats.',
      'Seuil franchi ! Je garde un œil sur le porte-monnaie, toi sur la liste ?',
      'Attention, zone orange : on passe en mode malin.',
    ],
    MascotEvent.shrinkflation: [
      '{name} a rétréci au lavage : même prix, moins de produit. On compare ?',
      'J\'ai remarqué que {name} avait maigri… mais pas son prix !',
    ],
    MascotEvent.priceIncrease: [
      '{name} a pris {pct}. On regarde ailleurs la prochaine fois ?',
      '{name} augmente de {pct} : un petit tour au comparateur ?',
    ],
    MascotEvent.forgotten: [
      'Tu as oublié {name} ? Ça arrive aux meilleurs, je le garde pour la prochaine liste.',
      '{name} est resté en rayon. Pas grave, on le note pour la prochaine fois !',
    ],
    MascotEvent.badge: [
      'Nouveau badge ! Je suis fier de toi.',
      'Un badge de plus : on fait une sacrée équipe !',
    ],
    MascotEvent.perfectTrip: [
      'Zéro oubli, liste parfaite : je suis fier de toi !',
      'Tout coché, rien oublié. Chapeau !',
    ],
  };

  static const greetingPools = <MascotMood, List<String>>{
    MascotMood.happy: [
      'Tout roule : {pct} du budget. On garde ce rythme ?',
      'Seulement {pct} du budget utilisé, je suis aux anges !',
    ],
    MascotMood.calm: [
      '{pct} du budget, tranquille. On reste attentifs.',
      'Budget à {pct} : on avance sereinement.',
    ],
    MascotMood.worried: [
      'Déjà {pct} du budget… on vise {jour} par jour ?',
      '{pct} du budget : je croise les doigts, on fait attention ensemble.',
    ],
    MascotMood.panicked: [
      'Budget dépassé ! On respire : chaque petit achat évité compte.',
      'Ça déborde un peu… pas grave, on se rattrape le mois prochain.',
    ],
    MascotMood.proud: [
      'Le mois se termine dans le budget : je suis fier de toi !',
      'Budget respecté, bravo ! On recommence le mois prochain ?',
    ],
  };

  /// Toutes les phrases (pour vérifier le ton dans les tests).
  static Iterable<String> get all => [
        ...receiptSmall,
        ...receiptMedium,
        ...receiptBig,
        for (final p in eventPools.values) ...p,
        for (final p in greetingPools.values) ...p,
      ];
}

/// Événement le plus marquant d'un ticket (du plus au moins important).
MascotEvent? mainEvent({
  required bool budgetExceeded,
  required bool threshold,
  required bool shrinkflation,
  required bool priceIncrease,
  required bool forgotten,
  required bool badge,
  required bool perfectTrip,
}) {
  if (budgetExceeded) return MascotEvent.budgetExceeded;
  if (threshold) return MascotEvent.threshold;
  if (shrinkflation) return MascotEvent.shrinkflation;
  if (priceIncrease) return MascotEvent.priceIncrease;
  if (badge) return MascotEvent.badge;
  if (perfectTrip) return MascotEvent.perfectTrip;
  if (forgotten) return MascotEvent.forgotten;
  return null;
}
