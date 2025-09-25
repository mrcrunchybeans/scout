import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout/services/label_export_service.dart';

void main() {
  testWidgets('produce test label PDF', (tester) async {
    // Ensure Flutter bindings so rootBundle and asset loading work
    TestWidgetsFlutterBinding.ensureInitialized();

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
    print('Wrote test label to: $path');

    expect(bytes.length, greaterThan(0));
  });
}
