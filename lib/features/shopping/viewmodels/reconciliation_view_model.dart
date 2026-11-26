import 'package:flutter/foundation.dart';

import '../models/shopping_list.dart';
import '../services/shopping_service.dart';

/// Écran résumé du rapprochement ticket ↔ liste : achetés, à confirmer,
/// oubliés (à garder pour la prochaine liste) et achats hors liste.
class ReconciliationViewModel extends ChangeNotifier {
  ReconciliationViewModel(this.service, ReconciliationReport report)
      : listName = report.listName,
        purchased = [...report.purchased],
        pending = [...report.uncertain],
        forgotten = [...report.forgotten],
        unplanned = [...report.unplanned],
        kept = {if (report.carriedTo != null) for (final i in report.forgotten) i.id!},
        nextListName = report.carriedTo;

  final ShoppingService service;
  final String listName;
  final List<PurchasedMatch> purchased;
  final List<PendingMatch> pending;
  final List<ShoppingItem> forgotten;
  final List<String> unplanned;

  /// Oubliés reportés dans « Prochaines courses ».
  final Set<int> kept;
  String? nextListName;
  String? error;
  bool busy = false;

  /// « 6 achetés, 2 oubliés : lait, pain ».
  String get headline {
    final b = purchased.length;
    final f = forgotten.length;
    final bought = '$b acheté${b > 1 ? 's' : ''}';
    if (f == 0) return pending.isEmpty ? '$bought, aucun oubli' : bought;
    final names = forgotten.map((i) => i.label.toLowerCase()).join(', ');
    return '$bought, $f oublié${f > 1 ? 's' : ''} : $names';
  }

  bool get allKept => forgotten.isNotEmpty && forgotten.every((i) => kept.contains(i.id));

  /// Réponse « oui / non » à un rapprochement incertain.
  Future<void> answer(PendingMatch m, {required bool yes}) => _run(() async {
        await service.confirmMatch(m, accepted: yes);
        pending.remove(m);
        if (yes) {
          purchased.add(PurchasedMatch(itemId: m.itemId, itemLabel: m.itemLabel, lineLabel: m.lineLabel, score: m.score));
        } else {
          final item = await service.repository.item(m.itemId);
          if (item != null && !item.checked) forgotten.add(item);
          unplanned.add(m.lineLabel);
        }
      });

  Future<void> keep(ShoppingItem item) => _run(() async {
        final target = await service.keepForNextList([item]);
        nextListName = target.name;
        kept.add(item.id!);
      });

  Future<void> unkeep(ShoppingItem item) => _run(() async {
        await service.unkeep(item);
        kept.remove(item.id);
      });

  Future<void> keepAll() => _run(() async {
        final rest = [for (final i in forgotten) if (!kept.contains(i.id)) i];
        final target = await service.keepForNextList(rest);
        nextListName = target.name;
        kept.addAll(rest.map((i) => i.id!));
      });

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
