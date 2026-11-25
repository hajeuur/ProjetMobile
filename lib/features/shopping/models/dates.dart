/// Petits outils de dates et de formatage partagés par la gestion 5.
library;

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Premier jour du mois de [d].
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// Clé de mois stockée en base : « 2026-11 ».
String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime parseMonthKey(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

DateTime addMonths(DateTime month, int n) => DateTime(month.year, month.month + n);

int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// Montant en dinars tunisiens, 3 décimales (millimes) : « 12,350 DT ».
String formatDt(double amount, {bool symbol = true}) {
  final s = amount.toStringAsFixed(3).replaceAll('.', ',');
  return symbol ? '$s DT' : s;
}

String formatQuantity(double? q, String? unit) {
  if (q == null) return unit ?? '';
  final n = q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
  return unit == null || unit.isEmpty ? n : '$n $unit';
}

String formatPct(double ratio, {bool sign = true}) {
  final v = (ratio * 100).round();
  return '${sign && v > 0 ? '+' : ''}$v %';
}

const monthNamesFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Abréviations usuelles, toutes distinctes (« juin » / « juil. »).
const monthShortFr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String monthLabel(DateTime d) => '${monthNamesFr[d.month - 1]} ${d.year}';

/// « Novembre 2026 » (en-têtes).
String monthTitle(DateTime d) {
  final n = monthNamesFr[d.month - 1];
  return '${n[0].toUpperCase()}${n.substring(1)} ${d.year}';
}

String monthShort(DateTime d) => monthShortFr[d.month - 1];

/// « 1 achat », « 3 achats ».
String plural(int n, String singular, [String? pluralForm]) => '$n ${n > 1 ? (pluralForm ?? '${singular}s') : singular}';

/// Graduation « propre » d'un axe : pas de 1, 2, 2,5 ou 5 × 10^k, au plus
/// [maxTicks] intervalles, et un maximum multiple du pas (0, 50, 100, 150).
({double maxY, double interval}) niceAxis(double maxValue, {int maxTicks = 4}) {
  if (maxValue <= 0) return (maxY: 100, interval: 25);
  final raw = maxValue / maxTicks;
  var magnitude = 1.0;
  while (magnitude * 10 <= raw) {
    magnitude *= 10;
  }
  while (magnitude > raw) {
    magnitude /= 10;
  }
  var step = magnitude * 10;
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (magnitude * m >= raw) {
      step = magnitude * m;
      break;
    }
  }
  final maxY = (maxValue / step).ceil() * step;
  return (maxY: maxY == maxValue ? maxY + step : maxY, interval: step);
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
