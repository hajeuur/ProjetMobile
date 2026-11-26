/// Suivi du ticket d'une image à l'autre pendant le scan en direct.
///
/// Une image seule se trompe souvent (reflet, flou de bougé). Le suivi
/// rapproche les lignes lues sur les images successives, garde pour chacune
/// la lecture la plus fréquente (vote), et ne la confirme qu'après l'avoir
/// vue sur plusieurs images. Quand plus rien ne change pendant quelques
/// images, le texte est « stable » : le scan peut se terminer.
library;

import 'dart:ui' show Rect;

import 'live_receipt_parser.dart';
import 'text_similarity.dart';

/// Une ligne du ticket suivie à travers les images.
class TrackedLine {
  TrackedLine._(this.id, LiveLine first) {
    _add(first);
  }

  final int id;

  final _labels = <String, int>{};
  final _prices = <double, int>{};
  final _quantities = <double, int>{};
  double _confidenceSum = 0;

  /// Nombre d'images où la ligne a été vue.
  int seen = 0;
  int lastSeenFrame = 0;

  /// Image à laquelle la ligne a été confirmée (null tant qu'elle ne l'est pas).
  int? confirmedAtFrame;

  bool get isConfirmed => confirmedAtFrame != null;

  String get label => _best(_labels);
  double get price => _best(_prices);
  double get quantity => _best(_quantities);

  /// Confiance : celle des lectures, renforcée quand les images concordent.
  double get confidence {
    final read = _confidenceSum / seen;
    // Part des images d'accord sur le prix retenu : des lectures qui varient
    // d'une image à l'autre rendent la ligne douteuse.
    final agreement = (_prices[price] ?? 0) / seen;
    final repeat = (seen / 4).clamp(0.0, 1.0);
    return (read * (0.2 + 0.8 * agreement) + (agreement == 1 ? 0.05 * repeat : 0)).clamp(0.0, 1.0);
  }

  bool get isDoubtful => confidence < LiveReceiptParser.doubtfulBelow;

  void _add(LiveLine l) {
    _labels[l.label] = (_labels[l.label] ?? 0) + 1;
    _prices[l.price] = (_prices[l.price] ?? 0) + 1;
    _quantities[l.quantity] = (_quantities[l.quantity] ?? 0) + 1;
    _confidenceSum += l.confidence;
    seen++;
  }

  static T _best<T>(Map<T, int> votes) {
    var best = votes.entries.first;
    for (final e in votes.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }

  /// Signature de ce qui est affiché : change si la lecture retenue change.
  String get _signature => '$id|$label|$price|$quantity';

  @override
  String toString() => '#$id $label $price${isConfirmed ? '' : ' ?'}';
}

/// Emplacement d'une ligne sur l'image courante, pour la surbrillance.
class LiveHighlight {
  const LiveHighlight({required this.id, required this.box, required this.doubtful, this.isTotal = false});
  final int id;
  final Rect box;
  final bool doubtful;
  final bool isTotal;
}

enum TotalCheck {
  /// Aucun total lu pour l'instant.
  missing,

  /// Somme des lignes = total (à 10 millimes près).
  valid,

  /// Écart entre la somme des lignes et le total.
  gap,
}

class LiveScanTracker {
  LiveScanTracker({this.confirmAfter = 2, this.stableAfter = 3, this.forgetAfter = 6});

  /// Images nécessaires pour confirmer une ligne.
  final int confirmAfter;

  /// Images consécutives sans changement pour que le texte soit stable.
  final int stableAfter;

  /// Une lecture vue une seule fois puis plus jamais pendant N images est
  /// oubliée (bruit, reflet).
  final int forgetAfter;

  final List<TrackedLine> _lines = [];
  final _totals = <double, int>{};
  double _totalConfidence = 0;
  int _totalSeen = 0;
  final _dates = <DateTime, int>{};
  final _headers = <String, int>{};
  List<String> _bestHeader = const [];

  int frame = 0;
  int _nextId = 1;
  int _unchanged = 0;
  String _lastSignature = '';

  /// Image la plus riche (pour « Texte lu » sur l'écran de validation).
  List<String> bestRows = const [];
  int _bestRowsLines = -1;

  /// Surbrillances de la dernière image.
  List<LiveHighlight> highlights = const [];

  /// Lignes confirmées, dans l'ordre du ticket.
  List<TrackedLine> get lines => [for (final l in _lines) if (l.isConfirmed) l];

  double? get total {
    if (_totalSeen < confirmAfter) return null;
    return TrackedLine._best(_totals);
  }

  /// Total le plus lu, même vu une seule fois (pour la validation).
  double? get bestTotal => _totals.isEmpty ? null : TrackedLine._best(_totals);

  double get totalConfidence => _totalSeen == 0 ? 0 : _totalConfidence / _totalSeen;

  DateTime? get date => _dates.isEmpty ? null : TrackedLine._best(_dates);
  List<String> get headerLines => _bestHeader;

  double get linesSum => _round(lines.fold(0.0, (s, l) => s + l.price));

  TotalCheck get totalCheck {
    final t = total;
    if (t == null) return TotalCheck.missing;
    return (t - linesSum).abs() < 0.011 ? TotalCheck.valid : TotalCheck.gap;
  }

