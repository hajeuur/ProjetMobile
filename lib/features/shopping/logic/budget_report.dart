/// Rapport budget du mois (PDF partagé à un proche) : données, message
/// d'accompagnement et contenu du document, sans dépendance à l'affichage.
///
/// [ReportContent] décrit tout ce qui sera écrit dans le PDF : il est testé
/// seul, puis mis en page par `ReportBuilder` (services/report_builder.dart).
library;

import '../models/dates.dart';
import '../models/receipt.dart';
import 'budget_forecast.dart';
import 'price_alerts.dart';
import 'shrinkflation.dart';
import 'text_similarity.dart';

/// Pourquoi le rapport est produit.
enum ReportReason {
  threshold('Seuil d\'alerte'),
  budget('Budget atteint'),
  test('Rapport test'),
  export('Export manuel');

  const ReportReason(this.label);
  final String label;

  static ReportReason fromName(String? n) => values.firstWhere((r) => r.name == n, orElse: () => export);
}

/// Proche qui reçoit les alertes (consentement explicite enregistré).
class AlertContact {
  const AlertContact({required this.name, required this.phone, required this.consentAt});

  final String name;
  final String phone;

  /// Date à laquelle l'utilisateur a confirmé avoir l'accord du proche.
  final DateTime consentAt;

  /// Prénom pour « Envoyer le rapport à Maman ».
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  Map<String, Object?> toJson() => {'name': name, 'phone': phone, 'consentAt': consentAt.toIso8601String()};

  static AlertContact? fromJson(Map<String, Object?>? m) {
    if (m == null) return null;
    final name = m['name'] as String?;
    final consent = DateTime.tryParse(m['consentAt'] as String? ?? '');
    if (name == null || name.trim().isEmpty || consent == null) return null; // sans accord : pas de contact
    return AlertContact(name: name, phone: m['phone'] as String? ?? '', consentAt: consent);
  }
}

/// Numéro au format international sans « + » pour wa.me (« 216 » ajouté à un
/// numéro tunisien à 8 chiffres). Null si le numéro est inutilisable.
String? internationalNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) {
    d = d.substring(1);
  } else if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.length == 8) {
    d = '216$d'; // numéro tunisien local
  }
  d = d.replaceAll('+', '');
  return d.length >= 8 && d.length <= 15 ? d : null;
}

/// Lien officiel « Click to chat » : `https://wa.me/<numéro>?text=<message>`
/// (texte seulement : un lien ne peut pas joindre de fichier).
Uri whatsAppLink(String number, String text) => Uri.https('wa.me', '/$number', {'text': text});

/// Données du mois.
class MonthlyReportData {
  const MonthlyReportData({
    required this.snapshot,
    required this.generatedAt,
    this.categories = const {},
    this.tickets = const [],
    this.priceIncreases = const [],
    this.shrinks = const [],
  });

  final BudgetSnapshot snapshot;
  final DateTime generatedAt;

  /// Dépenses par catégorie (de la plus grosse à la plus petite).
  final Map<String, double> categories;
  final List<Receipt> tickets;
  final List<PriceAlert> priceIncreases;
  final List<ShrinkAlert> shrinks;

  DateTime get month => snapshot.month;
  String get monthName => monthNamesFr[month.month - 1];
}

class ReportOptions {
  const ReportOptions({this.maskAmounts = true, this.includeItems = false, this.reason = ReportReason.export});

  /// Montants masqués : seuls les pourcentages apparaissent (réglage par défaut).
  final bool maskAmounts;

  /// Détail des articles sous chaque ticket.
  final bool includeItems;
  final ReportReason reason;
}

/// Vert = bon, orange = attention, rouge = dépassement.
enum ReportTone { good, caution, over }

ReportTone toneOf(BudgetSnapshot s) => switch (s.level) {
  BudgetLevel.exceeded => ReportTone.over,
  BudgetLevel.threshold => ReportTone.caution,
  _ => s.forecastOverrun ? ReportTone.caution : ReportTone.good,
};

/// Reste arrondi vers le bas, à la précision de [shortDt] : on n'annonce
/// jamais plus d'argent qu'il n'en reste (19,45 → « 19,4 DT »).
double floorForSentence(double v) {
  if (v <= 0) return v;
  final digits = v >= 100 ? 0 : (v >= 1 ? 1 : 2);
  final f = digits == 0 ? 1 : (digits == 1 ? 10 : 100);
  return (v * f + 1e-9).floor() / f;
}

