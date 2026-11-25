import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/shopping_service.dart';
import '../viewmodels/budget_alert_center.dart';
import 'widgets.dart';

/// Réglages de la gestion 5 : chaque capteur peut être désactivé, et le
/// compte Open Food Facts sert au partage facultatif des prix.
class ShoppingSettingsScreen extends StatefulWidget {
  const ShoppingSettingsScreen({super.key});

  @override
  State<ShoppingSettingsScreen> createState() => _ShoppingSettingsScreenState();
}

class _ShoppingSettingsScreenState extends State<ShoppingSettingsScreen> {
  ShoppingSettings? _settings;
  bool _account = false;

  ShoppingService get _service => context.read<ShoppingService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _service.settings();
    final a = await _service.hasOpenPricesAccount();
    if (mounted) {
      setState(() {
        _settings = s;
        _account = a;
      });
    }
  }

  Future<void> _save(ShoppingSettings s) async {
    setState(() => _settings = s);
    await _service.saveSettings(s);
  }

  Future<void> _login() async {
    final creds = await showDialog<(String, String)>(context: context, builder: (_) => const _LoginDialog());
    if (creds != null) {
      try {
        await _service.openPricesLogin(creds.$1, creds.$2);
        if (mounted) showSnack(context, 'Connecté à Open Prices.');
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages — Courses')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              const ListTile(title: Text('Capteurs')),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibreur'),
                subtitle: const Text('Vibre quand le seuil d\'alerte puis le budget sont atteints.'),
                value: s.vibration,
                onChanged: (v) => _save(s.copyWith(vibration: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    // Vibration courte + bannière animée (visible même sur émulateur).
                    onPressed: s.vibration ? () => context.read<BudgetAlertCenter>().test() : null,
                    icon: const Icon(Icons.vibration),
                    label: const Text('Tester la vibration'),
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Alertes de budget'),
                subtitle: const Text('Bannière (et notification si l\'app est en arrière-plan) quand le seuil '
                    'puis le budget sont franchis, une seule fois par franchissement.'),
                value: s.budgetAlerts,
                onChanged: (v) => _save(s.copyWith(budgetAlerts: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.document_scanner_outlined),
                title: const Text('Lecture automatique des tickets'),
                subtitle: const Text('Caméra + reconnaissance de texte. Désactivée : la photo est jointe, '
                    'les lignes sont saisies à la main.'),
                value: s.ocr,
                onChanged: (v) => _save(s.copyWith(ocr: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screen_rotation_alt),
                title: const Text('Secouer pour annuler'),
                subtitle: const Text('Dans une liste, secouer le téléphone annule la dernière action '
                    '(cocher, supprimer, ajouter un article). Accéléromètre.'),
                value: s.shakeToUndo,
                onChanged: (v) => _save(s.copyWith(shakeToUndo: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.mic_none),
                title: const Text('Ajout vocal'),
                subtitle: const Text('Bouton micro dans une liste : « ajoute lait, pain et 6 œufs ». '
                    'Microphone et reconnaissance vocale du téléphone.'),
                value: s.voiceInput,
                onChanged: (v) => _save(s.copyWith(voiceInput: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.fact_check_outlined),
                title: const Text('Rapprochement automatique'),
                subtitle: const Text('Après un ticket, les articles de la liste en cours achetés se cochent seuls.'),
                value: s.autoReconcile,
                onChanged: (v) => _save(s.copyWith(autoReconcile: v)),
              ),
              if (s.autoReconcile)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Ressemblance exigée pour cocher sans demander : ${(s.matchThreshold * 100).round()} %',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Slider(
                      value: s.matchThreshold.clamp(0.6, 0.9).toDouble(),
                      min: 0.6,
                      max: 0.9,
                      divisions: 6,
                      label: '${(s.matchThreshold * 100).round()} %',
                      onChanged: (v) => setState(() => _settings = s.copyWith(matchThreshold: v)),
                      onChangeEnd: (v) => _save(s.copyWith(matchThreshold: v)),
                    ),
                    Text(
                      'Plus bas : plus d\'articles cochés seuls. Plus haut : plus de questions « oui / non ».',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ]),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.shopping_basket_outlined),
                title: const Text('Panier type par magasin'),
                subtitle: const Text('Coût de vos achats habituels dans chaque magasin (accueil Courses et Prix).'),
                value: s.habitualBasket,
                onChanged: (v) => _save(s.copyWith(habitualBasket: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.event_available_outlined),
                title: const Text('Meilleur moment pour acheter'),
                subtitle: const Text('Moment du mois, jour et magasin où un produit est moins cher '
                    '(à partir de 6 achats), avec rappel.'),
                value: s.bestTime,
                onChanged: (v) => _save(s.copyWith(bestTime: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.history),
                title: const Text('Reporter les oubliés'),
                subtitle: const Text('Après un ticket, les articles de la liste non achetés sont ajoutés '
                    'automatiquement à « Prochaines courses ».'),
                value: s.carryForgotten,
                onChanged: (v) => _save(s.copyWith(carryForgotten: v)),
              ),
              const Divider(),
              const ListTile(title: Text('Open Prices')),
              SwitchListTile(
                secondary: const Icon(Icons.public),
                title: const Text('Comparer avec Open Prices'),
                subtitle: const Text('Interroge l\'API avec le code-barres du produit (réseau requis).'),
                value: s.openPrices,
                onChanged: (v) => _save(s.copyWith(openPrices: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('Partager mes prix'),
                subtitle: const Text('Bouton « Contribuer mon prix » sur la fiche produit (facultatif, '
                    'compte Open Food Facts et photo de preuve).'),
                value: s.sharePrices,
                onChanged: (v) => _save(s.copyWith(sharePrices: v)),
              ),
              if (s.sharePrices)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  leading: Icon(_account ? Icons.verified_user : Icons.person_outline),
                  title: Text(_account ? 'Compte connecté (partage possible)' : 'Se connecter à Open Food Facts'),
                  subtitle: Text(_account ? 'Touchez pour vous déconnecter.' : 'Nécessaire pour partager un prix.'),
                  onTap: _account
                      ? () async {
                          await _service.openPricesLogout();
                          await _load();
                        }
                      : _login,
                ),
              SwitchListTile(
                secondary: const Icon(Icons.science_outlined),
                title: const Text('Mode démo'),
                subtitle: const Text('3 codes-barres préchargés (Nutella, Coca-Cola, Spaghetti) qui fonctionnent '
                    'sans réseau, avec des prix fictifs.'),
                value: s.demoProducts,
                onChanged: (v) => _save(s.copyWith(demoProducts: v)),
              ),
            ]),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Compte Open Food Facts'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Nécessaire uniquement pour partager vos prix. Le mot de passe n\'est pas conservé ; '
                'seul le jeton est rangé dans le stockage sécurisé du téléphone.'),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Identifiant')),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_user.text, _pass.text)),
            child: const Text('Se connecter'),
          ),
        ],
      );
}
