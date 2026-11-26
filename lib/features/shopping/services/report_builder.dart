import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/budget_report.dart';

/// Polices intégrées au PDF (accents, guillemets français) : Roboto, livrée
/// avec l'application, aucun téléchargement.
class ReportFonts {
  const ReportFonts(this.regular, this.bold);
  final pw.Font regular;
  final pw.Font bold;

  static Future<ReportFonts> load() async => ReportFonts(
    pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
  );

  /// Depuis des octets (tests).
  factory ReportFonts.fromBytes(ByteData regular, ByteData bold) =>
      ReportFonts(pw.Font.ttf(regular), pw.Font.ttf(bold));
}

/// Met en page [ReportContent] en PDF A4 : vert = bon, orange = attention,
/// rouge = dépassement ; logo PanierMalin dessiné (vectoriel).
class ReportBuilder {
  const ReportBuilder(this.fonts);
  final ReportFonts fonts;

  static const green = PdfColor.fromInt(0xFF2E7D32);
  static const orange = PdfColor.fromInt(0xFFE65100);
  static const red = PdfColor.fromInt(0xFFC62828);
  static const grey = PdfColor.fromInt(0xFF616161);
  static const light = PdfColor.fromInt(0xFFF1F4EF);

  static PdfColor toneColor(ReportTone t) => switch (t) {
    ReportTone.good => green,
    ReportTone.caution => orange,
    ReportTone.over => red,
  };