  /// Écart total − somme des lignes (positif : il manque des lignes).
  double get gap => _round((total ?? linesSum) - linesSum);

  /// Plus rien ne change depuis [stableAfter] images.
  bool get isStable => lines.isNotEmpty && _unchanged >= stableAfter;

  /// Ajoute la lecture d'une image. Renvoie les lignes qui viennent d'être
  /// confirmées (pour l'animation).
  List<TrackedLine> add(LiveFrameReading reading, {List<String> rows = const []}) {
    frame++;
    final matched = <TrackedLine>{};
    final highlights = <LiveHighlight>[];
    final newlyConfirmed = <TrackedLine>[];
    TrackedLine? previous;
    // Nouvelles lignes en haut de l'image : placées avant la première ligne
    // déjà connue (le ticket a été remonté).
    final lead = <TrackedLine>[];

    for (final l in reading.lines) {
      var t = _match(l, matched);
      if (t == null) {
        t = TrackedLine._(_nextId++, l);
        if (previous == null || lead.contains(previous)) {
          lead.add(t);
        } else {
          _lines.insert(_lines.indexOf(previous) + 1, t);
        }
      } else {
        t._add(l);
        if (lead.isNotEmpty) {
          _lines.insertAll(_lines.indexOf(t), lead);
          lead.clear();
        }
      }
      t.lastSeenFrame = frame;
      matched.add(t);
      previous = t;
      if (!t.isConfirmed && t.seen >= confirmAfter) {
        t.confirmedAtFrame = frame;
        newlyConfirmed.add(t);
      }
      if (t.isConfirmed) highlights.add(LiveHighlight(id: t.id, box: l.box, doubtful: t.isDoubtful));
    }
    _lines.addAll(lead);

    // Bruit : vu une fois, puis plus jamais.
    _lines.removeWhere((t) => !t.isConfirmed && frame - t.lastSeenFrame >= forgetAfter);

    final rt = reading.total;
    if (rt != null) {
      _totals[rt.value] = (_totals[rt.value] ?? 0) + 1;
      _totalConfidence += rt.confidence;
      _totalSeen++;
      highlights.add(LiveHighlight(id: 0, box: rt.box, doubtful: false, isTotal: true));
    }
    if (reading.date != null) _dates[reading.date!] = (_dates[reading.date!] ?? 0) + 1;
    if (reading.headerLines.isNotEmpty) {
      final key = reading.headerLines.join('\n');
      final n = (_headers[key] ?? 0) + 1;
      _headers[key] = n;
      if (n >= (_headers[_bestHeader.join('\n')] ?? 0)) _bestHeader = reading.headerLines;
    }
    if (rows.isNotEmpty && reading.lines.length > _bestRowsLines) {
      _bestRowsLines = reading.lines.length;
      bestRows = rows;
    }
    this.highlights = highlights;

    // Stabilité : mêmes lignes et même total sur plusieurs images (une image
    // sans aucune ligne ne compte pas : le ticket est peut-être hors champ).
    final signature = [for (final l in lines) l._signature, 'T${total ?? ''}'].join(';');
    if (signature != _lastSignature) {
      _unchanged = 0;
      _lastSignature = signature;
    } else if (reading.lines.isNotEmpty) {
      _unchanged++;
    }
    return newlyConfirmed;
  }

  /// Ligne déjà suivie qui correspond à [l] (même libellé à quelques erreurs
  /// de lecture près, et même prix ou libellé quasi identique).
  TrackedLine? _match(LiveLine l, Set<TrackedLine> taken) {
    TrackedLine? best;
    var bestScore = 0.0;
    final key = normalize(l.label);
    for (final t in _lines) {
      if (taken.contains(t)) continue;
      final sim = textRatio(key, normalize(t.label));
      final samePrice = (t.price - l.price).abs() < 0.0005 || t._prices.containsKey(l.price);
      final ok = sim >= 0.9 || (sim >= 0.7 && samePrice);
      if (!ok) continue;
      final score = sim + (samePrice ? 0.5 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

/// Ressemblance de deux textes (0–1), tolérante aux erreurs de lecture d'un
/// ou deux caractères : 1 − distance d'édition / longueur.
double textRatio(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  final longest = a.length > b.length ? a.length : b.length;
  return 1 - prev[b.length] / longest;
}

/// Limite le traitement du flux caméra (~3 images par seconde) : une image
/// n'est lue que si la précédente est terminée et assez ancienne.
class FrameGate {
  FrameGate({this.minInterval = const Duration(milliseconds: 333)});
  final Duration minInterval;

  DateTime? _last;
  bool _busy = false;

  bool get busy => _busy;

  /// Vrai si l'image arrivée à [now] doit être traitée (elle réserve alors
  /// le créneau jusqu'à [done]).
  bool tryStart(DateTime now) {
    if (_busy) return false;
    if (_last != null && now.difference(_last!) < minInterval) return false;
    _busy = true;
    _last = now;
    return true;
  }

  void done() => _busy = false;
}

/// Luminosité moyenne (0–1) d'un plan de luminance (Y) échantillonné.
double meanLuma(List<int> bytes, {int step = 23}) {
  if (bytes.isEmpty) return 0;
  var sum = 0;
  var n = 0;
  for (var i = 0; i < bytes.length; i += step) {
    sum += bytes[i];
    n++;
  }
  return sum / n / 255;
}
