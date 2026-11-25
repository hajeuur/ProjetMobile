import 'package:flutter_test/flutter_test.dart';
import 'package:panier_malin/features/shopping/logic/voice_parser.dart';

void main() {
  const p = VoiceItemParser();
  List<String> parse(String s) => p.parse(s).map((e) => e.toString()).toList();

  test('phrase type : intro ignorée, virgules et « et »', () {
    expect(parse('ajoute lait, pain et 6 œufs'), ['Lait', 'Pain', '6.0 Œufs']);
    expect(p.parse('ajoute lait, pain et 6 œufs').last, const VoiceItem(label: 'Œufs', quantity: 6));
  });

  test('quantités en lettres, douzaine, demi', () {
    expect(p.parse('mets deux baguettes et trois yaourts'), const [
      VoiceItem(label: 'Baguettes', quantity: 2),
      VoiceItem(label: 'Yaourts', quantity: 3),
    ]);
    expect(p.parse("je veux une douzaine d'œufs").single, const VoiceItem(label: 'Œufs', quantity: 12));
    expect(p.parse("une demi-douzaine d'œufs").single, const VoiceItem(label: 'Œufs', quantity: 6));
    expect(p.parse("deux douzaines d'œufs").single, const VoiceItem(label: 'Œufs', quantity: 24));
    expect(p.parse('un demi kilo de tomates').single, const VoiceItem(label: 'Tomates', quantity: 0.5, unit: 'kg'));
    expect(p.parse('vingt-quatre canettes de coca').single,
        const VoiceItem(label: 'Coca', quantity: 24, unit: 'canettes'));
  });

  test('unités et « de / du / des »', () {
    expect(p.parse('il me faut deux litres de lait, 1,5 kg de pommes de terre et un paquet de pâtes'), const [
      VoiceItem(label: 'Lait', quantity: 2, unit: 'L'),
      VoiceItem(label: 'Pommes de terre', quantity: 1.5, unit: 'kg'),
      VoiceItem(label: 'Pâtes', quantity: 1, unit: 'paquet'),
    ]);
    expect(p.parse("rajoute 500g de farine et une bouteille d'huile d'olive"), const [
      VoiceItem(label: 'Farine', quantity: 500, unit: 'g'),
      VoiceItem(label: "Huile d'olive", quantity: 1, unit: 'bouteille'),
    ]);
    expect(p.parse('trois paquets de biscuits').single.unit, 'paquets');
  });

  test('articles, politesse, référence à la liste', () {
    expect(parse("ajoute du lait, de la farine et des pommes à ma liste s'il te plaît"),
        ['Lait', 'Farine', 'Pommes']);
    expect(parse('tu peux ajouter le pain puis du café'), ['Pain', 'Café']);
    expect(parse('un peu de sel'), ['Sel']);
    expect(parse("j'ai besoin de harissa"), ['Harissa']);
  });

  test('rien d\'exploitable', () {
    expect(p.parse(''), isEmpty);
    expect(p.parse('ajoute'), isEmpty);
    expect(p.parse('euh, et, deux'), isEmpty);
  });

  test('fusion des quantités avec un article existant', () {
    expect(mergedQuantity(2, 'L', 1, 'L'), (quantity: 3.0, unit: 'L'));
    expect(mergedQuantity(2, 'paquet', 1, 'paquets'), (quantity: 3.0, unit: 'paquet'));
    expect(mergedQuantity(2, 'L', null, null), (quantity: 3.0, unit: 'L'), reason: 'sans quantité dite : +1');
    expect(mergedQuantity(null, null, 6, null), (quantity: 6.0, unit: null));
    expect(mergedQuantity(1, 'kg', 3, null), isNull, reason: '1 kg + 3 pièces : incompatible');
  });
}
