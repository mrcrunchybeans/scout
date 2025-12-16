import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:convert';
import 'web_anchor_stub.dart' if (dart.library.html) 'web_anchor_impl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

/// Font pack for crisp PDF rendering
class _FontPack {
  final pw.Font regular;
  final pw.Font bold;
  const _FontPack(this.regular, this.bold);
}

/// Cache for loaded fonts
_FontPack? _fontPackCache;

/// Load Inter fonts for crisp printing
Future<_FontPack> _loadFonts() async {
  if (_fontPackCache != null) return _fontPackCache!;
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
  return _fontPackCache = _FontPack(regular, bold);
}

/// Avery 5160 label sheet specifications with calibration support
class Avery5160Spec {
  static const int columns = 3;
  static const int rows = 10;
  static const int labelsPerPage = columns * rows;

  final double pageWidth = 8.5 * 72; // 8.5" in points
  final double pageHeight = 11.0 * 72; // 11" in points
  final double topMargin = 0.5 * 72; // 0.5" top margin
  final double leftMargin = 0.1875 * 72; // 0.1875" left margin (correct)
  final double horizontalGap = 0.125 * 72; // 0.125" horizontal gap
  final double verticalGap = 0.0 * 72; // No vertical gap for 5160
  final double labelWidth = 2.625 * 72; // 2-5/8" in points
  final double labelHeight = 1.0 * 72; // 1" in points

  // Global calibration nudges (points) - adjust ±2-6 if printer drifts
  final double nudgeX;
  final double nudgeY;

  const Avery5160Spec({this.nudgeX = 0, this.nudgeY = 0});

  /// Get rectangle for a specific cell index (0-29)
  PdfRect cellRect(int index) {
    final row = index ~/ columns;
    final col = index % columns;
    final x = leftMargin + col * (labelWidth + horizontalGap) + nudgeX;
    final y = topMargin + row * (labelHeight + verticalGap) + nudgeY;
    return PdfRect(x, y, labelWidth, labelHeight);
  }
}

/// Configuration class for label layout and styling
class LabelTemplate {
  // Layout dimensions
  final double labelWidth;
  final double labelHeight;
  final double logoHeight;
  final double qrCodeSize;
  final double padding;
  final double textSpacing;

  // Font sizes
  final double lotIdFontSize;
  final double itemNameFontSize;
  final double expirationFontSize;
  final double logoTextFontSize;

  // Colors
  final PdfColor borderColor;
  final PdfColor textColor;
  final PdfColor expirationColor;
  final PdfColor logoTextColor;

  // Layout ratios (kept for future flexibility)
  final int textFlex;
  final int qrFlex;

  // Legacy flags (kept for config compatibility, ignored for rendering)
  final bool useQr;
  final bool showLinearBarcode;
  final bool showExpirationPill;

  // Misc
  final double quietZone;
  final double cornerRadius;
  final double dividerThickness;
  final pw.Font? fontRegular;
  final pw.Font? fontBold;
  // Optional custom design stored as fractional coords per element
  // Example: { 'lotId': {'x':0.05,'y':0.05,'w':0.6,'h':0.2}, 'qr': {...} }
  // Optional design - per-element map. Each element is a map with keys x,y,w,h (doubles)
  // and optional style keys like 'fontSize', 'bold', 'align'.
  final Map<String, dynamic>? design;

  const LabelTemplate({
    this.labelWidth = 2.625 * 72,
    this.labelHeight = 1.0 * 72,
    this.logoHeight = 12,
    this.qrCodeSize = 32,
    this.padding = 4,
    this.textSpacing = 1,
    this.lotIdFontSize = 12,
    this.itemNameFontSize = 6,
    this.expirationFontSize = 5,
    this.logoTextFontSize = 6,
    this.borderColor = PdfColors.grey300,
    this.textColor = PdfColors.black,
    this.expirationColor = PdfColors.grey700,
    this.logoTextColor = PdfColors.blue,
    this.textFlex = 3,
    this.qrFlex = 1,
    this.useQr = true,
    this.showLinearBarcode = false,
    this.showExpirationPill = true,
    this.quietZone = 2,
    this.cornerRadius = 2,
    this.dividerThickness = 0.3,
    this.fontRegular,
    this.fontBold,
    this.design,
  });