  Future<Uint8List> build(ReportContent c) {
    final color = toneColor(c.tone);
    final doc = pw.Document(
      title: c.title,
      author: 'PanierMalin',
      creator: 'PanierMalin',
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _smallHeader(c),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '${c.footer} · page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: grey),
          ),
        ),
        build: (ctx) => [
          _header(c),
          if (c.testBanner != null) ...[pw.SizedBox(height: 8), _banner(c.testBanner!, orange)],
          pw.SizedBox(height: 14),
          _statusBand(c, color),
          pw.SizedBox(height: 12),
          _metrics(c, color),
          pw.SizedBox(height: 10),
          _gauge(c, color),
          _section('Dépenses par catégorie'),
          if (c.categories.isEmpty) _muted('Aucune dépense enregistrée ce mois-ci.') else _categoryChart(c, color),
          _section('Prévision de fin de mois'),
          for (final f in c.forecast) _bullet(f),
          _section('Hausses de prix du mois'),
          if (c.priceIncreases.isEmpty) _muted('Aucune hausse détectée.'),
          for (final p in c.priceIncreases) _bullet(p, color: orange),
          _section('Shrinkflation du mois'),
          if (c.shrinks.isEmpty) _muted('Aucun produit devenu plus petit.'),
          for (final s in c.shrinks) _bullet(s, color: orange),
          _section('Tickets du mois'),
          if (c.tickets.isEmpty) _muted('Aucun ticket ce mois-ci.'),
          for (final t in c.tickets) _ticket(t),
        ],
      ),
    );
    return doc.save();
  }

  // ------------------------------------------------------------ Blocs

  /// Logo : tomate (la mascotte Malin) dans un cercle vert, et le nom.
  pw.Widget _logo({double size = 34}) => pw.Row(
    children: [
      pw.SizedBox(
        width: size,
        height: size,
        child: pw.CustomPaint(
          size: PdfPoint(size, size),
          painter: (canvas, s) {
            final r = s.x / 2;
            canvas
              ..setFillColor(green)
              ..drawEllipse(r, r, r, r)
              ..fillPath()
              ..setFillColor(const PdfColor.fromInt(0xFFE53935))
              ..drawEllipse(r, r * 0.88, r * 0.62, r * 0.56)
              ..fillPath()
              // Feuilles (repère PDF : y vers le haut).
              ..setFillColor(const PdfColor.fromInt(0xFF66BB6A))
              ..moveTo(r, r * 1.38)
              ..lineTo(r - r * 0.34, r * 1.62)
              ..lineTo(r, r * 1.48)
              ..lineTo(r + r * 0.34, r * 1.62)
              ..closePath()
              ..fillPath()
              // Sourire.
              ..setStrokeColor(PdfColors.white)
              ..setLineWidth(r * 0.08)
              ..moveTo(r - r * 0.26, r * 0.78)
              ..curveTo(r - r * 0.1, r * 0.58, r + r * 0.1, r * 0.58, r + r * 0.26, r * 0.78)
              ..strokePath();
          },
        ),
      ),
      pw.SizedBox(width: 8),
      pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: 'Panier',
              style: pw.TextStyle(fontSize: size * 0.55, color: green, fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(
              text: 'Malin',
              style: pw.TextStyle(fontSize: size * 0.55, color: red, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    ],
  );

  pw.Widget _header(ReportContent c) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _logo(),
      pw.Spacer(),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(c.title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(c.subtitle, style: const pw.TextStyle(fontSize: 9, color: grey)),
        ],
      ),
    ],
  );

  pw.Widget _smallHeader(ReportContent c) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      children: [
        _logo(size: 18),
        pw.Spacer(),
        pw.Text(c.title, style: const pw.TextStyle(fontSize: 9, color: grey)),
      ],
    ),
  );

  pw.Widget _banner(String text, PdfColor color) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: pw.BoxDecoration(
      color: PdfColor(color.red, color.green, color.blue, 0.12),
      border: pw.Border.all(color: color),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold, fontSize: 10),
    ),
  );

  pw.Widget _statusBand(ReportContent c, PdfColor color) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(
      children: [
        pw.Text(
          c.headline,
          style: pw.TextStyle(fontSize: 34, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Text(
            c.status,
            style: pw.TextStyle(fontSize: 14, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  pw.Widget _metrics(ReportContent c, PdfColor color) => pw.Row(
    children: [
      for (var i = 0; i < c.metrics.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(color: light, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(c.metrics[i].label, style: const pw.TextStyle(fontSize: 9, color: grey)),
                pw.SizedBox(height: 2),
                pw.Text(
                  c.metrics[i].value,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: c.metrics[i].label == 'Utilisé' ? color : PdfColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  /// Jauge horizontale : part utilisée, repère du seuil.
  pw.Widget _gauge(ReportContent c, PdfColor color) => pw.LayoutBuilder(
    builder: (ctx, constraints) {
      final w = constraints?.maxWidth ?? 500;
      final used = c.ratio.clamp(0.0, 1.0);
      return pw.Stack(
        children: [
          pw.Container(
            height: 10,
            width: w,
            decoration: pw.BoxDecoration(color: light, borderRadius: pw.BorderRadius.circular(5)),
          ),
          pw.Container(
            height: 10,
            width: w * used,
            decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(5)),
          ),
          pw.Positioned(
            left: w * c.threshold.clamp(0.0, 1.0) - 1,
            top: 0,
            child: pw.Container(width: 2, height: 10, color: PdfColors.black),
          ),
        ],
      );
    },
  );

  pw.Widget _section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: green),
    ),
  );

  pw.Widget _muted(String t) => pw.Text(t, style: const pw.TextStyle(fontSize: 10, color: grey));

  pw.Widget _bullet(String t, {PdfColor color = green}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 5,
          height: 5,
          margin: const pw.EdgeInsets.only(top: 4, right: 6),
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(child: pw.Text(t, style: const pw.TextStyle(fontSize: 10))),
      ],
    ),
  );

  /// Graphique en barres horizontales, la plus grosse catégorie en premier.
  pw.Widget _categoryChart(ReportContent c, PdfColor color) {
    final max = c.categories.map((x) => x.share).fold(0.0, (a, b) => a > b ? a : b);
    return pw.Column(
      children: [
        for (final x in c.categories)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 110, child: pw.Text(x.name, style: const pw.TextStyle(fontSize: 9))),
                pw.Expanded(
                  child: pw.LayoutBuilder(
                    builder: (ctx, cs) {
                      final w = (cs?.maxWidth ?? 200) * (max == 0 ? 0 : x.share / max);
                      return pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          height: 9,
                          width: w < 2 ? 2 : w,
                          decoration: pw.BoxDecoration(color: green, borderRadius: pw.BorderRadius.circular(3)),
                        ),
                      );
                    },
                  ),
                ),
                pw.SizedBox(
                  width: 100,
                  child: pw.Text(x.value, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _ticket(ReportTicket t) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(color: light, borderRadius: pw.BorderRadius.circular(6)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(t.title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(t.value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        for (final i in t.items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10, top: 2),
            child: pw.Text(i, style: const pw.TextStyle(fontSize: 9, color: grey)),
          ),
      ],
    ),
  );
}
