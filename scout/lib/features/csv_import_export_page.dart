// lib/features/csv_import_export_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

// Web-specific imports
import 'package:web/web.dart' as html;
import 'dart:js_interop';

class CsvImportExportPage extends StatefulWidget {
  const CsvImportExportPage({super.key});

  @override
  State<CsvImportExportPage> createState() => _CsvImportExportPageState();
}

class _CsvImportExportPageState extends State<CsvImportExportPage> {
  final _db = FirebaseFirestore.instance;
  bool _isProcessing = false;
  String _statusMessage = '';
  double _progress = 0.0;

  // Download helper for web
  void _downloadFile(String content, String filename) {
    if (kIsWeb) {
      final blob = html.Blob([content].jsify() as JSArray<JSAny>);
      final url = html.URL.createObjectURL(blob);
      final anchor = html.HTMLAnchorElement()
        ..href = url
        ..setAttribute('download', filename);
      
      // Temporarily add to DOM for some browsers
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      
      html.URL.revokeObjectURL(url);
    }
  }

  // Simple CSV conversion functions
  String _listToCsv(List<List<dynamic>> data) {
    return data.map((row) {
      return row.map((cell) {
        final cellStr = cell.toString();
        // Escape quotes and wrap in quotes if contains comma, quote, or newline
        if (cellStr.contains(',') || cellStr.contains('"') || cellStr.contains('\n')) {
          return '"${cellStr.replaceAll('"', '""')}"';
        }
        return cellStr;
      }).join(',');
    }).join('\n');
  }

  List<List<dynamic>> _csvToList(String csv) {
    final lines = csv.split('\n');
    return lines.map((line) {
      final result = <dynamic>[];
      bool inQuotes = false;
      String current = '';

      for (int i = 0; i < line.length; i++) {
        final char = line[i];

        if (char == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            // Escaped quote
            current += '"';
            i++; // Skip next quote
          } else {
            // Toggle quote mode
            inQuotes = !inQuotes;
          }
        } else if (char == ',' && !inQuotes) {
          // Field separator
          result.add(current);
          current = '';
        } else {
          current += char;
        }
      }

      // Add the last field
      result.add(current);
      return result;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CSV Import/Export'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import/Export Inventory Data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Import items and lots from CSV files, or export your current inventory data to CSV format.',
            ),
            const SizedBox(height: 32),

            // Export Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export Data',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text('Download your current inventory data as CSV files.'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Export Items'),
                            onPressed: _isProcessing ? null : () => _exportItems(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Export Lots'),
                            onPressed: _isProcessing ? null : () => _exportLots(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Import Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import Data',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text('Upload CSV files to import items and lots into your inventory.'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Warning: Importing will create new items and lots. '
                              'Existing items with matching barcodes will be skipped.',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Import Items'),
                            onPressed: _isProcessing ? null : () => _importItems(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Import Lots'),
                            onPressed: _isProcessing ? null : () => _importLots(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Status Section
            if (_statusMessage.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(_statusMessage),
                      if (_isProcessing) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // CSV Format Help
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV Format Requirements',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _buildCsvFormatHelp(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCsvFormatHelp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items CSV Format:',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Required columns: name, barcode\n'
          'Optional columns: category, baseUnit, qtyOnHand, minQty, description',
        ),
        const SizedBox(height: 16),
        Text(
          'Lots CSV Format:',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Required columns: itemBarcode, lotCode, qtyRemaining\n'
          'Optional columns: baseUnit, expiresAt (YYYY-MM-DD), openAt (YYYY-MM-DD)',
        ),
        const SizedBox(height: 16),
        const Text(
          'Notes:\n'
          '• Dates should be in YYYY-MM-DD format\n'
          '• Barcodes must match existing items for lot import\n'
          '• Use UTF-8 encoding for the CSV files',
        ),
      ],
    );
  }

  Future<void> _exportItems() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Exporting items...';
      _progress = 0.0;
    });

