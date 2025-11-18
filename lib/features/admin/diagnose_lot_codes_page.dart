import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DiagnoseLotCodesPage extends StatefulWidget {
  const DiagnoseLotCodesPage({super.key});

  @override
  State<DiagnoseLotCodesPage> createState() => _DiagnoseLotCodesPageState();
}

class _DiagnoseLotCodesPageState extends State<DiagnoseLotCodesPage> {
  final _db = FirebaseFirestore.instance;
  bool _isAnalyzing = false;
  List<String> _duplicates = [];
  Map<String, List<Map<String, dynamic>>> _lotsByCode = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnose Lot Codes'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lot Code Diagnostic Tool',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This tool checks for duplicate lot codes within the same item.\n\n'
                      'Note: It is NORMAL for different items to have the same lot code.\n'
                      'For example, both "Paper Towels" and "Hand Soap" can have "2510-001".\n\n'
                      'This tool only reports PROBLEMS: when the SAME ITEM has duplicate lot codes.',
                    ),
                    const SizedBox(height: 16),
                    if (!_isAnalyzing)
                      FilledButton.icon(
                        onPressed: _analyzeLotCodes,
                        icon: const Icon(Icons.search),
                        label: const Text('Check for Duplicates'),
                      )
                    else
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_duplicates.isNotEmpty) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '⚠️ Found ${_duplicates.length} items with duplicate lot codes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Duplicate Lot Codes (same item)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _duplicates.length,
                    itemBuilder: (context, index) {
                      return _buildDuplicateItem(_duplicates[index]);
                    },
                  ),
                ),
              ),
            ] else if (!_isAnalyzing && _lotsByCode.isNotEmpty) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '✅ No duplicate lot codes found!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicateItem(String itemId) {
    final itemLots = _lotsByCode[itemId] ?? [];
    
    // Group by lot code
    final Map<String, List<Map<String, dynamic>>> lotsByCode = {};
    for (final lot in itemLots) {
      final code = lot['lotCode'] as String;
      lotsByCode.putIfAbsent(code, () => []);
      lotsByCode[code]!.add(lot);
    }

    // Find duplicates
    final duplicateCodes = lotsByCode.entries.where((e) => e.value.length > 1).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(
          itemLots.first['itemName'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Item ID: $itemId\n${duplicateCodes.length} duplicate lot codes',
          style: const TextStyle(fontSize: 12),
        ),
        children: duplicateCodes.map((entry) {
          final code = entry.key;
          final lots = entry.value;
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lot Code: $code (${lots.length} duplicates)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                ...lots.map((lot) {
                  final createdAt = lot['createdAt'] as Timestamp?;
                  final createdDate = createdAt?.toDate();
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text(
                      '• Lot ID: ${lot['lotId']}\n'
                      '  Created: ${createdDate != null ? createdDate.toString().substring(0, 19) : 'Unknown'}\n'
                      '  Qty: ${lot['qtyRemaining']} ${lot['baseUnit']}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _analyzeLotCodes() async {
    setState(() {
      _isAnalyzing = true;
      _duplicates.clear();
      _lotsByCode.clear();
    });

    try {
      // Get all lots
      final lotsSnapshot = await _db.collectionGroup('lots').get();

      // Group by item ID
      final Map<String, List<Map<String, dynamic>>> lotsByItem = {};
      
      for (final lotDoc in lotsSnapshot.docs) {
        final itemId = lotDoc.reference.parent.parent!.id;
        final lotData = lotDoc.data();
        
        // Initialize item entry if needed
        if (!lotsByItem.containsKey(itemId)) {
          lotsByItem[itemId] = [];
        }

        lotsByItem[itemId]!.add({
          'lotId': lotDoc.id,
          'lotCode': lotData['lotCode'] ?? '',
          'qtyRemaining': lotData['qtyRemaining'] ?? 0,
          'baseUnit': lotData['baseUnit'] ?? 'each',
          'createdAt': lotData['createdAt'],
          'itemName': await _getItemName(itemId),
        });
      }

      // Remove the unused _getItemName call from the add statement
      for (final itemId in lotsByItem.keys) {
        final itemName = await _getItemName(itemId);
        for (final lot in lotsByItem[itemId]!) {
          lot['itemName'] = itemName;
        }
      }

      // Find items with duplicate lot codes
      for (final entry in lotsByItem.entries) {
        final itemId = entry.key;
        final lots = entry.value;

        // Count lot codes
        final Map<String, int> codeCount = {};
        for (final lot in lots) {
          final code = lot['lotCode'] as String;
          codeCount[code] = (codeCount[code] ?? 0) + 1;
        }

        // Check for duplicates
        if (codeCount.values.any((count) => count > 1)) {
          _duplicates.add(itemId);
          _lotsByCode[itemId] = lots;
        }
      }

      setState(() {});

      if (mounted) {
        if (_duplicates.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ No duplicate lot codes found! Everything looks good.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Found ${_duplicates.length} items with duplicate lot codes'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error analyzing lot codes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<String> _getItemName(String itemId) async {
    try {
      final itemDoc = await _db.collection('items').doc(itemId).get();
      return itemDoc.data()?['name'] ?? 'Unknown Item';
    } catch (e) {
      return 'Unknown Item';
    }
  }
}
