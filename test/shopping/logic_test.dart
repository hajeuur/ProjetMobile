import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/advice.dart';
import 'package:panier_malin/features/shopping/logic/badges.dart';
import 'package:panier_malin/features/shopping/logic/budget_forecast.dart';
import 'package:panier_malin/features/shopping/logic/categories.dart';
import 'package:panier_malin/features/shopping/logic/item_sorting.dart';
import 'package:panier_malin/features/shopping/logic/ocr_rows.dart';
import 'package:panier_malin/features/shopping/logic/price_alerts.dart';
import 'package:panier_malin/features/shopping/logic/receipt_matcher.dart';
import 'package:panier_malin/features/shopping/logic/receipt_parser.dart';
import 'package:panier_malin/features/shopping/logic/store_comparison.dart';
import 'package:panier_malin/features/shopping/logic/text_similarity.dart';
import 'package:panier_malin/features/shopping/models/budget.dart';
import 'package:panier_malin/features/shopping/models/dates.dart';
import 'package:panier_malin/features/shopping/models/shopping_list.dart';
import 'package:panier_malin/features/shopping/ui/budget_screen.dart' show groupCategories;

void main() {
  group('Lecture du ticket', () {
    test('lignes, quantité sur la ligne suivante, total et date', () {
      const text = '''
CARREFOUR LA MARSA
Av. Habib Bourguiba
Tel: 71 123 456
23/11/2026 18:42
LAIT DELICE DEMI ECR 1L      2,700
2 x 1,350
PAIN BAGUETTE                0,400
YAOURT VITALAIT 4 x 0,600    2,400
TOMATES 1,250 kg x 2,000     2,500
REMISE FIDELITE             -0,500
SOUS TOTAL                   7,500
TOTAL TTC                    7,500
ESPECES                     10,000
RENDU                        2,500
''';
      final r = parseReceiptText(text);
      expect(r.lines.map((l) => l.label), [
        'LAIT DELICE DEMI ECR 1L',
        'PAIN BAGUETTE',
        'YAOURT VITALAIT',
        'TOMATES',
        'REMISE FIDELITE',
      ]);
      expect(r.lines[0].quantity, 2);
      expect(r.lines[0].price, 2.7);
      expect(r.lines[2].quantity, 4);
      expect(r.lines[3].quantity, 1.25);
      expect(r.lines[4].price, -0.5);
      expect(r.total, 7.5);
      expect(r.isConsistent, isTrue);
      expect(r.date, DateTime(2026, 11, 23));
      expect(r.headerLines.first, 'CARREFOUR LA MARSA');
    });

    test('« NET A PAYER » prime sur « TOTAL », prix seul sur la ligne suivante', () {
      const text = '''
MONOPRIX
HUILE OLIVE 1L
18.500
CAFE MOULU 250G   7.900 DT
TOTAL   26,400
NET A PAYER
26,000
''';
      final r = parseReceiptText(text);
      expect(r.lines.length, 2);
      expect(r.lines[0].label, 'HUILE OLIVE 1L');
      expect(r.lines[0].price, 18.5);
      expect(r.total, 26.0);
      expect(r.isConsistent, isFalse);
      expect(r.headerLines, ['MONOPRIX']);
    });

    test('libellé puis « 3 x 0,900 » crée une ligne, code-barres en tête', () {
      final r = parseReceiptText('EAU MINERALE\n3 x 0,900   2,700\n6191234567890 HARISSA 380G  2,950\n');
      expect(r.lines[0].label, 'EAU MINERALE');
      expect(r.lines[0].quantity, 3);
      expect(r.lines[0].price, 2.7);
      expect(r.lines[1].barcode, '6191234567890');
      expect(r.lines[1].label, 'HARISSA 380G');
      expect(r.total, isNull);
      expect(r.effectiveTotal, closeTo(5.65, 1e-9));
    });

    test('les fragments OCR sont regroupés par ligne, de gauche à droite', () {
      final rows = rowsFromFragments(const [
        OcrFragment('2,700', left: 300, top: 101, right: 360, bottom: 121),
        OcrFragment('LAIT 1L', left: 10, top: 100, right: 120, bottom: 120),
        OcrFragment('PAIN', left: 10, top: 130, right: 60, bottom: 150),
        OcrFragment('0,400', left: 300, top: 132, right: 360, bottom: 152),
      ]);
      expect(rows, ['LAIT 1L  2,700', 'PAIN  0,400']);
    });
  });

  group('Similarité et rapprochement', () {
    test('abréviations et contenances ignorées', () {
      expect(labelSimilarity('Lait', 'LAIT DELICE DEMI ECR 1L'), greaterThan(0.8));
      expect(labelSimilarity('Yaourt', 'YAOU NAT X4'), greaterThan(0.7));
      expect(labelSimilarity('Tomates', 'TOMATE RONDE'), greaterThan(0.8));
      expect(labelSimilarity('Huile d\'olive', 'HLE OLIVE 1L'), greaterThan(0.8));
      expect(labelSimilarity('Café', 'LESSIVE 3KG'), 0);
    });

    test('affectation un pour un, oubliés et hors liste', () {
      final r = matchReceipt(const [
        MatchCandidate(id: 1, label: 'Lait'),
        MatchCandidate(id: 2, label: 'Pain'),
        MatchCandidate(id: 3, label: 'Café'),
        MatchCandidate(id: 4, label: 'Sucre', checked: true),
      ], const [
        LineCandidate(index: 0, label: 'CHOCOLAT AU LAIT'),
        LineCandidate(index: 1, label: 'LAIT DEMI ECREME 1L'),
        LineCandidate(index: 2, label: 'PAIN DE MIE'),
        LineCandidate(index: 3, label: 'SHAMPOOING'),
      ]);
      final byItem = {for (final m in r.matches) m.itemId: m.lineIndex};
      expect(byItem[1], 1, reason: '« Lait » va à LAIT DEMI ECREME, pas au chocolat');
      expect(byItem[2], 2);
      expect(r.forgottenItemIds, [3], reason: 'le sucre déjà coché n\'est pas « oublié »');
      expect(r.unplannedLineIndexes, containsAll([0, 3]));
    });

    test('même produit rapproché (gestion 2) : score maximal', () {
      final r = matchReceipt(
        const [MatchCandidate(id: 1, label: 'Boisson gazeuse', productId: 14)],
        const [LineCandidate(index: 0, label: 'COCA COLA 33CL', productId: 14)],
      );
      expect(r.matches.single.score, 1);
    });
  });

  test('catégories devinées depuis les libellés de ticket', () {
    expect(guessCategory('LAIT DEMI ECR 1L'), 'Produits laitiers');
    expect(guessCategory('CHOCOLAT AU LAIT'), 'Épicerie sucrée');
    expect(guessCategory('TOMATES'), 'Fruits et légumes');
    expect(guessCategory('LESSIVE 3KG'), 'Hygiène et entretien');
    expect(guessCategory('XYZ123'), 'Autre');
  });

  group('Hausses de prix', () {
    PricePoint p(String key, DateTime d, double price, int receipt) =>
        PricePoint(key: key, label: key, date: d, unitPrice: price, receiptId: receipt);

    test('au-delà de +10 % par rapport à la moyenne des 3 mois précédents', () {
      final alerts = detectPriceIncreases([
        p('huile', DateTime(2026, 6, 1), 10, 1), // hors fenêtre de 90 jours
        p('huile', DateTime(2026, 9, 10), 15, 2),
        p('huile', DateTime(2026, 10, 10), 16, 3),
        p('huile', DateTime(2026, 11, 15), 18.5, 4), // +19 %
        p('lait', DateTime(2026, 10, 1), 1.35, 2),
        p('lait', DateTime(2026, 11, 15), 1.45, 4), // +7 % : pas d'alerte
        p('cafe', DateTime(2026, 11, 15), 9, 4), // un seul achat
      ]);
      expect(alerts.single.key, 'huile');
      expect(alerts.single.average, 15.5);
      expect(alerts.single.increase, closeTo(0.1935, 1e-3));
      expect(alerts.single.sampleCount, 2);
    });

    test('deux lignes du même ticket ne se comparent pas entre elles', () {
      final alerts = detectPriceIncreases([
        p('pain', DateTime(2026, 11, 15), 0.2, 4),
        p('pain', DateTime(2026, 11, 15), 0.4, 4),
      ]);
      expect(alerts, isEmpty);
    });
  });

  group('Budget et prévision de fin de mois', () {
    final budget = Budget(userId: 1, month: DateTime(2026, 11), amount: 300, alertThreshold: 80);

    test('rythme qui mène au dépassement : avertissement avant qu\'il arrive', () {
      final s = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 150, today: DateTime(2026, 11, 10));
      expect(s.level, BudgetLevel.ok);
      expect(s.projected, 450); // 150 / 10 j × 30 j
      expect(s.forecastOverrun, isTrue);
      expect(s.forecastOverrunDay, 20);
      expect(s.dailyAllowance, closeTo(7.5, 1e-9)); // 150 DT pour 20 jours
    });

    test('seuil puis dépassement', () {
      final t = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 250, today: DateTime(2026, 11, 28));
      expect(t.level, BudgetLevel.threshold);
      final e = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 310, today: DateTime(2026, 11, 28));
      expect(e.level, BudgetLevel.exceeded);
      expect(e.forecastOverrun, isFalse, reason: 'déjà dépassé : plus une prévision');
    });

    test('mois terminé : la prévision est la dépense réelle', () {
      final s = BudgetSnapshot.compute(month: DateTime(2026, 10), budget: budget, spent: 120, today: DateTime(2026, 11, 5));
      expect(s.projected, 120);
      expect(s.daysLeft, 0);
      expect(s.forecastOverrun, isFalse);
    });

    test('formats', () {
      expect(formatDt(12.35), '12,350 DT');
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(formatPct(0.153), '+15 %');
    });
  });

  test('tri par rayon selon le magasin, articles cochés en bas', () {
    ShoppingItem i(int id, String label, {bool checked = false}) =>
        ShoppingItem(id: id, listId: 1, label: label, position: id, checked: checked);
    final items = [i(0, 'Lait'), i(1, 'Tomates'), i(2, 'Eau minérale'), i(3, 'Pain', checked: true)];
    final sorted = sortItems(items, ItemSort.aisle, aisleOrder: const ['Boissons', 'Fruits et légumes', 'Produits laitiers']);
    expect(sorted.map((x) => x.label), ['Eau minérale', 'Tomates', 'Lait', 'Pain']);
    expect(sortItems(items, ItemSort.added).map((x) => x.label), ['Lait', 'Tomates', 'Eau minérale', 'Pain']);
    expect(searchItems(items, 'EAU').single.label, 'Eau minérale');
  });

  group('Affichage', () {
    test('axe propre : paliers ronds, plus de « 161 » collé à « 150 »', () {
      expect(niceAxis(161), (maxY: 200.0, interval: 50.0));
      expect(niceAxis(140), (maxY: 150.0, interval: 50.0));
      expect(niceAxis(150), (maxY: 200.0, interval: 50.0));
      expect(niceAxis(23), (maxY: 30.0, interval: 10.0));
      expect(niceAxis(0), (maxY: 100.0, interval: 25.0));
    });

    test('abréviations de mois toutes distinctes (juin / juil.)', () {
      final all = [for (var m = 1; m <= 12; m++) monthShort(DateTime(2026, m))];
      expect(all.toSet().length, 12);
      expect(monthShort(DateTime(2026, 6)), 'juin');
      expect(monthShort(DateTime(2026, 7)), 'juil.');
      expect(monthTitle(DateTime(2026, 11)), 'Novembre 2026');
      expect(plural(1, 'achat'), '1 achat');
      expect(plural(3, 'achat'), '3 achats');
    });

    test('camembert : petites catégories regroupées dans « Autres »', () {
      final g = groupCategories({
        'Viandes': 50, 'Laitiers': 20, 'Épicerie': 15, 'Boissons': 8, 'Hygiène': 4, 'Surgelés': 2, 'Pain': 1,
      });
      expect(g.map((e) => e.key), ['Viandes', 'Laitiers', 'Épicerie', 'Boissons', 'Autres']);
      expect(g.last.value, 7);
    });
  });

  group('Conseil du jour', () {
    final budget = Budget(userId: 1, month: DateTime(2026, 11), amount: 140, alertThreshold: 80);

    test('rythme trop rapide : montant par jour et achats non essentiels', () {
      final s = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 120.55, today: DateTime(2026, 11, 24));
      final a = dailyAdvice(s, topCategory: const MapEntry('Viandes et poissons', 52.1));
      expect(a.tone, AdviceTone.warning);
      expect(a.message, contains('3,242 DT par jour'));
      expect(a.message, contains('non essentiels'));
      expect(a.message, contains('Viandes et poissons'));
    });

    test('dans les clous, dépassé, pas de budget', () {
      final ok = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 30, today: DateTime(2026, 11, 10));
      expect(dailyAdvice(ok).tone, AdviceTone.good);
      final over = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: budget, spent: 150, today: DateTime(2026, 11, 20));
      expect(dailyAdvice(over).tone, AdviceTone.danger);
      final none = BudgetSnapshot.compute(month: DateTime(2026, 11), budget: null, spent: 10, today: DateTime(2026, 11, 20));
      expect(dailyAdvice(none).title, 'Fixez un budget');
    });
  });

  group('Comparateur de magasins', () {
    final now = DateTime(2026, 11, 24);
    PricePoint p(String key, String label, String store, double price, int daysAgo) => PricePoint(
          key: key, label: label, date: now.subtract(Duration(days: daysAgo)), unitPrice: price, storeName: store);

    final points = [
      p('p:7', 'TOMATES', 'Marché central', 1.2, 80),
      p('p:7', 'TOMATES', 'Marché central', 1.5, 20), // dernier prix au marché
      p('p:7', 'TOMATES', 'Carrefour', 1.3, 30),
      p('p:6', 'CAFE MOULU', 'Carrefour', 6.85, 35),
      p('p:6', 'CAFE MOULU', 'Monoprix', 7.9, 9),
      p('l:sucre', 'SUCRE 1KG', 'Aziza', 1.4, 50),
      p('p:4', 'HUILE OLIVE', 'Carrefour', 15.9, 200), // trop ancien
    ];

    test('dernier prix par magasin, le moins cher en premier', () {
      final m = latestPricesByStore(points, now: now);
      expect(m['p:7']!.cheapest.storeName, 'Carrefour');
      expect(m['p:7']!.prices.map((x) => x.unitPrice), [1.3, 1.5]);
      expect(m['p:7']!.saving, closeTo(0.2, 1e-9));
      expect(m.containsKey('p:4'), isFalse);
      expect(comparableProducts(m).map((x) => x.key), ['p:6', 'p:7']); // plus gros écart d'abord
    });

    test('coût de la liste par magasin, prix manquants estimés', () {
      final m = latestPricesByStore(points, now: now);
      final c = compareBasket(const [
        BasketEntry(label: 'Tomates', productId: 7, quantity: 2),
        BasketEntry(label: 'Café'),
        BasketEntry(label: 'Sucre'),
        BasketEntry(label: 'Lessive'),
      ], m);
      expect(c.unknownLabels, ['Lessive']);
      expect(c.best!.storeName, 'Carrefour');
      final carrefour = c.stores.firstWhere((s) => s.storeName == 'Carrefour');
      expect(carrefour.known, 2);
      expect(carrefour.estimated, 1); // sucre : moyenne des autres
      expect(carrefour.total, closeTo(2 * 1.3 + 6.85 + 1.4, 1e-9));
    });
  });

  test('badges : série de mois dans le budget', () {
    final now = DateTime(2026, 11, 24);
    final months = [
      (month: DateTime(2026, 8), spent: 70.0, budget: 100.0),
      (month: DateTime(2026, 9), spent: 90.0, budget: 80.0), // dépassé : coupe la série
      (month: DateTime(2026, 10), spent: 60.0, budget: 90.0),
      (month: DateTime(2026, 11), spent: 999.0, budget: 10.0), // mois en cours ignoré
    ];
    expect(budgetStreak(months, now), 1);
    final b = computeBadges(budgetStreakMonths: 1, perfectTrips: 1, receiptCount: 12, completedLists: 0, priceComparisons: 2);
    expect(b.firstWhere((x) => x.id == 'budget3').progressText, '1 / 3');
    expect(b.firstWhere((x) => x.id == 'zero_oubli').unlocked, isTrue);
    expect(b.firstWhere((x) => x.id == 'scanner').unlocked, isTrue);
  });

  test('fiabilité d\'une alerte selon le nombre d\'achats', () {
    PriceAlert a(int n) => PriceAlert(key: 'p:4', label: 'HUILE', lastPrice: 18, average: 16, lastDate: DateTime(2026), sampleCount: n);
    expect(a(1).reliability, AlertReliability.low);
    expect(a(3).reliability, AlertReliability.medium);
    expect(a(5).reliability, AlertReliability.high);
    expect(a(1).productId, 4);
  });
}
