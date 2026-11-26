import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/live_receipt_parser.dart' show LiveOcrRow;
import '../logic/shelf_label_parser.dart';
import '../models/dates.dart';
import '../models/live_cart.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import 'widgets.dart';

/// Étiquettes de démonstration (émulateur sans vraie étiquette à filmer).
const demoShelfLabels = <String, List<(String, double)>>{
  // Plus cher que mon dernier achat (14,200 DT) : bulle rouge.
  'Nutella 15,500': [('NUTELLA 400G', 0.04), ('PRIX 15,500', 0.10), ('LE KG 38,750', 0.02), ('3017620422003', 0.02)],
  // Moins cher que d'habitude : bulle verte.
  'Café 6 500': [('PROMO', 0.03), ('CAFE MOULU 250G', 0.04), ('6 500', 0.12)],
};

/// Scan d'étiquette en rayon : OCR continu, prix et nom (code-barres en
/// priorité), puis bulle « moins cher que d'habitude » / « plus cher que ton
/// dernier achat » / « déjà payé », et comparaison Open Prices.
class ShelfLabelScanScreen extends StatefulWidget {
  const ShelfLabelScanScreen({super.key, this.demoMode = false});
  final bool demoMode;

  @override
  State<ShelfLabelScanScreen> createState() => _ShelfLabelScanScreenState();
}

enum _Phase { starting, scanning, error }

class _ShelfLabelScanScreenState extends State<ShelfLabelScanScreen> with WidgetsBindingObserver {
  late final LiveReceiptCamera _camera = context.read<LiveCameraFactory>()();
  late final ProductScanService _scan = context.read<ProductScanService>();
  _Phase _phase = _Phase.starting;
  LiveCameraError? _error;
  StreamSubscription<LiveFrame>? _sub;
  ShelfLabelTracker _tracker = ShelfLabelTracker();
  ShelfLookup? _result;
  bool _looking = false;
  int _darkFrames = 0;
  DateTime _startedAt = DateTime.now();
  Rect? _priceBox;

  bool get _tooDark => _darkFrames >= 2;
  bool get _illegible =>
      _result == null && _tracker.framesWithText >= 3 && DateTime.now().difference(_startedAt).inSeconds >= 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _error = null;
    });
    try {
      await _camera.open();
    } on LiveCameraException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.error;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.scanning;
      _startedAt = DateTime.now();
    });
    _sub = _camera.frames().listen(_onFrame, onError: (Object _) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = LiveCameraError.failed;
        });
      }
    });
  }

  void _onFrame(LiveFrame f) {
    if (_result != null || _looking) return; // résultat affiché : on ne lit plus
    final dark = f.brightness != null && f.brightness! < 0.2;
    _darkFrames = dark ? _darkFrames + 1 : 0;
    _read(f.rows);
  }

  void _read(List<LiveOcrRow> rows) {
    final r = parseShelfLabel(rows);
    _tracker.add(r, hadText: rows.isNotEmpty);
    setState(() => _priceBox = r.priceBox);
    final confirmed = _tracker.confirmed;
    if (confirmed != null) _lookup(confirmed);
  }

  Future<void> _lookup(ShelfLabelReading r) async {
    if (_looking) return;
    _looking = true;
    HapticFeedback.mediumImpact();
    final res = await _scan.shelfLookup(r);
    if (!mounted) return;
    setState(() {
      _result = res;
      _looking = false;
    });
  }

  void _again() => setState(() {
        _tracker = ShelfLabelTracker();
        _result = null;
        _priceBox = null;
        _startedAt = DateTime.now();
      });

  Future<void> _manual() async {
    final r = await showDialog<ShelfLabelReading>(context: context, builder: (_) => const _ManualLabelDialog());
    if (r != null && mounted) await _lookup(r);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _sub?.cancel();
      _sub = null;
      _camera.close();
    } else if (state == AppLifecycleState.resumed && _phase == _Phase.scanning && _sub == null) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _sub?.cancel();
    _camera.close(); // caméra libérée
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Étiquette en rayon'),
          actions: [
            IconButton(tooltip: 'Saisir à la main', icon: const Icon(Icons.keyboard), onPressed: _manual),
          ],
        ),
        body: _phase == _Phase.error ? _errorView() : _scanView(),
      );

  Widget _scanView() {
    final hint = _tooDark
        ? 'Trop sombre : rapproche-toi / ajoute de la lumière'
        : _illegible
            ? 'Prix illisible : rapproche-toi de l\'étiquette, bien en face'
            : _looking
                ? 'Recherche dans tes achats…'
                : 'Vise l\'étiquette de prix';
    return Column(children: [
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          if (_phase == _Phase.scanning)
            _camera.buildPreview(LayoutBuilder(
              builder: (_, c) => Stack(children: [
                if (_priceBox != null)
                  Positioned(
                    left: _priceBox!.left * c.maxWidth - 6,
                    top: _priceBox!.top * c.maxHeight - 4,
                    width: _priceBox!.width * c.maxWidth + 12,
                    height: _priceBox!.height * c.maxHeight + 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.greenAccent, width: 3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
              ]),
            ))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          const IgnorePointer(child: CustomPaint(painter: _LabelFramePainter())),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _tooDark || _illegible ? Colors.orange.shade800 : Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(hint, style: const TextStyle(color: Colors.white)),
            ),
          ),
          if (_result == null && (_illegible || widget.demoMode))
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                  if (widget.demoMode)
                    for (final e in demoShelfLabels.entries)
                      ActionChip(
                        avatar: const Icon(Icons.science_outlined, size: 18),
                        label: Text('Démo : ${e.key}'),
                        onPressed: () {
                          // Deux « images » identiques : la lecture se confirme comme en vrai.
                          final rows = [
                            for (final (i, (t, h)) in e.value.indexed)
                              LiveOcrRow(t, box: Rect.fromLTWH(0.2, 0.25 + i * 0.1, 0.6, h)),
                          ];
                          _read(rows);
                          _read(rows);
                        },
                      ),
                  FilledButton.tonalIcon(
                    onPressed: _manual,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Saisir le prix'),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      if (_result != null) _ResultPanel(result: _result!, onAgain: _again),
    ]);
  }

  Widget _errorView() {
    final denied = _error == LiveCameraError.permissionDenied || _error == LiveCameraError.permissionPermanentlyDenied;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.no_photography_outlined, size: 56, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(denied ? 'Accès à la caméra refusé' : 'Caméra indisponible',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tu peux saisir le prix de l\'étiquette à la main pour comparer quand même.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_error == LiveCameraError.permissionPermanentlyDenied)
            FilledButton.icon(
              onPressed: _camera.openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Ouvrir les réglages'),
            ),
          if (_error != LiveCameraError.noCamera)
            TextButton.icon(onPressed: _start, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          FilledButton.tonalIcon(onPressed: _manual, icon: const Icon(Icons.keyboard), label: const Text('Saisir le prix')),
          if (_result != null) _ResultPanel(result: _result!, onAgain: _again),
        ]),
      ),
    );
  }
}

