import '../data/recipe_repository.dart';

/// Réglages des capteurs de la gestion 3 (cahier des charges : « chaque
/// capteur peut être désactivé dans les réglages »).
class CookingSettings {
  const CookingSettings({
    this.proximityEnabled = true,
    this.voiceEnabled = true,
    this.continuousListening = false,
    this.readAloud = true,
    this.largeText = true,
    this.micExplained = false,
  });

  final bool proximityEnabled;
  final bool voiceEnabled;

  /// Relance l'écoute après chaque commande (sinon : appui sur le micro).
  final bool continuousListening;
  final bool readAloud;
  final bool largeText;

  /// L'explication de la permission micro a déjà été montrée.
  final bool micExplained;

  CookingSettings copyWith({
    bool? proximityEnabled,
    bool? voiceEnabled,
    bool? continuousListening,
    bool? readAloud,
    bool? largeText,
    bool? micExplained,
  }) =>
      CookingSettings(
        proximityEnabled: proximityEnabled ?? this.proximityEnabled,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        continuousListening: continuousListening ?? this.continuousListening,
        readAloud: readAloud ?? this.readAloud,
        largeText: largeText ?? this.largeText,
        micExplained: micExplained ?? this.micExplained,
      );
}

class CookingSettingsStore {
  CookingSettingsStore(this.repo);
  final RecipeRepository repo;

  static const _prefix = 'cooking.';

  Future<CookingSettings> load() async {
    Future<bool> b(String k, bool def) async {
      final v = await repo.getSetting('$_prefix$k');
      return v == null ? def : v == '1';
    }

    const d = CookingSettings();
    return CookingSettings(
      proximityEnabled: await b('proximity', d.proximityEnabled),
      voiceEnabled: await b('voice', d.voiceEnabled),
      continuousListening: await b('continuous', d.continuousListening),
      readAloud: await b('readAloud', d.readAloud),
      largeText: await b('largeText', d.largeText),
      micExplained: await b('micExplained', d.micExplained),
    );
  }

  Future<void> save(CookingSettings s) async {
    Future<void> w(String k, bool v) => repo.setSetting('$_prefix$k', v ? '1' : '0');
    await w('proximity', s.proximityEnabled);
    await w('voice', s.voiceEnabled);
    await w('continuous', s.continuousListening);
    await w('readAloud', s.readAloud);
    await w('largeText', s.largeText);
    await w('micExplained', s.micExplained);
  }
}