/// « 86 % » avec une espace insécable : le « % » ne passe jamais seul à la ligne.
String _pct(double ratio) => '${(ratio * 100).round()} %';

String _days(int n) => n == 1 ? '1 jour' : '$n jours';

/// Message pré-rempli du partage :
/// « PanierMalin : budget de novembre atteint à 86 %. Il reste 19,4 DT pour
/// 5 jours. Rapport en pièce jointe. »
String reportMessage(MonthlyReportData d, {required bool maskAmounts}) {
  final s = d.snapshot;
  final month = d.monthName;
  const tail = 'Rapport en pièce jointe.';
  if (s.budget == null) {
    return maskAmounts
        ? 'PanierMalin : dépenses de $month (aucun budget défini). $tail'
        : 'PanierMalin : dépenses de $month : ${shortDt(s.spent)} (aucun budget défini). $tail';
  }
  final days = s.daysLeft;
  final period = days <= 0 ? 'jusqu\'à la fin du mois' : 'pour ${_days(days)}';
  if (s.level == BudgetLevel.exceeded) {
    final over = maskAmounts ? _pct(s.ratio - 1) : shortDt(s.spent - s.budget!.amount);
    final left = days <= 0 ? 'Le mois est terminé.' : 'Encore ${_days(days)} avant la fin du mois.';
    return 'PanierMalin : budget de $month dépassé (${_pct(s.ratio)}), de $over. $left $tail';
  }
  final left = maskAmounts ? '${_pct(1 - s.ratio)} du budget' : shortDt(floorForSentence(s.remaining));
  // « atteint » au seuil d'alerte ; en dessous (export, test), « utilisé ».
  final verb = s.level == BudgetLevel.threshold ? 'atteint' : 'utilisé';
  return 'PanierMalin : budget de $month $verb à ${_pct(s.ratio)}. Il reste $left $period. $tail';
}

/// Une ligne « libellé → valeur ».
typedef ReportRow = ({String label, String value});

class ReportCategory {
  const ReportCategory(this.name, this.share, this.value);
  final String name;

  /// Part des dépenses du mois (0 à 1), pour la barre du graphique.
  final double share;
  final String value;
}

class ReportTicket {
  const ReportTicket({required this.title, required this.value, this.items = const []});

  /// « 15/11/2026 · Monoprix Lafayette · 7 articles ».
  final String title;
  final String value;

  /// « Café moulu 250g ×1 — 7,900 DT » (si le détail est demandé).
  final List<String> items;
}

/// Tout le texte du PDF, dans l'ordre.
class ReportContent {
  const ReportContent({
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.headline,
    required this.status,
    required this.metrics,
    required this.ratio,
    required this.threshold,
    required this.categories,
    required this.forecast,
    required this.priceIncreases,
    required this.shrinks,
    required this.tickets,
    required this.footer,
    this.testBanner,
  });

  final String title;
  final String subtitle;
  final ReportTone tone;

  /// Grand chiffre du bandeau : « 86 % ».
  final String headline;

  /// « Seuil d'alerte franchi ».
  final String status;
  final List<ReportRow> metrics;

  /// Jauge : part utilisée et seuil (0 à 1).
  final double ratio;
  final double threshold;
  final List<ReportCategory> categories;
  final List<String> forecast;
  final List<String> priceIncreases;
  final List<String> shrinks;
  final List<ReportTicket> tickets;
  final String footer;
  final String? testBanner;

  /// Tout le texte, pour les tests (« aucun montant quand masqué »).
  Iterable<String> get allText sync* {
    yield title;
    yield subtitle;
    yield headline;
    yield status;
    for (final m in metrics) {
      yield m.label;
      yield m.value;
    }
    for (final c in categories) {
      yield c.name;
      yield c.value;
    }
    yield* forecast;
    yield* priceIncreases;
    yield* shrinks;
    for (final t in tickets) {
      yield t.title;
      yield t.value;
      yield* t.items;
    }
    yield footer;
    if (testBanner != null) yield testBanner!;
  }
}

const hidden = 'masqué';

