import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/lot_code.dart';

class RecalculateLotCodesPage extends StatefulWidget {
  const RecalculateLotCodesPage({super.key});

  @override
  State<RecalculateLotCodesPage> createState() => _RecalculateLotCodesPageState();
}

class _RecalculateLotCodesPageState extends State<RecalculateLotCodesPage> {
  final _db = FirebaseFirestore.instance;
  bool _isProcessing = false;
  String _statusMessage = '';
  List<String> _logMessages = [];
  int _totalLots = 0;
  int _processedLots = 0;
  int _updatedLots = 0;
  int _skippedLots = 0;
  int _duplicatesFound = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recalculate Lot Codes'),
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
                      'Lot Code Standardization Tool',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This tool will recalculate lot codes to ensure consistency across your inventory. '
                      'It will:\n'
                      '• Find lots with old format codes (e.g., 2510A, 2510B)\n'
                      '• Regenerate codes in standard YYMM-XXX format (e.g., 2510-001, 2510-002)\n'
                      '• Preserve original creation dates and chronological order\n'
                      '• Group by item and creation month\n\n'
                      'This process is safe and reversible. A detailed log will be provided.',
                    ),
                    const SizedBox(height: 16),
                    if (!_isProcessing)
                      FilledButton.icon(
                        onPressed: _recalculateLotCodes,
                        icon: const Icon(Icons.calculate),
                        label: const Text('Start Recalculation'),
                      )
                    else
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_statusMessage.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage),
                      if (_totalLots > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalLots > 0 ? _processedLots / _totalLots : 0,
                        ),
                        const SizedBox(height: 4),
                        Text('Progress: $_processedLots / $_totalLots lots'),
                        Text('Updated: $_updatedLots'),
                        Text('Skipped (already correct): $_skippedLots'),
                        if (_duplicatesFound > 0)
                          Text(
                            'Duplicates found: $_duplicatesFound',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (_logMessages.isNotEmpty) ...[
              Text(
                'Detailed Log',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _logMessages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          _logMessages[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add('${DateTime.now().toIso8601String().substring(11, 19)} - $message');
    });
    debugPrint(message);
  }

  Future<void> _recalculateLotCodes() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Starting lot code recalculation...';
      _logMessages.clear();
      _totalLots = 0;
      _processedLots = 0;
      _updatedLots = 0;
      _skippedLots = 0;
      _duplicatesFound = 0;
    });

    try {
      _addLog('Fetching all lots from database...');
      
      // Get all lots from all items
      final lotsSnapshot = await _db.collectionGroup('lots').get();
      _totalLots = lotsSnapshot.docs.length;
      
      _addLog('Found $_totalLots total lots');
      setState(() {
        _statusMessage = 'Found $_totalLots lots. Analyzing...';
      });

      // Group lots by item ID
      final Map<String, List<QueryDocumentSnapshot>> lotsByItem = {};
      for (final lotDoc in lotsSnapshot.docs) {
        final itemId = lotDoc.reference.parent.parent!.id;
        lotsByItem.putIfAbsent(itemId, () => []);
        lotsByItem[itemId]!.add(lotDoc);
      }

      _addLog('Grouped lots into ${lotsByItem.length} items');

      // Check for duplicates before processing
      _addLog('Checking for existing duplicate lot codes...');
      for (final entry in lotsByItem.entries) {
        final itemId = entry.key;
        final lots = entry.value;
        
        // Count lot codes
        final Map<String, int> codeCount = {};
        for (final lotDoc in lots) {
          final lotData = lotDoc.data() as Map<String, dynamic>;
          final lotCode = lotData['lotCode'] as String?;
          if (lotCode != null && lotCode.isNotEmpty) {
            codeCount[lotCode] = (codeCount[lotCode] ?? 0) + 1;
          }
        }
        
        // Check for duplicates
        final duplicates = codeCount.entries.where((e) => e.value > 1).toList();
        if (duplicates.isNotEmpty) {
          _duplicatesFound += duplicates.length;
          final itemDoc = await _db.collection('items').doc(itemId).get();
          final itemName = itemDoc.data()?['name'] ?? 'Unknown Item';
          _addLog('  ⚠️ DUPLICATE CODES in "$itemName": ${duplicates.map((e) => '${e.key} (x${e.value})').join(', ')}');
        }
      }
      
      if (_duplicatesFound > 0) {
        _addLog('⚠️ Found $_duplicatesFound duplicate lot codes that will be fixed');
      } else {
        _addLog('✓ No duplicate lot codes found');
      }

      // Process each item
      for (final entry in lotsByItem.entries) {
        final itemId = entry.key;
        final lots = entry.value;

        // Get item name for logging
        final itemDoc = await _db.collection('items').doc(itemId).get();
        final itemName = itemDoc.data()?['name'] ?? 'Unknown Item';

        _addLog('Processing item: $itemName (ID: $itemId, ${lots.length} lots)');

        // Group lots by creation month
        final Map<String, List<QueryDocumentSnapshot>> lotsByMonth = {};
        for (final lotDoc in lots) {
          final lotData = lotDoc.data() as Map<String, dynamic>;
          final createdAt = lotData['createdAt'] as Timestamp?;
          
          if (createdAt == null) {
            _addLog('  Skipping lot ${lotDoc.id} - no createdAt timestamp');
            _processedLots++;
            _skippedLots++;
            continue;
          }

          final createdDate = createdAt.toDate();
          final monthKey = lotCodeMonthPrefix(referenceDate: createdDate);
          
          lotsByMonth.putIfAbsent(monthKey, () => []);
          lotsByMonth[monthKey]!.add(lotDoc);
        }

        // Process each month's lots
        for (final monthEntry in lotsByMonth.entries) {
          final monthPrefix = monthEntry.key;
          final monthLots = monthEntry.value;

          // Sort by creation time (oldest first)
          monthLots.sort((a, b) {
            final aCreated = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp;
            final bCreated = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp;
            return aCreated.compareTo(bCreated);
          });

          _addLog('  Month $monthPrefix: ${monthLots.length} lots');

          // Track assigned codes to ensure uniqueness
          final Set<String> assignedCodes = {};
          int sequenceNumber = 1;

          // Assign sequential lot codes
          for (final lotDoc in monthLots) {
            final lotData = lotDoc.data() as Map<String, dynamic>;
            final currentLotCode = lotData['lotCode'] as String?;
            
            // Generate next unique code
            String newLotCode;
            do {
              newLotCode = '$monthPrefix-${sequenceNumber.toString().padLeft(3, '0')}';
              sequenceNumber++;
            } while (assignedCodes.contains(newLotCode));
            
            assignedCodes.add(newLotCode);

            if (currentLotCode == newLotCode) {
              _addLog('    Lot ${lotDoc.id}: $currentLotCode (already correct)');
              _skippedLots++;
            } else {
              _addLog('    Lot ${lotDoc.id}: ${currentLotCode ?? '(null)'} → $newLotCode');
              
              // Update the lot code
              await lotDoc.reference.update({
                'lotCode': newLotCode,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              
              _updatedLots++;
            }

            _processedLots++;
            setState(() {
              _statusMessage = 'Processing... ($_processedLots / $_totalLots)';
            });
          }
        }
      }

      _addLog('Recalculation complete!');
      _addLog('Total lots processed: $_processedLots');
      _addLog('Lots updated: $_updatedLots');
      _addLog('Lots already correct: $_skippedLots');

      setState(() {
        _statusMessage = 'Recalculation complete! Updated $_updatedLots lots, skipped $_skippedLots.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully recalculated lot codes! Updated $_updatedLots lots.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      _addLog('ERROR: $e');
      _addLog('Stack trace: $stackTrace');
      
      setState(() {
        _statusMessage = 'Error: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recalculating lot codes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}
