import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/receipt_reconciler.dart';

/// Les 8 cas de référence du rapprochement ticket ↔ liste, avec le résultat
/// attendu. (Seuils : sûr ≥ 0,75 → coché seul ; 0,5–0,75 → oui/non ; < 0,5 → rien.)
void main() {
  var nextId = 1;
  MatchCandidate item(String label, {int? productId, bool checked = false}) =>
      MatchCandidate(id: nextId++, label: label, productId: productId, checked: checked);
  List<LineCandidate> ticket(List<String> labels) =>
      [for (var i = 0; i < labels.length; i++) LineCandidate(index: i, label: labels[i])];

  group('8 cas de référence', () {
    test('1. « Lait » ~ « LAIT DEMI ECR 1L » → sûr, coché seul', () {
      final r = const ReceiptReconciler().reconcile([item('Lait')], ticket(['LAIT DEMI ECR 1L']));
      expect(r.sure.single.line.label, 'LAIT DEMI ECR 1L');
      expect(r.sure.single.score, greaterThanOrEqualTo(sureMatchScore));
      expect(r.forgotten, isEmpty);
      expect(r.unplanned, isEmpty);
    });

    test('2. Majuscules et accents : « Pâtes » ~ « PATES » → sûr (score 1)', () {
      final r = const ReceiptReconciler().reconcile([item('Pâtes')], ticket(['PATES']));
      expect(r.sure.single.score, 1);
    });

    test('3. Abréviations : « Yaourt nature » ~ « YAOU NAT VITALAIT 4X125G » → sûr', () {
      final r = const ReceiptReconciler().reconcile([item('Yaourt nature')], ticket(['YAOU NAT VITALAIT 4X125G']));
      expect(r.sure, hasLength(1));
    });

    test('4. Lettre mal lue : « Fromage » ~ « FRMAGE BLANC » → sûr (Levenshtein / Jaro-Winkler)', () {
      final r = const ReceiptReconciler().reconcile([item('Fromage')], ticket(['FRMAGE BLANC']));
      expect(r.sure, hasLength(1));
      expect(labelScore('Fromage', 'FRMAGE BLANC'), greaterThan(0.8));
    });

    test('5. « Lait » va à « LAIT DELICE », pas à « CHOCOLAT AU LAIT » (hors liste)', () {
      final r = const ReceiptReconciler().reconcile(
        [item('Lait')],
        ticket(['CHOCOLAT AU LAIT', 'LAIT DELICE 1L']),
      );
      expect(r.sure.single.line.label, 'LAIT DELICE 1L');
      expect(r.unplanned.single.label, 'CHOCOLAT AU LAIT');
    });

    test('6. Cas moyen : « Jus d\'orange » ~ « JUS POMME » → à confirmer (oui/non)', () {
      final r = const ReceiptReconciler().reconcile([item('Jus d\'orange')], ticket(['JUS POMME 1L']));
      expect(r.sure, isEmpty);
      expect(r.uncertain.single.score, inInclusiveRange(askMatchScore, sureMatchScore));
      expect(r.forgotten, isEmpty, reason: 'en attente de la réponse');
      expect(r.unplanned, isEmpty);
    });

    test('7. Aucun rapport : « Pain » / « SAVON » → pain oublié, savon hors liste ; « Laid » ≠ « Lait »', () {
      final r = const ReceiptReconciler().reconcile([item('Pain'), item('Œufs', checked: true)], ticket(['SAVON DE MARSEILLE']));
      expect(r.sure, isEmpty);
      expect(r.uncertain, isEmpty);
      expect(r.forgotten.map((i) => i.label), ['Pain'], reason: 'les œufs étaient déjà cochés');
      expect(r.unplanned.single.label, 'SAVON DE MARSEILLE');
      expect(labelScore('Lait', 'LAID'), lessThan(askMatchScore));
    });

    test('8. Apprentissage : « non » n\'est plus redemandé, « oui » devient sûr', () {
      final memory = CorrectionMemory();
      final reconciler = ReceiptReconciler(memory: memory);
      final jus = item('Jus d\'orange');
      final mouchoirs = item('Mouchoirs');
      var r = reconciler.reconcile([jus, mouchoirs], ticket(['JUS POMME 1L', 'KLEENEX BOITE X100']));
      expect(r.uncertain.single.item.label, 'Jus d\'orange');
      expect(r.forgotten.single.label, 'Mouchoirs', reason: 'Kleenex : aucun mot en commun');

      memory.record('Jus d\'orange', 'JUS POMME 1L', false); // « non »
      memory.record('Mouchoirs', 'KLEENEX BOITE X100', true); // corrigé à la main
      // La mémoire survit à un redémarrage.
      final reloaded = ReceiptReconciler(memory: CorrectionMemory.fromJson(memory.toJson()));
      r = reloaded.reconcile([jus, mouchoirs], ticket(['JUS POMME 1L', 'KLEENEX BOITE X100']));
      expect(r.uncertain, isEmpty);
      expect(r.sure.single.item.label, 'Mouchoirs');
      expect(r.sure.single.reason, MatchReason.learned);
      expect(r.forgotten.single.label, 'Jus d\'orange');
      // Variante de contenance : même clé, la réponse s'applique encore.
      expect(memory.answerFor('mouchoirs', 'KLEENEX BOITE X 50'), isTrue);
    });
  });

  group('Outils', () {
    test('Levenshtein et Jaro-Winkler', () {
      expect(levenshtein('fromage', 'frmage'), 1);
      expect(levenshtein('chat', 'chien'), 3);
      expect(levenshteinRatio('fromage', 'frmage'), closeTo(0.857, 0.001));
      expect(jaroWinkler('martha', 'marhta'), closeTo(0.961, 0.001)); // valeur de référence
      expect(jaroWinkler('dixon', 'dicksonx'), closeTo(0.813, 0.001));
      expect(jaroWinkler('abc', 'xyz'), 0);
    });

    test('même produit (gestion 2) : sûr même si les libellés diffèrent', () {
      final r = const ReceiptReconciler().reconcile(
        [MatchCandidate(id: 1, label: 'Eau', productId: 7)],
        [const LineCandidate(index: 0, label: 'SAFIA 1,5L', productId: 7)],
      );
      expect(r.sure.single.reason, MatchReason.sameProduct);
    });

    test('seuils réglables', () {
      final strict = const ReceiptReconciler(sureThreshold: 0.95, askThreshold: 0.6);
      final r = strict.reconcile([item('Lait')], ticket(['LAIT DEMI ECR 1L']));
      expect(r.sure, isEmpty);
      expect(r.uncertain, hasLength(1));
    });
  });
}
