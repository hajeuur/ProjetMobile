/// Reconstruction des lignes d'un ticket à partir des fragments de texte
/// détectés par la reconnaissance de caractères.
///
/// ML Kit renvoie souvent le libellé (à gauche) et le prix (à droite) dans des
/// blocs différents. On regroupe les fragments dont les centres verticaux sont
/// proches, puis on les lit de gauche à droite.
library;

class OcrFragment {
  const OcrFragment(
    this.text, {
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Confiance de la reconnaissance (0–1), si fournie.
  final double? confidence;

  double get centerY => (top + bottom) / 2;
  double get height => (bottom - top).abs();
}

/// Une rangée du ticket : ses fragments lus de gauche à droite, et le
/// rectangle qui les englobe.
class OcrRow {
  const OcrRow(this.text, {required this.left, required this.top, required this.right, required this.bottom, this.confidence});

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Confiance la plus basse des fragments (le maillon faible).
  final double? confidence;
}

/// Regroupe les fragments en lignes de texte, de haut en bas.
List<String> rowsFromFragments(List<OcrFragment> fragments) => [for (final r in groupRows(fragments)) r.text];

/// Comme [rowsFromFragments], avec la position de chaque rangée.
List<OcrRow> groupRows(List<OcrFragment> fragments) {
  final frags = fragments.where((f) => f.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrFragment>>[];
  final centers = <double>[];
  for (final f in frags) {
    var placed = false;
    for (var i = rows.length - 1; i >= 0 && i >= rows.length - 3; i--) {
      final rowHeight = rows[i].map((r) => r.height).reduce((a, b) => a + b) / rows[i].length;
      final tolerance = 0.5 * (rowHeight < f.height ? rowHeight : f.height);
      if ((centers[i] - f.centerY).abs() <= tolerance) {
        rows[i].add(f);
        centers[i] = rows[i].map((r) => r.centerY).reduce((a, b) => a + b) / rows[i].length;
        placed = true;
        break;
      }
    }
    if (!placed) {
      rows.add([f]);
      centers.add(f.centerY);
    }
  }
  return [
    for (final r in rows)
      () {
        r.sort((a, b) => a.left.compareTo(b.left));
        final conf = [for (final f in r) if (f.confidence != null) f.confidence!];
        return OcrRow(
          r.map((f) => f.text.trim()).join('  '),
          left: r.map((f) => f.left).reduce((a, b) => a < b ? a : b),
          top: r.map((f) => f.top).reduce((a, b) => a < b ? a : b),
          right: r.map((f) => f.right).reduce((a, b) => a > b ? a : b),
          bottom: r.map((f) => f.bottom).reduce((a, b) => a > b ? a : b),
          confidence: conf.isEmpty ? null : conf.reduce((a, b) => a < b ? a : b),
        );
      }(),
  ];
}