  factory LabelTemplate.compact() {
    return const LabelTemplate(
      logoHeight: 8,
      qrCodeSize: 24,
      padding: 2,
      lotIdFontSize: 10,
      itemNameFontSize: 5,
      expirationFontSize: 4,
      logoTextFontSize: 5,
    );
  }

  factory LabelTemplate.spacious() {
    return const LabelTemplate(
      logoHeight: 16,
      qrCodeSize: 40,
      padding: 6,
      lotIdFontSize: 14,
      itemNameFontSize: 7,
      expirationFontSize: 6,
      logoTextFontSize: 7,
    );
  }

  /// Create a copy with fonts assigned
  LabelTemplate withFonts(pw.Font regular, pw.Font bold) => LabelTemplate(
        labelWidth: labelWidth,
        labelHeight: labelHeight,
        logoHeight: logoHeight,
        qrCodeSize: qrCodeSize,
        padding: padding,
        textSpacing: textSpacing,
        lotIdFontSize: lotIdFontSize,
        itemNameFontSize: itemNameFontSize,
        expirationFontSize: expirationFontSize,
        logoTextFontSize: logoTextFontSize,
        borderColor: borderColor,
        textColor: textColor,
        expirationColor: expirationColor,
        logoTextColor: logoTextColor,
        textFlex: textFlex,
        qrFlex: qrFlex,
        useQr: useQr,
        showLinearBarcode: showLinearBarcode,
        showExpirationPill: showExpirationPill,
        quietZone: quietZone,
        cornerRadius: cornerRadius,
        dividerThickness: dividerThickness,
        fontRegular: regular,
        fontBold: bold,
        design: design,
      );

  LabelTemplate withFontsAndDesign(pw.Font regular, pw.Font bold, Map<String, dynamic>? design) => LabelTemplate(
        labelWidth: labelWidth,
        labelHeight: labelHeight,
        logoHeight: logoHeight,
        qrCodeSize: qrCodeSize,
        padding: padding,
        textSpacing: textSpacing,
        lotIdFontSize: lotIdFontSize,
        itemNameFontSize: itemNameFontSize,
        expirationFontSize: expirationFontSize,
        logoTextFontSize: logoTextFontSize,
        borderColor: borderColor,
        textColor: textColor,
        expirationColor: expirationColor,
        logoTextColor: logoTextColor,
        textFlex: textFlex,
        qrFlex: qrFlex,
        useQr: useQr,
        showLinearBarcode: showLinearBarcode,
        showExpirationPill: showExpirationPill,
        quietZone: quietZone,
        cornerRadius: cornerRadius,
        dividerThickness: dividerThickness,
        fontRegular: regular,
        fontBold: bold,
        design: design,
      );
}

/// Label Export Service for SCOUT
class LabelExportService {
  // 🎨 Defaults tuned for Avery 5160 (1" high)
  static LabelTemplate defaultTemplate = const LabelTemplate(
    padding: 4,
    textSpacing: 1.5,
    lotIdFontSize: 16,
    itemNameFontSize: 7,
    expirationFontSize: 6,
    qrCodeSize: 44, // increased to better fill 1" labels while keeping room for text
    logoHeight: 20,
    borderColor: PdfColors.white,
    textColor: PdfColors.black,
    expirationColor: PdfColors.grey700,
    logoTextColor: PdfColors.blue700,
    useQr: true, // kept for config compat
    showLinearBarcode: false, // kept for config compat
    showExpirationPill: true,
    quietZone: 3,
    cornerRadius: 2,
    dividerThickness: 0,
    textFlex: 3,
    qrFlex: 1,
  );

  // Logo image cache
  static pw.MemoryImage? _logoImage;

