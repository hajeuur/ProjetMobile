import 'dart:convert';

import '../logic/categories.dart';
import '../logic/pack_format.dart';
import '../logic/text_similarity.dart';
import '../models/budget.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../models/shopping_list.dart';
import 'shopping_repository.dart';

/// Données de démonstration : une liste en cours, quatre mois de tickets
/// (avec deux hausses de prix) et des budgets. Écrites seulement si la
/// gestion est vide.
Future<void> seedDemoShoppingIfEmpty(ShoppingRepository repo, int userId, DateTime today) async {
  if ((await repo.lists(userId)).isNotEmpty || (await repo.receipts(userId)).isNotEmpty) return;

  // --- Liste en cours.
  final listId = await repo.insertList(
    ShoppingList(
      userId: userId,
      name: 'Courses de la semaine',
      createdAt: today.subtract(const Duration(days: 1)),
      storeId: 1,
    ),
  );
  const items = [
    ('Lait', 2.0, 'L', 1, ItemOrigin.shortage),
    ('Pain', 2.0, null, 2, ItemOrigin.manual),
    ('Tomates', 1.0, 'kg', 7, ItemOrigin.recipe),
    ('Yaourt', 4.0, null, 3, ItemOrigin.manual),
    ('Huile d\'olive', 1.0, 'L', 4, ItemOrigin.manual),
    ('Spaghetti', 2.0, null, 5, ItemOrigin.manual),
    ('Café', 1.0, null, 6, ItemOrigin.manual),
    ('Harissa', 1.0, null, 9, ItemOrigin.recipe),
    ('Liquide vaisselle', 1.0, null, null, ItemOrigin.manual),
  ];
  for (var i = 0; i < items.length; i++) {
    final (label, qty, unit, productId, origin) = items[i];
    await repo.insertItem(
      ShoppingItem(
        listId: listId,
        label: label,
        quantity: qty,
        unit: unit,
        productId: productId,
        origin: origin,
        aisle: guessCategory(label),
        position: i,
        createdAt: today,
      ),
    );
  }

  // --- Tickets des mois passés et du mois en cours.
  final thisMonth = monthStart(today);
  DateTime at(int monthOffset, int day) {
    final m = addMonths(thisMonth, monthOffset);
    final d = day.clamp(1, monthOffset == 0 ? today.day : daysInMonth(m));
    return DateTime(m.year, m.month, d, 18, 30);
  }

  ReceiptLine l(String label, double price, {double qty = 1, int? productId, String? barcode}) {
    final f = parsePackFormat(label);
    return ReceiptLine(
      label: label,
      quantity: qty,
      price: price,
      productId: productId,
      barcode: barcode,
      category: guessCategory(label),
      packSize: f?.amount,
      packUnit: f?.measure.base,
    );
  }

  final receipts = <(DateTime, int, String, List<ReceiptLine>)>[
    // Juin et juillet : historique plus ancien (meilleur moment pour acheter :
    // tomates moins chères en début de mois au Marché central).
    (at(-5, 3), 4, 'Marché central', [l('TOMATES', 1.900, qty: 2, productId: 7), l('OIGNONS', 1.600)]),
    (
      at(-5, 24),
      1,
      'Carrefour La Marsa',
      [
        l('TOMATES', 2.700, qty: 2, productId: 7),
        l('LAIT DEMI ECR 1L', 2.700, qty: 2, productId: 1),
        l('PAIN DE MIE', 2.200),
      ],
    ),
    (at(-4, 5), 4, 'Marché central', [l('TOMATES', 2.000, qty: 2, productId: 7), l('POIVRONS', 2.400)]),
    (
      at(-4, 22),
      2,
      'Monoprix Lafayette',
      [
        l('TOMATES', 2.800, qty: 2, productId: 7),
        l('YAOURT NATURE X4', 2.400, productId: 3),
        l('CAFE EN GRAINS 250G', 9.800),
      ],
    ),
    (
      at(-3, 4),
      1,
      'Carrefour La Marsa',
      [
        l('LAIT DEMI ECR 1L', 2.700, qty: 2, productId: 1),
        l('HUILE OLIVE 1L', 15.900, productId: 4),
        l('CAFE MOULU 250G', 6.800, productId: 6),
        l('SPAGHETTI 500G', 2.200, qty: 2, productId: 5),
        l('POULET ENTIER', 14.500, productId: 12),
        l('LESSIVE 3KG', 18.900),
        l('NUTELLA 400G', 13.900, productId: 13, barcode: '3017620422003'),
      ],
    ),
    (
      at(-3, 17),
      4,
      'Marché central',
      [
        l('TOMATES', 2.400, qty: 2, productId: 7),
        l('POMMES DE TERRE', 3.000, qty: 2),
        l('OIGNONS', 1.800),
        l('ORANGES', 4.500, qty: 3),
      ],
    ),
    (
      at(-2, 3),
      2,
      'Monoprix Lafayette',
      [
        l('LAIT DEMI ECR 1L', 2.700, qty: 2, productId: 1),
        l('YAOURT NATURE X4', 2.400, productId: 3),
        l('CAFE MOULU 250G', 6.900, productId: 6),
        l('HARISSA 380G', 2.950, productId: 9),
        l('NUTELLA 400G', 13.500, productId: 13, barcode: '3017620422003'),
        l('TOMATES', 2.700, qty: 2, productId: 7),
        l('EAU MINERALE 1.5L X6', 4.200, productId: 10),
      ],
    ),
    (
      at(-2, 21),
      1,
      'Carrefour La Marsa',
      [
        l('HUILE OLIVE 1L', 16.200, productId: 4),
        l('VIANDE HACHEE', 19.500),
        l('POULET ENTIER', 15.000, productId: 12),
        l('CAFE EN GRAINS 200G', 9.800),
        l('FROMAGE RAPE', 5.900),
        l('PAIN DE MIE', 2.300),
        l('SHAMPOOING', 9.800),
      ],
    ),
    (
      at(-1, 6),
      3,
      'Aziza Ennasr',
      [
        l('LAIT DEMI ECR 1L', 3.900, qty: 3, productId: 1),
        l('SUCRE 1KG', 1.400, productId: 11),
        l('YAOURT NATURE X4', 2.500, productId: 3),
        l('SPAGHETTI 500G', 2.200, qty: 2, productId: 5),
        l('COCA COLA 33CL', 3.600, qty: 4, productId: 14, barcode: '5449000000996'),
        l('BISCUITS', 3.200),
      ],
    ),
    (
      at(-1, 19),
      1,
      'Carrefour La Marsa',
      [
        l('POULET ENTIER', 15.200, productId: 12),
        l('TOMATES', 2.600, qty: 2, productId: 7),
        l('HARISSA 380G', 2.750, productId: 9),
        l('YAOURT NATURE X4', 2.400, productId: 3),
        l('CAFE MOULU 250G', 6.850, productId: 6),
        l('DETERGENT SOL', 7.400),
        l('PAPIER HYGIENIQUE X12', 12.900),
        l('POMMES', 4.800, qty: 2),
        l('NUTELLA 400G', 14.200, productId: 13, barcode: '3017620422003'),
      ],
    ),
    (
      at(0, 2),
      4,
      'Marché central',
      [l('TOMATES', 3.000, qty: 2, productId: 7), l('POIVRONS', 2.600), l('BANANES', 6.900)],
    ),
    (
      at(0, 8),
      1,
      'Carrefour La Marsa',
      [
        l('HUILE OLIVE 1L', 18.500, productId: 4),
        l('LAIT DEMI ECR 1L', 2.700, qty: 2, productId: 1),
        l('VIANDE HACHEE', 21.000),
        l('OEUFS X10', 4.200, productId: 8),
        l('SAVON MAINS', 3.900),
      ],
    ),
    (
      at(0, 15),
      2,
      'Monoprix Lafayette',
      [
        l('CAFE MOULU 250G', 7.900, productId: 6),
        l('HARISSA 380G', 2.950, productId: 9),
        l('PAIN BAGUETTE', 0.400, qty: 2, productId: 2),
        l('FROMAGE RAPE', 6.100),
        l('JUS ORANGE 1L', 4.600),
        l('POULET ENTIER', 15.900, productId: 12),
        l('LESSIVE 3KG', 19.900),
      ],
    ),
  ];

  final receiptIds = <int>[];
  for (final (date, storeId, storeName, lines) in receipts) {
    receiptIds.add(
      await repo.insertReceipt(
        Receipt(
          userId: userId,
          storeId: storeId,
          storeName: storeName,
          date: date,
          total: double.parse(lines.fold<double>(0, (s, x) => s + x.price).toStringAsFixed(3)),
          lines: lines,
        ),
      ),
    );
  }

  // --- Suggestions : « Sacs poubelle » oubliés lors de 3 courses passées
  // (rapprochement ticket ↔ liste) → « Tu oublies souvent… ».
  await repo.setSetting(
    'forgotten_counts',
    jsonEncode({
      'l:${labelKey('Sacs poubelle')}': {
        'label': 'Sacs poubelle',
        'receipts': [receiptIds[4], receiptIds[7], receiptIds[9]],
      },
    }),
  );

  // --- Budgets : le mois -2 a été dépassé ; le mois en cours a passé le
  // seuil de 80 % et la prévision dépasse le budget.
  for (final (offset, amount) in [(-3, 100.0), (-2, 80.0), (-1, 90.0), (0, 140.0)]) {
    await repo.upsertBudget(
      Budget(userId: userId, month: addMonths(thisMonth, offset), amount: amount, alertThreshold: 80),
    );
  }
}