class _LabelFramePainter extends CustomPainter {
  const _LabelFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45), width: size.width * 0.8, height: size.height * 0.45);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr)),
      Paint()..color = Colors.black45,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LabelFramePainter old) => false;
}

/// Résultat : nom, prix, bulle colorée, communauté, actions.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result, required this.onAgain});
  final ShelfLookup result;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final theme = Theme.of(context);
    final price = r.reading.price!;
    final (color, icon) = switch (r.verdict.kind) {
      ShelfVerdictKind.cheaper => (Colors.green.shade700, Icons.thumb_up_alt_outlined),
      ShelfVerdictKind.dearer => (Colors.red.shade700, Icons.trending_up),
      ShelfVerdictKind.usual => (theme.colorScheme.primary, Icons.history),
      ShelfVerdictKind.unknown => (theme.colorScheme.outline, Icons.help_outline),
    };
    final diff = r.communityDiff;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.name, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(
                '${formatDt(price)}${r.reading.priceIsPerKilo ? '/kg' : ''}',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ]),
            if (r.reading.barcode != null) Text('Code ${r.reading.barcode}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            // Bulle : verdict par rapport à mes achats.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.verdict.text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ]),
            ),
            if (r.communityMean != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Communauté : ${formatDt(r.communityMean!)} en moyenne (${plural(r.communityCount, 'prix', 'prix')})'
                  '${diff == null ? '' : ' · ${diff >= 0 ? '+' : ''}${(diff * 100).round()} %'}',
                  style: TextStyle(color: diff != null && diff > 0.05 ? Colors.red.shade700 : null),
                ),
              )
            else if (r.communityNote != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.communityNote!, style: theme.textTheme.bodySmall)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(
                onPressed: () async {
                  final list = await context.read<ProductScanService>().addToList(r.name);
                  if (context.mounted) showSnack(context, '« ${r.name} » ajouté à « $list ».');
                },
                icon: const Icon(Icons.playlist_add),
                label: const Text('Ajouter à ma liste'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final cart = await context.read<ShoppingService>().addToLiveCart(LiveCartItem(
                        label: r.name,
                        unitPrice: price,
                        barcode: r.reading.barcode,
                        perKilo: r.reading.priceIsPerKilo,
                      ));
                  final total = cart.fold(0.0, (s, i) => s + i.total);
                  if (context.mounted) {
                    showSnack(context, 'Panier en direct : ${plural(cart.length, 'article')}, ${formatDt(total)}.');
                  }
                },
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Ajouter au panier en direct'),
              ),
              TextButton.icon(onPressed: onAgain, icon: const Icon(Icons.refresh), label: const Text('Autre étiquette')),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Saisie manuelle : nom et prix lus sur l'étiquette.
class _ManualLabelDialog extends StatefulWidget {
  const _ManualLabelDialog();

  @override
  State<_ManualLabelDialog> createState() => _ManualLabelDialogState();
}

class _ManualLabelDialogState extends State<_ManualLabelDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Étiquette'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Produit')),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Prix', suffixText: 'DT', errorText: _error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final p = parseNumber(_price.text);
              if (_name.text.trim().isEmpty || p == null || p <= 0) {
                setState(() => _error = 'Nom et prix nécessaires.');
                return;
              }
              Navigator.pop(context, ShelfLabelReading(name: _name.text.trim(), price: p));
            },
            child: const Text('Comparer'),
          ),
        ],
      );
}