  /// Load logo image from assets
  static Future<pw.MemoryImage?> _loadLogoImage() async {
    if (_logoImage != null) return _logoImage;

    try {
      const logoPaths = [
        'assets/images/scout_logo.png',
        'assets/images/scout_logo.webp',
        'assets/images/scout dash logo light mode.png',
      ];

      for (final path in logoPaths) {
        try {
          final logoData = await rootBundle.load(path);
          _logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
          return _logoImage;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Generate PDF with labels for the given lots
  static Future<Uint8List> generateLabels(
    List<Map<String, dynamic>> lotsData, {
    LabelTemplate? template,
    int startIndex = 0, // 0..29 for Avery 5160 (which cell to start on)
    double nudgeX = 0, // Global X calibration nudge (points)
    double nudgeY = 0, // Global Y calibration nudge (points)
    bool debugForceQrPlaceholder = false,
    bool debugMarkQr = false,
  }) async {
    // Try Firestore overrides if template not provided
    if (template == null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('config').doc('labels').get();
        if (doc.exists) {
          final data = doc.data()!;
          template = LabelTemplate(
            qrCodeSize: (data['qrCodeSize'] ?? defaultTemplate.qrCodeSize).toDouble(),
            padding: (data['padding'] ?? defaultTemplate.padding).toDouble(),
            lotIdFontSize: (data['lotIdFontSize'] ?? defaultTemplate.lotIdFontSize).toDouble(),
            itemNameFontSize: (data['itemNameFontSize'] ?? defaultTemplate.itemNameFontSize).toDouble(),
            expirationFontSize: (data['expirationFontSize'] ?? defaultTemplate.expirationFontSize).toDouble(),
            logoHeight: (data['logoHeight'] ?? defaultTemplate.logoHeight).toDouble(),
            // legacy flags are ignored in rendering; we still read them for compat
            useQr: true,
            quietZone: (data['quietZone'] ?? defaultTemplate.quietZone).toDouble(),
            cornerRadius: (data['cornerRadius'] ?? defaultTemplate.cornerRadius).toDouble(),
            dividerThickness: (data['dividerThickness'] ?? defaultTemplate.dividerThickness).toDouble(),
            textFlex: (data['textFlex'] ?? defaultTemplate.textFlex) as int,
            qrFlex: (data['qrFlex'] ?? defaultTemplate.qrFlex) as int,
          );
        }
      } catch (_) {
        // ignore and fall back to default template
      }
    }

    final spec = Avery5160Spec(nudgeX: nudgeX, nudgeY: nudgeY);
    final pdf = pw.Document();
    final fonts = await _loadFonts();
    // Attempt to load saved design if template was not provided
  Map<String, dynamic>? design;
    if (template == null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('config').doc('labels').get();
        if (doc.exists) {
          final data = doc.data()!;
          final rawDesign = data['design'] as Map<String, dynamic>?;
          if (rawDesign != null) {
            // Preserve arbitrary keys per element (x,y,w,h plus style hints)
            design = rawDesign.map((k, v) {
              final out = <String, dynamic>{};
              if (v is Map) {
                out['x'] = (v['x'] ?? 0.0).toDouble();
                out['y'] = (v['y'] ?? 0.0).toDouble();
                out['w'] = (v['w'] ?? 0.4).toDouble();
                out['h'] = (v['h'] ?? 0.15).toDouble();
                // optional style hints
                if (v.containsKey('fontSize')) out['fontSize'] = (v['fontSize'] as num?)?.toDouble();
                if (v.containsKey('bold')) out['bold'] = v['bold'] == true;
                if (v.containsKey('align')) out['align'] = v['align'] as String?;
              }
              return MapEntry(k, out);
            });
          }
        }
      } catch (_) {}
    }

    final labelTemplate = (template ?? defaultTemplate).withFontsAndDesign(fonts.regular, fonts.bold, design);
    final logoImage = await _loadLogoImage();

    // Group lots into pages, accounting for startIndex on first page
    var cursor = 0;
    while (cursor < lotsData.length) {
      final startOffset = (cursor == 0 ? (startIndex % Avery5160Spec.labelsPerPage) : 0);
      final remainingOnFirstPage = Avery5160Spec.labelsPerPage - startOffset;
      final take = (lotsData.length - cursor).clamp(0, remainingOnFirstPage);
      final pageLots = lotsData.sublist(cursor, cursor + take);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.zero,
          build: (context) => _buildLabelPage(
            pageLots,
            logoImage,
            labelTemplate,
            spec,
            startCell: startOffset,
            debugForceQrPlaceholder: debugForceQrPlaceholder,
            debugMarkQr: debugMarkQr,
          ),
        ),
      );
      cursor += take;
    }

    return pdf.save();
  }

