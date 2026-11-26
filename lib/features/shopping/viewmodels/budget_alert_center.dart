import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logic/budget_forecast.dart';
import '../logic/budget_report.dart';
import '../models/dates.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';

/// Alerte affichée en bannière en haut de l'écran.
class BudgetAlert {
  const BudgetAlert(this.notice, {this.isTest = false, this.report});
  final BudgetNotice notice;

  /// « Envoyer le rapport à Maman » (alerte PDF activée, une fois par seuil).
  final ({AlertContact contact, ReportReason reason})? report;

  /// « Tester la vibration » des Réglages.
  final bool isTest;

  BudgetSnapshot get snapshot => notice.snapshot;
  BudgetLevel get level => notice.snapshot.level;

  String get title => isTest ? 'Test de l\'alerte de budget' : notice.title;

  /// « 86 % du budget utilisé (77,400 DT sur 90,000 DT) ».
  String get usage {
    final s = notice.snapshot;
    if (s.budget == null) return 'Aucun budget défini ce mois-ci.';
    return '${(s.ratio * 100).round()} % du budget utilisé (${formatDt(s.spent)} sur ${formatDt(s.budget!.amount)})';
  }

  /// « À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour. »
  String get sentence => budgetSentence(notice.snapshot);
}

/// Centre des alertes de budget, au niveau de l'application : à chaque
/// franchissement signalé par le service (une fois par franchissement), il
/// affiche la bannière avec la jauge et l'animation de vibration, ou une
/// notification locale si l'application est en arrière-plan.
class BudgetAlertCenter extends ChangeNotifier with WidgetsBindingObserver {
  BudgetAlertCenter(this.service, this.notifier, {this.visibleFor = const Duration(seconds: 12)}) {
    _sub = service.budgetAlerts.listen(_onNotice);
    WidgetsBinding.instance.addObserver(this);
    _state = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  final ShoppingService service;
  final LocalNotifier notifier;

  /// La bannière se referme seule après ce délai.
  final Duration visibleFor;

  BudgetAlert? current;

  /// Animation « téléphone qui vibre » à l'écran, pendant la vibration.
  bool vibrating = false;

  /// Alerte arrivée en arrière-plan, affichée au retour dans l'app.
  BudgetNotice? _pending;
  ({AlertContact contact, ReportReason reason})? _pendingReport;
  late final StreamSubscription<BudgetNotice> _sub;
  late AppLifecycleState _state;
  Timer? _vibrationTimer;
  Timer? _hideTimer;
  int _notificationId = 500;

  bool get inForeground => _state == AppLifecycleState.resumed;

  /// Palier franchi sans bannière (50 %) : petit cœur qui bat 5 s.
  BudgetNotice? heartNotice;
  Timer? _heartTimer;

  Future<void> _onNotice(BudgetNotice n) async {
    if (!n.showBanner) {
      // Palier 50 % : pas d'alerte, juste le cœur (rien en arrière-plan).
      if (n.heartbeat == null || !inForeground) return;
      heartNotice = n;
      _heartTimer?.cancel();
      _heartTimer = Timer(n.heartbeat!.total + const Duration(milliseconds: 1500), () {
        heartNotice = null;
        notifyListeners();
      });
      notifyListeners();
      return;
    }
    if (!inForeground) {
      ({AlertContact contact, ReportReason reason})? report;
      try {
        report = await service.reportOffer(n);
      } catch (_) {} // la notification part quand même
      _pending = n;
      _pendingReport = report;
      final a = BudgetAlert(n);
      final extra = report == null ? '' : ' Rapport prêt pour ${report.contact.firstName}.';
      await notifier.show(id: _notificationId++, title: a.title, body: '${a.usage}. ${a.sentence}$extra');
      return;
    }
    // La bannière d'abord (sans attendre la base), puis le bouton « Envoyer
    // le rapport à … » s'ajoute dès que la proposition est connue.
    final alert = BudgetAlert(n);
    _show(alert);
    try {
      final report = await service.reportOffer(n);
      if (report != null && identical(current, alert)) {
        current = BudgetAlert(n, report: report);
        _hideTimer?.cancel();
        _hideTimer = Timer(visibleFor * 2.5, dismiss); // plus de temps pour décider
        notifyListeners();
      }
    } catch (_) {} // la bannière reste, sans le bouton
  }

  /// [animate] : animation de vibration à l'écran. Par défaut, dès qu'une
  /// vibration a été demandée (vibreur activé), même si l'appareil ne peut
  /// pas vibrer (émulateur) : l'alerte reste visible pour tous.
  void _show(BudgetAlert alert, {bool? animate}) {
    current = alert;
    _vibrationTimer?.cancel();
    _hideTimer?.cancel();
    vibrating = animate ?? alert.notice.vibrationEnabled;
    if (vibrating) {
      // L'animation dure le temps du motif de vibration (+ un léger délai).
      final length = alert.notice.heartbeat?.total ?? vibrationDuration(alert.level);
      _vibrationTimer = Timer(length + const Duration(milliseconds: 400), () {
        vibrating = false;
        notifyListeners();
      });
    }
    // Plus de temps pour lire quand un envoi de rapport est proposé.
    _hideTimer = Timer(alert.report == null ? visibleFor : visibleFor * 2.5, dismiss);
    notifyListeners();
  }

  void dismiss() {
    _vibrationTimer?.cancel();
    _hideTimer?.cancel();
    current = null;
    vibrating = false;
    notifyListeners();
  }

  /// « Tester la vibration » : vibration courte + bannière de démonstration
  /// (visible même sur émulateur, qui ne vibre pas).
  Future<void> test({BudgetLevel level = BudgetLevel.threshold}) async {
    final settings = await service.settings();
    final vibrated = settings.vibration && await service.vibrator.alert(level);
    final snapshot = await service.snapshot(service.now);
    _show(BudgetAlert(
      BudgetNotice(
        snapshot: snapshot,
        isNewLevel: false,
        isNewForecast: false,
        previousRatio: snapshot.ratio,
        vibrated: vibrated,
        vibrationEnabled: settings.vibration,
      ),
      isTest: true,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    if (state == AppLifecycleState.resumed && _pending != null) {
      final n = _pending!;
      final report = _pendingReport;
      _pending = null;
      _pendingReport = null;
      // La vibration a déjà eu lieu : la bannière reste, sans animation.
      _show(BudgetAlert(BudgetNotice(
        snapshot: n.snapshot,
        isNewLevel: n.isNewLevel,
        isNewForecast: n.isNewForecast,
        previousRatio: n.previousRatio,
        vibrationEnabled: n.vibrationEnabled,
      ), report: report), animate: false);
    }
  }

  void dismissHeart() {
    _heartTimer?.cancel();
    heartNotice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    _sub.cancel();
    _vibrationTimer?.cancel();
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
