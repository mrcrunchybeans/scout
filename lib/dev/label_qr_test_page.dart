import 'package:flutter/material.dart';
import '../services/label_export_service.dart';

/// Dev-only page to generate test label PDFs and verify QR rendering.
class LabelQrTestPage extends StatelessWidget {
  const LabelQrTestPage({super.key});

  Future<void> _generateDefault(BuildContext context) async {
    final lots = [
      {
        'id': 'lot-test-1',
        'itemId': 'item-test-1',
        'lotCode': 'T202509',
        'itemName': 'Test Item',
      }
    ];

    try {
      await LabelExportService.exportLabels(lots);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated default label')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _generateLargeQr(BuildContext context) async {
    final lots = [
      {
        'id': 'lot-test-2',
        'itemId': 'item-test-2',
        'lotCode': 'T202509-LARGE',
        'itemName': 'Test Item Large QR',
      }
    ];

    try {
      // Build a template based on default but with larger QR; fonts will be loaded in the service
      final defaultTpl = LabelExportService.defaultTemplate;
      final custom = LabelTemplate(
        labelWidth: defaultTpl.labelWidth,
        labelHeight: defaultTpl.labelHeight,
        logoHeight: defaultTpl.logoHeight,
        qrCodeSize: 96,
        padding: defaultTpl.padding,
        textSpacing: defaultTpl.textSpacing,
        lotIdFontSize: defaultTpl.lotIdFontSize,
        itemNameFontSize: defaultTpl.itemNameFontSize,
        expirationFontSize: defaultTpl.expirationFontSize,
        logoTextFontSize: defaultTpl.logoTextFontSize,
        borderColor: defaultTpl.borderColor,
        textColor: defaultTpl.textColor,
        expirationColor: defaultTpl.expirationColor,
        logoTextColor: defaultTpl.logoTextColor,
        textFlex: defaultTpl.textFlex,
        qrFlex: defaultTpl.qrFlex,
        useQr: defaultTpl.useQr,
        showLinearBarcode: defaultTpl.showLinearBarcode,
        showExpirationPill: defaultTpl.showExpirationPill,
        quietZone: 6.0,
        cornerRadius: defaultTpl.cornerRadius,
        dividerThickness: defaultTpl.dividerThickness,
      );

      await LabelExportService.exportLabels(lots, template: custom);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated large QR label')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label QR Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () => _generateDefault(context),
              child: const Text('Generate default label (single)')),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _generateLargeQr(context),
              child: const Text('Generate large-QR label (single)')),
            const SizedBox(height: 12),
            const Text('Note: This page is for development testing only.'),
          ],
        ),
      ),
    );
  }
}

// No local font placeholders required; LabelExportService loads fonts internally.