  static pw.Widget _buildLabelPage(
    List<Map<String, dynamic>> lots,
    pw.MemoryImage? logoImage,
    LabelTemplate template,
    Avery5160Spec spec, {
    int startCell = 0,
    bool debugForceQrPlaceholder = false,
    bool debugMarkQr = false,
  }) {
    final labels = <pw.Widget>[];
    for (int i = 0; i < lots.length && (i + startCell) < Avery5160Spec.labelsPerPage; i++) {
      final cellRect = spec.cellRect(i + startCell);
      labels.add(
        pw.Positioned(
          left: cellRect.x,
          top: cellRect.y,
          child: pw.Container(
            width: cellRect.width,
            height: cellRect.height,
            child: _buildLabel(
              lots[i],
              logoImage,
              template,
              debugForceQrPlaceholder: debugForceQrPlaceholder,
              debugMarkQr: debugMarkQr,
            ),
          ),
        ),
      );
    }
    return pw.Stack(children: labels);
  }

  /// Auto-fit text to one line by scaling font size
  static pw.Widget _autoFitOneLine(
    String text, {
    required double maxSize,
    required double minSize,
    required pw.TextStyle style,
  }) {
    final steps = [maxSize, (maxSize * 0.95), (maxSize * 0.9), (maxSize * 0.85), (maxSize * 0.8), minSize];

    return pw.LayoutBuilder(
      builder: (ctx, constraints) {
        final maxWidth = constraints?.maxWidth ?? 0;
        if (maxWidth <= 0) {
          return pw.Text(text, maxLines: 1, style: style.copyWith(fontSize: minSize));
        }

        for (final size in steps) {
          if (text.length * (size * 0.6) <= maxWidth) {
            return pw.Text(text, maxLines: 1, style: style.copyWith(fontSize: size));
          }
        }
        return pw.Text(text, maxLines: 1, style: style.copyWith(fontSize: minSize));
      },
    );
  }

  static pw.Widget _buildLabel(
    Map<String, dynamic> lot,
    pw.MemoryImage? logoImage,
    LabelTemplate t, {
    bool debugForceQrPlaceholder = false,
    bool debugMarkQr = false,
  }) {
    final lotId = (lot['lotCode'] ?? lot['id'] ?? 'Unknown').toString();
    final variety = lot['variety'] as String?;
    final itemName = (lot['itemName'] ?? 'Unknown Item').toString();
    final expirationDate = _formatExpirationDate(lot['expiresAt']);
    final itemId = (lot['itemId'] ?? '').toString();
    final lotDocId = (lot['id'] ?? '').toString();
    final grantName = lot['grantName'] as String?;
    
    // Debug output
    debugPrint('Label data - lotId: $lotId, variety: $variety, grantName: $grantName, itemName: $itemName');

    final todayDate = _formatTodayDate();

    // Helper to get rect in points from fractional design if available
    PdfRect? designRect(String key) {
      try {
        final d = t.design?[key];
        if (d == null) return null;
        return PdfRect(d['x']! * t.labelWidth, d['y']! * t.labelHeight, d['w']! * t.labelWidth, d['h']! * t.labelHeight);
      } catch (_) {
        return null;
      }
    }

    // Helper to get style overrides for an element
    double? designFontSize(String key) {
      try {
        final d = t.design?[key];
        return d != null && d.containsKey('fontSize') ? (d['fontSize'] as num).toDouble() : null;
      } catch (_) {
        return null;
      }
    }

    bool designBold(String key) {
      try {
        final d = t.design?[key];
        return d != null && d['bold'] == true;
      } catch (_) {
        return false;
      }
    }

    pw.TextAlign designAlign(String key, pw.TextAlign fallback) {
      try {
        final d = t.design?[key];
        final a = d != null ? (d['align'] as String?) : null;
        if (a == 'center') return pw.TextAlign.center;
        if (a == 'right') return pw.TextAlign.right;
        return fallback;
      } catch (_) {
        return fallback;
      }
    }

    // Expiration chip/pill widget
    pw.Widget expirationChip(String text) => t.showExpirationPill && text.isNotEmpty
        ? pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(
              'Exp: $text',
              style: pw.TextStyle(
                font: t.fontBold ?? pw.Font.helveticaBold(),
                fontSize: t.expirationFontSize,
                color: t.expirationColor,
              ),
            ),
          )
        : (text.isNotEmpty
            ? pw.Text(
                'Exp: $text',
                style: pw.TextStyle(
                  font: t.fontRegular ?? pw.Font.helvetica(),
                  fontSize: t.expirationFontSize,
                  color: t.expirationColor,
                ),
              )
            : pw.SizedBox());

