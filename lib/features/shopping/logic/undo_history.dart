/// Historique des actions sur les articles d'une liste, pour « Secouer pour
/// annuler » : une pile d'annulation (au plus [ItemUndoHistory.maxSize] actions)
/// et une pile de rétablissement.
library;

import '../models/shopping_list.dart';

enum ItemActionType { toggle, delete, add }

/// Une action annulable : son type, l'article concerné et son état avant /
/// après l'action.
class ItemAction {
  ItemAction({required this.type, this.before, this.after});

  final ItemActionType type;

  /// État avant l'action (null pour l'ajout d'un nouvel article).
  ShoppingItem? before;

  /// État après l'action (null pour une suppression).
  ShoppingItem? after;

  ShoppingItem get item => (after ?? before)!;

  /// Ajout qui a complété un article existant (quantités fusionnées).
  bool get isMerge => type == ItemActionType.add && before != null;

  /// Phrase décrivant l'effet de l'annulation : « lait décoché ».
  String get undoDescription {
    final l = item.label.toLowerCase();
    return switch (type) {
      ItemActionType.toggle => (after?.checked ?? false) ? '$l décoché' : '$l coché',
      ItemActionType.delete => '$l remis dans la liste',
      ItemActionType.add => isMerge ? 'quantité de $l rétablie' : '$l retiré de la liste',
    };
  }

  /// Phrase décrivant l'effet du rétablissement.
  String get redoDescription {
    final l = item.label.toLowerCase();
    return switch (type) {
      ItemActionType.toggle => (after?.checked ?? false) ? '$l coché' : '$l décoché',
      ItemActionType.delete => '$l supprimé',
      ItemActionType.add => isMerge ? 'quantité de $l modifiée' : '$l ajouté',
    };
  }
}

class ItemUndoHistory {
  static const maxSize = 10;

  final List<ItemAction> _undo = [];
  final List<ItemAction> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get length => _undo.length;

  /// Nouvelle action : elle rend impossible le rétablissement des précédentes.
  void record(ItemAction a) {
    _undo.add(a);
    if (_undo.length > maxSize) _undo.removeAt(0);
    _redo.clear();
  }

  /// Retire la dernière action à annuler (l'appelant l'annule puis appelle [undone]).
  ItemAction? popUndo() => _undo.isEmpty ? null : _undo.removeLast();
  void undone(ItemAction a) => _redo.add(a);

  ItemAction? popRedo() => _redo.isEmpty ? null : _redo.removeLast();
  void redone(ItemAction a) {
    _undo.add(a);
    if (_undo.length > maxSize) _undo.removeAt(0);
  }

  ItemAction? get lastUndoable => _undo.isEmpty ? null : _undo.last;

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