    try {
      // Get all items
      final itemsSnap = await _db.collection('items').get();
      final items = itemsSnap.docs.map((doc) => doc.data()).toList();

      // Convert to CSV
      final csvData = [
        ['name', 'barcode', 'category', 'baseUnit', 'qtyOnHand', 'minQty', 'description'],
        ...items.map((item) => [
          item['name'] ?? '',
          item['barcode'] ?? item['barcodes']?.first ?? '',
          item['category'] ?? '',
          item['baseUnit'] ?? '',
          item['qtyOnHand']?.toString() ?? '0',
          item['minQty']?.toString() ?? '0',
          item['description'] ?? '',
        ]),
      ];

      final csvString = _listToCsv(csvData);

      // Download the CSV file
      final timestamp = DateTime.now().toIso8601String().split('T').first;
      _downloadFile(csvString, 'scout_items_$timestamp.csv');

      setState(() {
        _statusMessage = 'Items exported successfully! File downloaded.';
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error exporting items: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportLots() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Exporting lots...';
      _progress = 0.0;
    });

    try {
      // Get all lots with item information
      final lotsSnap = await _db.collectionGroup('lots').get();
      final lotsData = <Map<String, dynamic>>[];

      for (final lotDoc in lotsSnap.docs) {
        final lotData = lotDoc.data();
        final itemId = lotDoc.reference.parent.parent!.id;

        // Get item barcode
        final itemDoc = await _db.collection('items').doc(itemId).get();
        final itemData = itemDoc.data() ?? {};
        final barcode = itemData['barcode'] ?? itemData['barcodes']?.first ?? '';

        lotsData.add({
          'itemBarcode': barcode,
          'lotCode': lotData['lotCode'] ?? '',
          'qtyRemaining': lotData['qtyRemaining']?.toString() ?? '0',
          'baseUnit': lotData['baseUnit'] ?? '',
          'expiresAt': lotData['expiresAt'] is Timestamp
              ? (lotData['expiresAt'] as Timestamp).toDate().toIso8601String().split('T').first
              : '',
          'openAt': lotData['openAt'] is Timestamp
              ? (lotData['openAt'] as Timestamp).toDate().toIso8601String().split('T').first
              : '',
        });
      }

      // Convert to CSV
      final csvData = [
        ['itemBarcode', 'lotCode', 'qtyRemaining', 'baseUnit', 'expiresAt', 'openAt'],
        ...lotsData.map((lot) => [
          lot['itemBarcode'],
          lot['lotCode'],
          lot['qtyRemaining'],
          lot['baseUnit'],
          lot['expiresAt'],
          lot['openAt'],
        ]),
      ];

      final csvString = _listToCsv(csvData);

      // Download the CSV file
      final timestamp = DateTime.now().toIso8601String().split('T').first;
      _downloadFile(csvString, 'scout_lots_$timestamp.csv');

      setState(() {
        _statusMessage = 'Lots exported successfully! File downloaded.';
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error exporting lots: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _importItems() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Importing items...';
      _progress = 0.0;
    });

    try {
      String csvString;
      if (kIsWeb) {
        final bytes = result.files.first.bytes;
        if (bytes == null) throw Exception('Could not read file');
        csvString = utf8.decode(bytes);
      } else {
        final file = File(result.files.first.path!);
        csvString = await file.readAsString();
      }

      final csvData = _csvToList(csvString);
      if (csvData.isEmpty) throw Exception('CSV file is empty');

      final headers = csvData[0].map((h) => h.toString().toLowerCase()).toList();
      final rows = csvData.sublist(1);

      // Validate headers
      final requiredHeaders = ['name', 'barcode'];
      for (final required in requiredHeaders) {
        if (!headers.contains(required)) {
          throw Exception('Missing required column: $required');
        }
      }

      final nameIndex = headers.indexOf('name');
      final barcodeIndex = headers.indexOf('barcode');
      final categoryIndex = headers.indexOf('category');
      final baseUnitIndex = headers.indexOf('baseunit');
      final qtyIndex = headers.indexOf('qtyonhand');
      final minQtyIndex = headers.indexOf('minqty');

      int imported = 0;
      int skipped = 0;

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final name = row[nameIndex]?.toString().trim();
        final barcode = row[barcodeIndex]?.toString().trim();

        if (name?.isEmpty ?? true) continue;
        if (barcode?.isEmpty ?? true) continue;

        // Check if item already exists
        final existingQuery = await _db
            .collection('items')
            .where('barcode', isEqualTo: barcode)
            .limit(1)
            .get();

        if (existingQuery.docs.isNotEmpty) {
          skipped++;
          continue;
        }

        // Create new item
        final itemData = {
          'name': name,
          'barcode': barcode,
          'barcodes': [barcode],
          'category': categoryIndex >= 0 ? row[categoryIndex]?.toString().trim() : null,
          'baseUnit': baseUnitIndex >= 0 ? row[baseUnitIndex]?.toString().trim() : 'each',
          'qtyOnHand': qtyIndex >= 0 ? num.tryParse(row[qtyIndex]?.toString() ?? '0') ?? 0 : 0,
          'minQty': minQtyIndex >= 0 ? num.tryParse(row[minQtyIndex]?.toString() ?? '0') ?? 0 : 0,
          'active': true,
          'archived': false,
        };

        // Remove null values
        itemData.removeWhere((key, value) => value == null);

        await _db.collection('items').add({
          ...itemData,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        imported++;

        setState(() {
          _progress = (i + 1) / rows.length;
          _statusMessage = 'Importing items... $imported imported, $skipped skipped';
        });
      }

      setState(() {
        _statusMessage = 'Items import completed! $imported imported, $skipped skipped';
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error importing items: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _importLots() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Importing lots...';
      _progress = 0.0;
    });

    try {
      String csvString;
      if (kIsWeb) {
        final bytes = result.files.first.bytes;
        if (bytes == null) throw Exception('Could not read file');
        csvString = utf8.decode(bytes);
      } else {
        final file = File(result.files.first.path!);
        csvString = await file.readAsString();
      }

      final csvData = _csvToList(csvString);
      if (csvData.isEmpty) throw Exception('CSV file is empty');

      final headers = csvData[0].map((h) => h.toString().toLowerCase()).toList();
      final rows = csvData.sublist(1);

      // Validate headers
      final requiredHeaders = ['itembarcode', 'lotcode', 'qtyremaining'];
      for (final required in requiredHeaders) {
        if (!headers.contains(required)) {
          throw Exception('Missing required column: $required');
        }
      }

      final itemBarcodeIndex = headers.indexOf('itembarcode');
      final lotCodeIndex = headers.indexOf('lotcode');
      final qtyIndex = headers.indexOf('qtyremaining');
      final baseUnitIndex = headers.indexOf('baseunit');
      final expiresIndex = headers.indexOf('expiresat');
      final openIndex = headers.indexOf('openat');

      int imported = 0;
      int skipped = 0;

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final itemBarcode = row[itemBarcodeIndex]?.toString().trim();
        final lotCode = row[lotCodeIndex]?.toString().trim();
        final qtyRemaining = num.tryParse(row[qtyIndex]?.toString() ?? '0') ?? 0;

        if (itemBarcode?.isEmpty ?? true) continue;
        if (lotCode?.isEmpty ?? true) continue;
        if (qtyRemaining <= 0) continue;

        // Find item by barcode
        final itemQuery = await _db
            .collection('items')
            .where('barcode', isEqualTo: itemBarcode)
            .limit(1)
            .get();

        if (itemQuery.docs.isEmpty) {
          skipped++;
          continue;
        }

        final itemId = itemQuery.docs.first.id;
        final itemData = itemQuery.docs.first.data();

        // Check if lot already exists
        final existingLotQuery = await _db
            .collection('items')
            .doc(itemId)
            .collection('lots')
            .where('lotCode', isEqualTo: lotCode)
            .limit(1)
            .get();

        if (existingLotQuery.docs.isNotEmpty) {
          skipped++;
          continue;
        }

        // Parse dates
        Timestamp? expiresAt;
        Timestamp? openAt;

        if (expiresIndex >= 0) {
          final expiresStr = row[expiresIndex]?.toString().trim();
          if (expiresStr?.isNotEmpty ?? false) {
            try {
              final date = DateTime.parse(expiresStr!);
              expiresAt = Timestamp.fromDate(date);
            } catch (e) {
              // Invalid date, skip
            }
          }
        }

        if (openIndex >= 0) {
          final openStr = row[openIndex]?.toString().trim();
          if (openStr?.isNotEmpty ?? false) {
            try {
              final date = DateTime.parse(openStr!);
              openAt = Timestamp.fromDate(date);
            } catch (e) {
              // Invalid date, skip
            }
          }
        }

        // Create lot
        await _db.collection('items').doc(itemId).collection('lots').add({
          'lotCode': lotCode,
          'qtyRemaining': qtyRemaining,
          'qtyInitial': qtyRemaining,
          'baseUnit': baseUnitIndex >= 0 ? row[baseUnitIndex]?.toString().trim() : (itemData['baseUnit'] ?? 'each'),
          'expiresAt': expiresAt,
          'openAt': openAt,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update item quantity
        await _db.collection('items').doc(itemId).update({
          'qtyOnHand': FieldValue.increment(qtyRemaining),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        imported++;

        setState(() {
          _progress = (i + 1) / rows.length;
          _statusMessage = 'Importing lots... $imported imported, $skipped skipped';
        });
      }

      setState(() {
        _statusMessage = 'Lots import completed! $imported imported, $skipped skipped';
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error importing lots: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}