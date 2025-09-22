import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr/qr.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LabelExportService {
  // Avery 5160 specifications
  static const double pageWidth = 8.5 * 72; // 8.5" in points
  static const double pageHeight = 11.0 * 72; // 11" in points
  static const double labelWidth = 2.625 * 72; // 2-5/8" in points
  static const double labelHeight = 1.0 * 72; // 1" in points
  static const double topMargin = 0.5 * 72; // 0.5" top margin
  static const double bottomMargin = 0.5 * 72; // 0.5" bottom margin
  static const double leftMargin = 0.19 * 72; // 0.19" left margin
  static const double rightMargin = 0.19 * 72; // 0.19" right margin
  static const double horizontalGap = 0.125 * 72; // 0.125" horizontal gap
  static const double verticalGap = 0.125 * 72; // 0.125" vertical gap

  /// Generate PDF with labels for the given lots
  static Future<Uint8List> generateLabels(List<Map<String, dynamic>> lotsData) async {
    final pdf = pw.Document();

    // Group lots into pages (30 labels per page for Avery 5160)
    const int labelsPerPage = 30;
    final pages = <List<Map<String, dynamic>>>[];

    for (int i = 0; i < lotsData.length; i += labelsPerPage) {
      final end = (i + labelsPerPage < lotsData.length) ? i + labelsPerPage : lotsData.length;
      pages.add(lotsData.sublist(i, end));
    }

    for (final pageLots in pages) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          build: (context) => _buildLabelPage(pageLots),
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _buildLabelPage(List<Map<String, dynamic>> lots) {
    // Calculate positions for 3x10 grid
    final labels = <pw.Widget>[];
    const int columns = 3;
    const int rows = 10;

    for (int i = 0; i < lots.length && i < columns * rows; i++) {
      final row = i ~/ columns;
      final col = i % columns;

      final x = leftMargin + col * (labelWidth + horizontalGap);
      final y = topMargin + row * (labelHeight + verticalGap);

      labels.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.Container(
            width: labelWidth,
            height: labelHeight,
            child: _buildLabel(lots[i]),
          ),
        ),
      );
    }

    return pw.Stack(children: labels);
  }

  static pw.Widget _buildLabel(Map<String, dynamic> lot) {
    final lotId = lot['lotCode'] ?? lot['id'] ?? 'Unknown';
    final itemName = lot['itemName'] ?? 'Unknown Item';
    final expirationDate = _formatExpirationDate(lot['expiresAt']);
    final qrData = 'scout://lot/${lot['itemId']}/${lot['id']}';

    return pw.Container(
      width: labelWidth,
      height: labelHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        children: [
          // Logo at the top
          pw.Container(
            height: 16, // Small logo height
            child: pw.Center(
              child: pw.Text(
                'SCOUT',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          // Main content
          pw.Expanded(
            child: pw.Row(
              children: [
                // Left side: Lot ID and item info
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      // Lot ID - large and bold
                      pw.Text(
                        lotId,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      // Item name
                      pw.Text(
                        itemName,
                        style: pw.TextStyle(
                          fontSize: 6,
                          color: PdfColors.black,
                        ),
                        maxLines: 2,
                      ),
                      pw.SizedBox(height: 1),
                      // Expiration date
                      if (expirationDate.isNotEmpty)
                        pw.Text(
                          'Exp: $expirationDate',
                          style: pw.TextStyle(
                            fontSize: 5,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 2),
                // Right side: QR Code
                pw.Container(
                  width: 32,
                  height: 32,
                  child: _buildQrCode(qrData),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildQrCode(String data) {
    try {
      // Generate QR code
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.L,
      );

      // Get the QR code matrix
      final qrImage = QrImage(qrCode);

      // Calculate pixel size for the QR code in the available space
      const double qrSize = 32; // Size of QR code area
      final int moduleCount = qrImage.moduleCount;
      final double pixelSize = qrSize / moduleCount;

      // Create a list of rectangles for black modules
      final List<pw.Widget> qrModules = [];

      for (int x = 0; x < moduleCount; x++) {
        for (int y = 0; y < moduleCount; y++) {
          if (qrImage.isDark(y, x)) { // Note: isDark(y, x) not isDark(x, y)
            qrModules.add(
              pw.Positioned(
                left: x * pixelSize,
                top: y * pixelSize,
                child: pw.Container(
                  width: pixelSize,
                  height: pixelSize,
                  color: PdfColors.black,
                ),
              ),
            );
          }
        }
      }

      return pw.Container(
        width: qrSize,
        height: qrSize,
        child: pw.Stack(children: qrModules),
      );
    } catch (e) {
      // Fallback to text if QR generation fails
      return pw.Container(
        width: 32,
        height: 32,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1),
        ),
        child: pw.Center(
          child: pw.Text(
            'QR',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.black),
          ),
        ),
      );
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

  /// Export PDF with labels, handling web vs mobile platforms
  static Future<void> exportLabels(List<Map<String, dynamic>> lotsData) async {
    if (kIsWeb) {
      // Web export not supported in WASM builds
      throw UnsupportedError('PDF export is not available on web. Please use the mobile app for PDF export functionality.');
    } else {
      // Mobile: Use share_plus
      // This would need to be called from the UI layer since it requires context
      throw UnsupportedError('Mobile export should be handled in the UI layer');
    }
  }

  /// Get lots data for the given item IDs
  static Future<List<Map<String, dynamic>>> getLotsForItems(List<String> itemIds) async {
    final lots = <Map<String, dynamic>>[];

    for (final itemId in itemIds) {
      // Get item data first
      final itemDoc = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
      if (!itemDoc.exists) continue;

      final itemData = itemDoc.data()!;
      final itemName = itemData['name'] ?? 'Unknown Item';

      // Get lots for this item
      final lotsSnapshot = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .collection('lots')
          .where('qtyRemaining', isGreaterThan: 0)
          .get();

      for (final lotDoc in lotsSnapshot.docs) {
        final lotData = lotDoc.data();
        lots.add({
          ...lotData,
          'id': lotDoc.id,
          'itemId': itemId,
          'itemName': itemName,
        });
      }
    }

    return lots;
  }
}