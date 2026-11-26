import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/pack_format.dart';

void main() {
  /// Les 10 libellés de référence, et le format attendu (g ou ml, nombre d'unités).
  final cases = <String, (double, Measure, int)?>{
    'CAFE MOULU 250G': (250, Measure.mass, 1),
    'LAIT DELICE 1L': (1000, Measure.volume, 1),
    'HUILE OLIVE 500 ML': (500, Measure.volume, 1),
    'EAU SAFIA 6X1,5L': (9000, Measure.volume, 6),
    'COCA COLA 33CL': (330, Measure.volume, 1),
    'FARINE 1KG': (1000, Measure.mass, 1),
    'YAOURT VITALAIT 4X125G': (500, Measure.mass, 4),
    'EAU MINERALE 1,5L X6': (9000, Measure.volume, 6),
    'NUTELLA 400 GR': (400, Measure.mass, 1),
    'POULET ENTIER': null, // pas de format : on n'affirme rien
  };

  for (final e in cases.entries) {
    test('« ${e.key} » → ${e.value == null ? 'illisible' : '${e.value!.$1} ${e.value!.$2.base}'}', () {
      final f = parsePackFormat(e.key);
      if (e.value == null) {
        expect(f, isNull);
      } else {
        expect(f, isNotNull);
        expect(f!.amount, e.value!.$1);
        expect(f.measure, e.value!.$2);
        expect(f.count, e.value!.$3);
      }
    });
  }

  test('pièges : nombre sans unité, deux formats, code produit, valeur absurde', () {
    expect(parsePackFormat('BISCUITS 2 PAQUETS'), isNull);
    expect(parsePackFormat('LAIT 1L FROMAGE 500G'), isNull, reason: 'ambigu');
    expect(parsePackFormat('SAVON GEL450ML'), isNull, reason: 'collé à un mot');
    expect(parsePackFormat('PAPIER 99999KG'), isNull);
    expect(parsePackFormat('LAIT 1L 1L')?.amount, 1000, reason: 'même format répété');
  });

  test('libellé lisible et prix au kilo / au litre', () {
    expect(parsePackFormat('CAFE 250G')!.label, '250 g');
    expect(parsePackFormat('EAU 6X1,5L')!.label, '6 × 1,5 L');
    expect(parsePackFormat('COCA 33CL')!.label, '33 cl');
    expect(parsePackFormat('FARINE 1KG')!.label, '1 kg');
    expect(parsePackFormat('CAFE 250G')!.pricePerBig(9.8), closeTo(39.2, 1e-9));
    expect(parsePackFormat('CAFE 200G')!.pricePerBig(9.8), closeTo(49.0, 1e-9));
  });
}
