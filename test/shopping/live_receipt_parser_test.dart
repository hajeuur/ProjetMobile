import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/live_receipt_parser.dart';
import 'package:panier_malin/features/shopping/logic/live_scan_tracker.dart';
import 'package:panier_malin/features/shopping/logic/ocr_rows.dart';

const parser = LiveReceiptParser();

List<LiveOcrRow> rows(List<String> texts, {double? confidence}) => [
      for (var i = 0; i < texts.length; i++)
        LiveOcrRow(texts[i], box: Rect.fromLTWH(0.1, 0.1 + i * 0.05, 0.8, 0.04), confidence: confidence),
    ];

LiveFrameReading read(List<String> texts, {double? confidence}) => parser.parse(rows(texts, confidence: confidence));

void main() {
  group('Montants tunisiens', () {
    test('virgule ou point, 3 décimales, devise avant/après, collée ou non', () {
      for (final s in ['1,350', '1.350', '1,350 DT', '1,350DT', 'DT 1,350', '1.350 TND', '1,350 D']) {
        final a = LiveReceiptParser.parseAmount(s);
        expect(a?.value, 1.35, reason: s);
        expect(a?.decimals, 3, reason: s);
        expect(a?.corrected, isFalse, reason: s);
      }
    });

    test('milliers séparés par une espace, deux décimales', () {
      expect(LiveReceiptParser.parseAmount('1 250,000')?.value, 1250);
      expect(LiveReceiptParser.parseAmount('12,50')?.decimals, 2);
    });

    test('lettres confondues avec des chiffres : corrigées mais signalées', () {
      final a = LiveReceiptParser.parseAmount('1,3S0')!;
      expect(a.value, 1.35);
      expect(a.corrected, isTrue);
      expect(LiveReceiptParser.parseAmount('O,800')?.value, 0.8);
      expect(LiveReceiptParser.parseAmount('B,OOO'), isNull, reason: 'trop de lettres');
      expect(LiveReceiptParser.parseAmount('1,5L'), isNull, reason: 'contenance, pas un prix');
    });

    test('pas un montant', () {
      expect(LiveReceiptParser.parseAmount('LAIT'), isNull);
      expect(LiveReceiptParser.parseAmount('1350'), isNull, reason: 'sans décimales');
      expect(LiveReceiptParser.parseAmount('SOLDES'), isNull);
    });
  });

  group('Lignes et total d\'une image', () {
    test('ticket complet : en-tête, lignes, quantité, remise, total TTC, paiement ignoré', () {
      final r = read([
        'CARREFOUR MARKET',
        'LA MARSA',
        '12/11/2026 10:42',
        'LAIT DELICE 1L        1,350',
        'PAIN BAGUETTE         0,200',
        'YAOURT VITALAIT 4 x 0,600  2,400',
        'EAU SAFIA 1,5L',
        '2 x 0,650             1,300',
        'REMISE FIDELITE       -0,300',
        'TOTAL TTC             4,950 DT',
        'ESPECES               10,000',
        'RENDU                 5,050',
      ]);
      expect(r.lines.map((l) => l.label), ['LAIT DELICE 1L', 'PAIN BAGUETTE', 'YAOURT VITALAIT', 'EAU SAFIA 1,5L', 'REMISE FIDELITE']);
      expect(r.lines.map((l) => l.price), [1.35, 0.2, 2.4, 1.3, -0.3]);
      expect(r.lines[2].quantity, 4);
      expect(r.lines[3].quantity, 2);
      expect(r.total?.value, 4.95);
      expect((r.total!.value - r.linesSum).abs() < 0.001, isTrue, reason: 'somme = total');
      expect(r.headerLines, ['CARREFOUR MARKET', 'LA MARSA']);
      expect(r.date, DateTime(2026, 11, 12));
    });

    test('mots du total : TOTAL, TTC, À PAYER ; « net à payer » l\'emporte ; sous-total et TVA ignorés', () {
      expect(read(['LAIT 1,350', 'TTC 1,350']).total?.value, 1.35);
      expect(read(['LAIT 1,350', 'À PAYER : 1,350 DT']).total?.value, 1.35);
      final r = read(['LAIT 1,350', 'SOUS TOTAL 1,350', 'TVA 7% 0,088', 'TOTAL 1,350', 'NET A PAYER 1,000']);
      expect(r.total?.value, 1.0);
      expect(r.lines.length, 1);
    });

    test('total et montant sur deux rangées ; prix seul sous le libellé', () {
      final r = read(['HARISSA SICAM', '1,450', 'TOTAL', '1,450']);
      expect(r.lines.single.label, 'HARISSA SICAM');
      expect(r.lines.single.price, 1.45);
      expect(r.total?.value, 1.45);
    });

    test('confiance : ligne nette sûre, chiffre deviné ou libellé abîmé douteux', () {
      final r = read(['LAIT DELICE 1L  1,350', 'CAFE BONDIN  1,3S0', '#*  0,500', 'FROMAGE  2,95'], confidence: 0.95);
      final byLabel = {for (final l in r.lines) l.label: l};
      expect(byLabel['LAIT DELICE 1L']!.isDoubtful, isFalse);
      expect(byLabel['CAFE BONDIN']!.isDoubtful, isTrue, reason: 'S lu à la place de 5');
      expect(byLabel.containsKey('#*'), isFalse, reason: 'pas de libellé : ignorée');
      expect(byLabel['FROMAGE']!.isDoubtful, isFalse, reason: '2 décimales : acceptable');
      expect(byLabel['FROMAGE']!.confidence, lessThan(byLabel['LAIT DELICE 1L']!.confidence));
      // La confiance faible de ML Kit fait baisser le score.
      expect(read(['LAIT DELICE 1L  1,350'], confidence: 0.3).lines.single.confidence,
          lessThan(byLabel['LAIT DELICE 1L']!.confidence));
    });
  });

  group('Suivi d\'une image à l\'autre', () {
    final ticket = ['LAIT DELICE 1L  1,350', 'PAIN  0,200', 'TOTAL  1,550'];

    test('une ligne n\'est confirmée qu\'après 2 images ; total vérifié', () {
      final t = LiveScanTracker();
      expect(t.add(read(ticket)), isEmpty);
      expect(t.lines, isEmpty);
      final confirmed = t.add(read(ticket));
      expect(confirmed.map((l) => l.label), ['LAIT DELICE 1L', 'PAIN']);
      expect(t.total, 1.55);
      expect(t.totalCheck, TotalCheck.valid);
      expect(t.highlights.where((h) => h.isTotal).length, 1);
    });

    test('écart signalé quand une ligne manque', () {
      final t = LiveScanTracker();
      for (var i = 0; i < 2; i++) {
        t.add(read(['LAIT DELICE 1L  1,350', 'TOTAL  1,550']));
      }
      expect(t.totalCheck, TotalCheck.gap);
      expect(t.gap, closeTo(0.2, 0.0001));
    });

    test('vote : une lecture fautive isolée est corrigée, libellé tolérant aux erreurs', () {
      final t = LiveScanTracker();
      t.add(read(['LAIT DELICE 1L  1,350']));
      t.add(read(['LAIT DEL1CE 1L  1,850'])); // une image ratée
      t.add(read(['LAIT DELICE 1L  1,350']));
      expect(t.lines.length, 1);
      expect(t.lines.single.label, 'LAIT DELICE 1L');
      expect(t.lines.single.price, 1.35);
      expect(t.lines.single.isDoubtful, isFalse);
    });

    test('lectures qui varient sans cesse : ligne douteuse', () {
      final t = LiveScanTracker();
      for (final p in ['1,350', '1,850', '1,380', '1,350']) {
        t.add(read(['FROMAGE PRESIDENT  $p']));
      }
      expect(t.lines.single.isDoubtful, isTrue);
    });

    test('stable après 3 images identiques ; un changement relance l\'attente', () {
      final t = LiveScanTracker();
      t.add(read(ticket));
      t.add(read(ticket)); // confirmées
      t.add(read(ticket));
      t.add(read(ticket));
      expect(t.isStable, isFalse);
      t.add(read(ticket));
      expect(t.isStable, isTrue);
      t.add(read([...ticket.take(2), 'BEURRE  2,100', 'TOTAL 3,650']));
      t.add(read([...ticket.take(2), 'BEURRE  2,100', 'TOTAL 3,650']));
      expect(t.isStable, isFalse, reason: 'nouvelle ligne confirmée');
    });

    test('bruit vu une seule fois oublié ; ordre du ticket conservé en remontant', () {
      final t = LiveScanTracker();
      t.add(read(['PAIN  0,200', 'BEURRE  2,100']));
      t.add(read(['PAIN  0,200', 'REFLET XX  9,990', 'BEURRE  2,100']));
      // On remonte : « LAIT » apparaît au-dessus de « PAIN ».
      t.add(read(['LAIT  1,350', 'PAIN  0,200']));
      t.add(read(['LAIT  1,350', 'PAIN  0,200']));
      for (var i = 0; i < 6; i++) {
        t.add(read(['LAIT  1,350', 'PAIN  0,200', 'BEURRE  2,100']));
      }
      expect(t.lines.map((l) => l.label), ['LAIT', 'PAIN', 'BEURRE']);
    });

    test('deux articles identiques sur la même image restent deux lignes', () {
      final t = LiveScanTracker();
      for (var i = 0; i < 2; i++) {
        t.add(read(['PAIN  0,200', 'PAIN  0,200']));
      }
      expect(t.lines.length, 2);
      expect(t.linesSum, 0.4);
    });
  });

  test('≈ 3 images par seconde, jamais deux lectures à la fois', () {
    final gate = FrameGate();
    final t0 = DateTime(2026, 11, 25, 10);
    expect(gate.tryStart(t0), isTrue);
    expect(gate.tryStart(t0.add(const Duration(milliseconds: 400))), isFalse, reason: 'lecture en cours');
    gate.done();
    expect(gate.tryStart(t0.add(const Duration(milliseconds: 200))), isFalse, reason: 'trop tôt');
    expect(gate.tryStart(t0.add(const Duration(milliseconds: 340))), isTrue);
    gate.done();
    var accepted = 0;
    for (var ms = 0; ms < 3000; ms += 33) {
      // flux à 30 images/s pendant 3 s
      if (gate.tryStart(t0.add(Duration(milliseconds: 1000 + ms)))) {
        accepted++;
        gate.done();
      }
    }
    expect(accepted, inInclusiveRange(8, 10));
  });

  test('luminosité moyenne et rangées avec leur position', () {
    expect(meanLuma(List.filled(1000, 255)), 1);
    expect(meanLuma(List.filled(1000, 26)), closeTo(0.1, 0.01));
    final r = groupRows(const [
      OcrFragment('LAIT', left: 10, top: 100, right: 60, bottom: 120, confidence: 0.9),
      OcrFragment('1,350', left: 200, top: 102, right: 250, bottom: 121, confidence: 0.7),
      OcrFragment('PAIN', left: 10, top: 140, right: 60, bottom: 160),
    ]);
    expect(r.map((x) => x.text), ['LAIT  1,350', 'PAIN']);
    expect([r.first.left, r.first.top, r.first.right, r.first.bottom], [10, 100, 250, 121]);
    expect(r.first.confidence, 0.7);
  });
}
