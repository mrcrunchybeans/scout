import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:scout/services/label_export_service.dart';

Future<void> main() async {
  final lots = [
    {
      'id': 'lot-test-1',
      'itemId': 'item-test-1',
      'lotCode': 'T202509',
      'itemName': 'Test Item',
    }
  ];

  final bytes = await LabelExportService.generateLabels(lots);
  final outDir = Directory('build/test-labels');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final path = 'build/test-labels/test_label_${DateTime.now().millisecondsSinceEpoch}.pdf';
  final file = File(path);
  await file.writeAsBytes(bytes);
  debugPrint('Wrote test label to: $path');
}
