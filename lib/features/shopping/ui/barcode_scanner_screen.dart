import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/demo_products.dart';
import '../logic/product_price.dart';

/// Scanner de code-barres (mobile_scanner) : cadre animé, lampe de poche,
/// saisie manuelle en secours. Renvoie le code lu.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.demoMode = false});

  /// Raccourcis vers les trois codes de démonstration (soutenance).
  final bool demoMode;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
  );
  late final _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  bool _torch = false;
  bool _done = false;

  @override
  void dispose() {
    _line.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _found(String code) {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && isValidBarcode(v)) return _found(v);
    }
  }

  Future<void> _manual() async {
    final code = await showDialog<String>(context: context, builder: (_) => const ManualBarcodeDialog());
    if (code != null && mounted) _found(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Scanner un produit'),
          actions: [
            IconButton(
              tooltip: _torch ? 'Éteindre la lampe' : 'Lampe de poche',
              icon: Icon(_torch ? Icons.flashlight_off : Icons.flashlight_on),
              onPressed: () async {
                await _controller.toggleTorch();
                setState(() => _torch = !_torch);
              },
            ),
          ],
        ),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(error: error, onManual: _manual),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _line,
              builder: (_, _) => CustomPaint(painter: _FramePainter(_line.value)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                    'Placez le code-barres dans le cadre',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  if (widget.demoMode) ...[
                    Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                      for (final code in DemoProducts.codes)
                        ActionChip(
                          avatar: const Icon(Icons.science_outlined, size: 18),
                          label: Text('Démo : ${DemoProducts.labels[code]}'),
                          onPressed: () => _found(code),
                        ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: _manual,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Saisir le code à la main'),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );
}

/// Cadre de visée : fond assombri, coins, ligne de balayage animée.
class _FramePainter extends CustomPainter {
  _FramePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.8;
    final h = w * 0.55;
    final r = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: w, height: h);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr)),
      Paint()..color = Colors.black54,
    );
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(l * dx, 0), corner);
      canvas.drawLine(c, c + Offset(0, l * dy), corner);
    }
    final y = r.top + 10 + (r.height - 20) * t;
    canvas.drawLine(
      Offset(r.left + 12, y),
      Offset(r.right - 12, y),
      Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.t != t;
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.onManual});
  final MobileScannerException error;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 12),
            Text(
              denied ? 'Accès à la caméra refusé' : 'Caméra indisponible',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Autorisez la caméra dans les réglages du téléphone, ou saisissez le code-barres.'
                  : 'Le scanner n\'a pas pu démarrer. Saisissez le code-barres à la main.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onManual, icon: const Icon(Icons.keyboard), label: const Text('Saisir le code')),
          ]),
        ),
      ),
    );
  }
}

/// Saisie manuelle du code (8 à 14 chiffres, clé de contrôle vérifiée).
class ManualBarcodeDialog extends StatefulWidget {
  const ManualBarcodeDialog({super.key});

  @override
  State<ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<ManualBarcodeDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _c.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{8,14}$').hasMatch(v)) {
      setState(() => _error = 'Entre 8 et 14 chiffres.');
    } else if (!isValidBarcode(v)) {
      setState(() => _error = 'Clé de contrôle incorrecte : vérifiez le dernier chiffre.');
    } else {
      Navigator.pop(context, v);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Code-barres'),
        content: TextField(
          controller: _c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Chiffres sous le code-barres',
            hintText: '3017620422003',
            errorText: _error,
          ),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _ok, child: const Text('Valider')),
        ],
      );
}