  // If design exists, use it to position elements. Otherwise, fallback to legacy layout
  final hasDesign = t.design != null;
  final innerW = t.labelWidth - (t.padding * 2);
  final innerH = t.labelHeight - (t.padding * 2);

  // Legacy computed QR size (used when no design provided)
  final qrRegionWidth = (innerW * 0.5).clamp(20.0, innerW * 0.6);
  final maxQrHeight = (innerH - 2.0).clamp(16.0, innerH);
  final legacyQrSize = t.qrCodeSize.clamp(20.0, qrRegionWidth).clamp(16.0, maxQrHeight);

    // Generate deep link for QR code
    // Use path-based URLs (no hash) to match PathUrlStrategy
    const host = 'scout.littleempathy.com';
    final qrData = (itemId.isNotEmpty && lotDocId.isNotEmpty)
        ? 'https://$host/lot/$itemId/$lotDocId'
        : (lotId.isNotEmpty ? lotId : 'INVALID_LOT');

    // Log warning if QR data is invalid
    if (itemId.isEmpty || lotDocId.isEmpty) {
      debugPrint('WARNING: Label generated with incomplete data - itemId: "$itemId", lotDocId: "$lotDocId", lotCode: "$lotId"');
    }

    if (!hasDesign) {
      // Legacy layout kept for backward compatibility
      return pw.Container(
        width: t.labelWidth,
        height: t.labelHeight,
        padding: pw.EdgeInsets.all(t.padding),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: t.borderColor, width: 0.5),
          borderRadius: pw.BorderRadius.circular(t.cornerRadius),
        ),
        child: pw.Row(
          children: [
            // Left column: logo, lot, item, expiration
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // logo + expiration (top row)
                  pw.Row(
                    children: [
                      pw.Container(
                        width: t.logoHeight,
                        height: t.logoHeight,
                        child: logoImage != null
                            ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                            : pw.Text(
                                'SCOUT',
                                style: pw.TextStyle(
                                  font: t.fontBold ?? pw.Font.helveticaBold(),
                                  fontSize: t.logoTextFontSize,
                                  color: t.logoTextColor,
                                ),
                              ),
                      ),
                      pw.Spacer(),
                      expirationChip(expirationDate),
                    ],
                  ),

                  pw.SizedBox(height: 2),

                  // Lot ID (auto-fit, shrinks more if needed)
                  _autoFitOneLine(
                    lotId,
                    maxSize: t.lotIdFontSize + 2,
                    minSize: 8, // Allow shrinking to 8pt to make room for other fields
                    style: pw.TextStyle(
                      font: t.fontBold ?? pw.Font.helveticaBold(),
                      color: t.textColor,
                    ),
                  ),
                  
                  pw.SizedBox(height: 1),

                  // Item name - always show
                  pw.Text(
                    itemName,
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: t.fontRegular ?? pw.Font.helvetica(),
                      fontSize: (t.itemNameFontSize).clamp(6, 9),
                      color: t.textColor,
                    ),
                    overflow: pw.TextOverflow.clip,
                  ),

                  // Variety (if present) - show in bold below item name
                  if (variety != null && variety.isNotEmpty) ...[
                    pw.Text(
                      variety,
                      style: pw.TextStyle(
                        font: t.fontBold ?? pw.Font.helveticaBold(),
                        fontSize: (t.itemNameFontSize).clamp(6, 9),
                        color: t.textColor,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                  
                  // Grant (if present)
                  if (grantName != null) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Grant: $grantName',
                      style: pw.TextStyle(
                        font: t.fontRegular ?? pw.Font.helvetica(),
                        fontSize: 6,
                        color: t.textColor,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                  
                  pw.Spacer(), // Push everything to top, leaving space at bottom
                ],
              ),
            ),

            // subtle divider (add a little padding before it so date isn't cramped)
            pw.SizedBox(width: 4),
            pw.Container(width: 1, height: innerH * 0.9, color: PdfColors.grey200),
            pw.SizedBox(width: 4),

            // Right: large QR with printed date underneath
            pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(
                  width: legacyQrSize,
                  height: legacyQrSize,
                  child: debugForceQrPlaceholder
                      ? pw.Container(color: PdfColors.black, width: legacyQrSize, height: legacyQrSize)
                      : pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrData, drawText: false),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  todayDate,
                  style: pw.TextStyle(
                    font: t.fontRegular ?? pw.Font.helvetica(),
                    fontSize: 5,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // If we reach here, use the design to layout elements
    final elements = <pw.Widget>[];

    // Helper to place a child at fractional rect
    pw.Widget placed(String key, pw.Widget child) {
      final r = designRect(key);
      if (r == null) return pw.SizedBox();
      return pw.Positioned(left: r.left + t.padding, top: r.top + t.padding, child: pw.Container(width: r.width, height: r.height, child: child));
    }

    // Lot ID
    final lotFontSize = designFontSize('lotId') ?? t.lotIdFontSize + 2;
    final lotBold = designBold('lotId');
    elements.add(placed(
      'lotId',
      pw.Align(
        alignment: designAlign('lotId', pw.TextAlign.left) == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.topLeft,
        child: _autoFitOneLine(
          lotId,
          maxSize: lotFontSize + 2,
          minSize: (lotFontSize * 0.7).clamp(7, lotFontSize),
          style: pw.TextStyle(font: lotBold ? (t.fontBold ?? pw.Font.helveticaBold()) : (t.fontRegular ?? pw.Font.helvetica()), color: t.textColor),
        ),
      ),
    ));

    // Grant (if present and no custom design)
    if (grantName != null && designRect('grant') == null) {
      // Place grant below lot ID
      final lotRect = designRect('lotId');
      if (lotRect != null) {
        elements.add(pw.Positioned(
          left: lotRect.left,
          top: lotRect.bottom + 2,
          child: pw.Container(
            width: lotRect.width,
            child: pw.Text(
              'Grant: $grantName',
              style: pw.TextStyle(
                font: t.fontRegular ?? pw.Font.helvetica(),
                fontSize: (t.expirationFontSize * 0.9).clamp(6, 8),
                color: t.textColor,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ));
      }
    }

    // Item name with variety (if present)
    final itemFontSize = designFontSize('itemName') ?? t.itemNameFontSize + 1;
    final itemBold = designBold('itemName');
    final itemText = variety != null && variety.isNotEmpty ? '$itemName ($variety)' : itemName;
    elements.add(placed(
      'itemName',
      pw.Text(itemText, maxLines: 2, textAlign: designAlign('itemName', pw.TextAlign.left), style: pw.TextStyle(font: itemBold ? (t.fontBold ?? pw.Font.helveticaBold()) : (t.fontRegular ?? pw.Font.helvetica()), fontSize: itemFontSize, color: t.textColor)),
    ));

    // Expiration
    // Expiration may need custom font size/bold
    final expFontSize = designFontSize('expiration') ?? t.expirationFontSize;
    final expBold = designBold('expiration');
    pw.Widget expWidget = t.showExpirationPill && expirationDate.isNotEmpty
        ? pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(
              'Exp: $expirationDate',
              style: pw.TextStyle(
                font: expBold ? (t.fontBold ?? pw.Font.helveticaBold()) : (t.fontRegular ?? pw.Font.helvetica()),
                fontSize: expFontSize,
                color: t.expirationColor,
              ),
            ),
          )
        : (expirationDate.isNotEmpty
            ? pw.Text('Exp: $expirationDate', style: pw.TextStyle(font: expBold ? (t.fontBold ?? pw.Font.helveticaBold()) : (t.fontRegular ?? pw.Font.helvetica()), fontSize: expFontSize, color: t.expirationColor))
            : pw.SizedBox());

    elements.add(placed('expiration', expWidget));

    // QR and date
    elements.add(placed(
      'qr',
      pw.Column(children: [
        pw.Container(width: designRect('qr')?.width ?? legacyQrSize, height: designRect('qr')?.height ?? legacyQrSize, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrData, drawText: false)),
        pw.SizedBox(height: 4),
        pw.Text(todayDate, style: pw.TextStyle(font: t.fontRegular ?? pw.Font.helvetica(), fontSize: 5, color: PdfColors.grey600)),
      ]),
    ));

    return pw.Container(
      width: t.labelWidth,
      height: t.labelHeight,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: t.borderColor, width: 0.5), borderRadius: pw.BorderRadius.circular(t.cornerRadius)),
      child: pw.Stack(children: elements),
    );
  }

  /// Get lots data for the given item IDs
  static Future<List<Map<String, dynamic>>> getLotsForItems(List<String> itemIds) async {
    final lots = <Map<String, dynamic>>[];
    
    // Load all grant names once
    final grantsSnapshot = await FirebaseFirestore.instance.collection('grants').get();
    final grantNames = <String, String>{};
    for (final doc in grantsSnapshot.docs) {
      grantNames[doc.id] = doc.data()['name'] as String? ?? doc.id;
    }

    for (final itemId in itemIds) {
      final itemDoc = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
      if (!itemDoc.exists) continue;

      final itemData = itemDoc.data()!;
      final itemName = itemData['name'] ?? 'Unknown Item';

      final lotsSnapshot = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .collection('lots')
          .where('qtyRemaining', isGreaterThan: 0)
          .get();

      for (final lotDoc in lotsSnapshot.docs) {
        final lotData = lotDoc.data();
        final grantId = lotData['grantId'] as String?;
        final grantName = grantId != null ? grantNames[grantId] : null;
        
        lots.add({
          ...lotData,
          'id': lotDoc.id,
          'itemId': itemId,
          'itemName': itemName,
          'grantName': grantName,
        });
      }
    }

    return lots;
  }

  /// Export PDF with labels, handling web vs mobile platforms
  static Future<void> exportLabels(
    List<Map<String, dynamic>> lotsData, {
    LabelTemplate? template,
    int startIndex = 0,
    double nudgeX = 0,
    double nudgeY = 0,
  }) async {
    final pdfBytes = await generateLabels(
      lotsData,
      template: template,
      startIndex: startIndex,
      nudgeX: nudgeX,
      nudgeY: nudgeY,
    );
    final fileName = 'item_labels_${DateTime.now().millisecondsSinceEpoch}.pdf';

    if (kIsWeb) {
      final base64 = base64Encode(pdfBytes);
      final dataUrl = 'data:application/pdf;base64,$base64';
      downloadDataUrl(dataUrl, fileName);
    } else {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Item Labels PDF');
      } catch (e) {
        throw UnsupportedError('Mobile PDF export failed: $e');
      }
    }
  }

  static String _formatExpirationDate(dynamic expiresAt) {
    if (expiresAt == null) return '';
    DateTime? date;
    if (expiresAt is Timestamp) {
      date = expiresAt.toDate();
    } else if (expiresAt is DateTime) {
      date = expiresAt;
    }
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }

  static String _formatTodayDate() {
    final now = DateTime.now();
    return '${now.month}/${now.day}/${now.year}';
  }
}