ReportContent buildReportContent(MonthlyReportData d, ReportOptions o) {
  final s = d.snapshot;
  final mask = o.maskAmounts;
  String dt(double v) => mask ? hidden : formatDt(v);
  final b = s.budget;
  final status = switch (s.level) {
    BudgetLevel.exceeded => 'Budget dépassé',
    BudgetLevel.threshold => 'Seuil d\'alerte de ${b!.alertThreshold} % franchi',
    BudgetLevel.ok => s.forecastOverrun ? 'Dans le budget, mais le rythme mène au dépassement' : 'Dans le budget',
    BudgetLevel.none => 'Aucun budget défini',
  };

  final totalCat = d.categories.values.fold(0.0, (a, v) => a + v);
  final categories = [
    for (final e in d.categories.entries)
      if (e.value > 0)
        ReportCategory(
          e.key,
          totalCat == 0 ? 0 : e.value / totalCat,
          mask ? _pct(totalCat == 0 ? 0 : e.value / totalCat) : '${formatDt(e.value)} · ${_pct(e.value / totalCat)}',
        ),
  ];

  final forecast = <String>[];
  if (b == null) {
    forecast.add(
      mask
          ? 'Définis un budget pour obtenir une prévision.'
          : 'Au rythme actuel, le mois finira vers ${shortDt(s.projected)}.',
    );
  } else if (s.daysLeft <= 0) {
    forecast.add(
      mask
          ? 'Mois terminé à ${_pct(s.ratio)} du budget.'
          : 'Mois terminé : ${shortDt(s.spent)} pour un budget de ${shortDt(b.amount)}.',
    );
  } else {
    final projectedRatio = b.amount == 0 ? 0.0 : s.projected / b.amount;
    forecast.add(
      mask
          ? 'Au rythme actuel, le mois finira vers ${_pct(projectedRatio)} du budget.'
          : 'Au rythme actuel, le mois finira vers ${shortDt(s.projected)} '
                '(${_pct(projectedRatio)} du budget de ${shortDt(b.amount)}).',
    );
    final allowance = s.dailyAllowance;
    if (allowance != null && allowance > 0 && !mask) {
      forecast.add('Pour rester dans le budget : ${shortDt(allowance)} par jour pendant ${_days(s.daysLeft)}.');
    } else if (s.level == BudgetLevel.exceeded) {
      forecast.add('Encore ${_days(s.daysLeft)} : seulement l\'essentiel jusqu\'à la fin du mois.');
    } else if (mask) {
      forecast.add('Il reste ${_pct(1 - s.ratio)} du budget pour ${_days(s.daysLeft)}.');
    }
  }

  final increases = [
    for (final a in d.priceIncreases)
      mask
          ? '${displayLabel(a.label)} : +${(a.increase * 100).round()} %'
                '${a.storeName == null ? '' : ' (${a.storeName})'}'
          : '${displayLabel(a.label)} : +${(a.increase * 100).round()} % '
                '(${formatDt(a.lastPrice)} au lieu de ${formatDt(a.average)} en moyenne)'
                '${a.storeName == null ? '' : ' · ${a.storeName}'}',
  ];
  final shrinks = [
    for (final x in d.shrinks)
      '${displayLabel(x.name)} : ${x.sentence[0].toLowerCase()}${x.sentence.substring(1)}'
          '${mask ? '' : ' (${formatDt(x.before.price)} → ${formatDt(x.after.price)})'}',
  ];

  final tickets = [
    for (final t in [...d.tickets]..sort((a, b) => a.date.compareTo(b.date)))
      ReportTicket(
        title:
            '${formatDate(t.date)} · ${t.storeName ?? 'Magasin non précisé'}'
            '${t.lines.isEmpty ? '' : ' · ${plural(t.lines.length, 'article')}'}',
        value: dt(t.total),
        items: o.includeItems
            ? [
                for (final l in t.lines)
                  '${displayLabel(l.label)}${l.quantity == 1 ? '' : ' ×${formatQuantity(l.quantity, null)}'}'
                      '${mask ? '' : ' — ${formatDt(l.price)}'}',
              ]
            : const [],
      ),
  ];

  return ReportContent(
    title: 'Rapport budget · ${monthLabel(d.month)}',
    subtitle:
        'Généré le ${formatDate(d.generatedAt)} à '
        '${d.generatedAt.hour.toString().padLeft(2, '0')}h${d.generatedAt.minute.toString().padLeft(2, '0')}'
        ' · ${o.reason.label}',
    tone: toneOf(s),
    headline: b == null ? (mask ? '—' : shortDt(s.spent)) : _pct(s.ratio),
    status: status,
    metrics: [
      (label: 'Budget', value: b == null ? 'aucun' : dt(b.amount)),
      (label: 'Dépensé', value: dt(s.spent)),
      (
        label: 'Reste',
        value: b == null ? '—' : (mask ? _pct((1 - s.ratio).clamp(-9, 1).toDouble()) : formatDt(s.remaining)),
      ),
      (label: 'Utilisé', value: b == null ? '—' : _pct(s.ratio)),
    ],
    ratio: s.ratio,
    threshold: (b?.alertThreshold ?? 80) / 100,
    categories: categories,
    forecast: forecast,
    priceIncreases: increases,
    shrinks: shrinks,
    tickets: tickets,
    footer:
        'PanierMalin · rapport généré sur le téléphone, sans serveur'
        '${mask ? ' · montants masqués' : ''}',
    testBanner: o.reason == ReportReason.test ? 'RAPPORT TEST : données réelles du mois, envoi d\'essai' : null,
  );
}

