/// Rapprochement entre la liste de courses et les lignes d'un ticket
/// (métier avancé n° 1).
///
/// Chaque couple (article, ligne) reçoit une similarité de libellé. Les
/// couples sont ensuite affectés du plus sûr au moins sûr, chaque article et
/// chaque ligne ne servant qu'une fois (affectation gloutonne). Les articles
/// rapprochés se cochent seuls ; les articles non cochés restés sans ligne
/// sont signalés comme oubliés.
library;

import 'text_similarity.dart';

class MatchCandidate {
  const MatchCandidate({required this.id, required this.label, this.productId, this.checked = false});

  final int id;
  final String label;
  final int? productId;
  final bool checked;
}

class LineCandidate {
  const LineCandidate({required this.index, required this.label, this.productId});

  final int index;
  final String label;
  final int? productId;
}

class ItemMatch {
  const ItemMatch({required this.itemId, required this.lineIndex, required this.score});

  final int itemId;
  final int lineIndex;

  /// 1 si le produit est le même, sinon la similarité des libellés.
  final double score;
}

class MatchResult {
  const MatchResult({required this.matches, required this.forgottenItemIds, required this.unplannedLineIndexes});

  final List<ItemMatch> matches;

  /// Articles de la liste non cochés et absents du ticket.
  final List<int> forgottenItemIds;

  /// Lignes du ticket qui ne correspondent à aucun article (achats hors liste).
  final List<int> unplannedLineIndexes;
}

const defaultMatchThreshold = 0.6;

double matchScore(MatchCandidate item, LineCandidate line) {
  if (item.productId != null && item.productId == line.productId) return 1;
  return labelSimilarity(item.label, line.label);
}

MatchResult matchReceipt(
  List<MatchCandidate> items,
  List<LineCandidate> lines, {
  double threshold = defaultMatchThreshold,
}) {
  final pairs = <ItemMatch>[];
  for (final item in items) {
    for (final line in lines) {
      final s = matchScore(item, line);
      if (s >= threshold) pairs.add(ItemMatch(itemId: item.id, lineIndex: line.index, score: s));
    }
  }
  // Du plus sûr au moins sûr ; à égalité, l'ordre de la liste puis du ticket.
  pairs.sort((a, b) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    final i = items.indexWhere((x) => x.id == a.itemId).compareTo(items.indexWhere((x) => x.id == b.itemId));
    return i != 0 ? i : a.lineIndex.compareTo(b.lineIndex);
  });

  final usedItems = <int>{};
  final usedLines = <int>{};
  final matches = <ItemMatch>[];
  for (final p in pairs) {
    if (usedItems.contains(p.itemId) || usedLines.contains(p.lineIndex)) continue;
    usedItems.add(p.itemId);
    usedLines.add(p.lineIndex);
    matches.add(p);
  }

  return MatchResult(
    matches: matches,
    forgottenItemIds: [
      for (final i in items)
        if (!i.checked && !usedItems.contains(i.id)) i.id,
    ],
    unplannedLineIndexes: [
      for (final l in lines)
        if (!usedLines.contains(l.index)) l.index,
    ],
  );
}