/// Nom du fichier : « PanierMalin_rapport_2026-11.pdf ».
String reportFileName(DateTime month) => 'PanierMalin_rapport_${monthKey(month)}.pdf';

/// Réglages « Alerte budget par rapport PDF ».
class ReportSettings {
  const ReportSettings({
    this.enabled = false,
    this.contact,
    this.atThreshold = true,
    this.atBudget = true,
    this.maskAmounts = true,
    this.includeItems = false,
  });

  /// Proposer l'envoi du rapport au franchissement du seuil / du budget.
  final bool enabled;

  /// Proche à prévenir (avec son accord).
  final AlertContact? contact;
  final bool atThreshold;
  final bool atBudget;

  /// Activé par défaut : seuls les pourcentages sont partagés.
  final bool maskAmounts;
  final bool includeItems;

  ReportSettings copyWith({
    bool? enabled,
    AlertContact? contact,
    bool clearContact = false,
    bool? atThreshold,
    bool? atBudget,
    bool? maskAmounts,
    bool? includeItems,
  }) => ReportSettings(
    enabled: enabled ?? this.enabled,
    contact: clearContact ? null : (contact ?? this.contact),
    atThreshold: atThreshold ?? this.atThreshold,
    atBudget: atBudget ?? this.atBudget,
    maskAmounts: maskAmounts ?? this.maskAmounts,
    includeItems: includeItems ?? this.includeItems,
  );

  ReportOptions options(ReportReason reason) =>
      ReportOptions(maskAmounts: maskAmounts, includeItems: includeItems, reason: reason);
}

/// Ligne de l'historique des envois.
class ReportSendRecord {
  const ReportSendRecord({
    required this.date,
    required this.reason,
    required this.recipient,
    required this.month,
    this.confirmed = true,
  });

  final DateTime date;
  final ReportReason reason;

  /// « Maman », ou « Partage » pour un export sans destinataire choisi.
  final String recipient;
  final DateTime month;

  /// false : le système n'a pas pu confirmer que l'envoi est allé au bout.
  final bool confirmed;

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'reason': reason.name,
    'recipient': recipient,
    'month': monthKey(month),
    'confirmed': confirmed,
  };

  static ReportSendRecord? fromJson(Object? o) {
    if (o is! Map) return null;
    final date = DateTime.tryParse(o['date'] as String? ?? '');
    if (date == null) return null;
    return ReportSendRecord(
      date: date,
      reason: ReportReason.fromName(o['reason'] as String?),
      recipient: o['recipient'] as String? ?? '',
      month: parseMonthKey(o['month'] as String? ?? monthKey(date)),
      confirmed: o['confirmed'] as bool? ?? true,
    );
  }
}

/// Quel envoi proposer au franchissement [level] (une seule fois par seuil
/// et par mois : [alreadyOffered] est le niveau déjà proposé ce mois-ci).
ReportReason? reportReasonFor(BudgetLevel level, ReportSettings s, int alreadyOffered) {
  if (!s.enabled || s.contact == null) return null;
  if (level == BudgetLevel.exceeded && alreadyOffered < BudgetLevel.exceeded.index) {
    if (s.atBudget) return ReportReason.budget;
    // Budget non coché : le seuil, s'il n'a pas encore été proposé (saut direct au-delà de 100 %).
    if (s.atThreshold && alreadyOffered < BudgetLevel.threshold.index) return ReportReason.threshold;
    return null;
  }
  if (level == BudgetLevel.threshold && alreadyOffered < BudgetLevel.threshold.index && s.atThreshold) {
    return ReportReason.threshold;
  }
  return null;
}
