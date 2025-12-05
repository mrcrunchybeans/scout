// lib/features/admin/merge_operators_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Page for merging operator names across the entire application.
/// This updates items, audit logs, sessions, feedback, etc.
class MergeOperatorsPage extends StatefulWidget {
  const MergeOperatorsPage({super.key});

  @override
  State<MergeOperatorsPage> createState() => _MergeOperatorsPageState();
}

class _MergeOperatorsPageState extends State<MergeOperatorsPage> {
  bool _loading = true;
  bool _merging = false;
  Map<String, int> _operatorCounts = {};
  String? _sourceOperator;
  String? _targetOperator;
  String _mergeLog = '';

  @override
  void initState() {
    super.initState();
    _loadOperators();
  }

  Future<void> _loadOperators() async {
    setState(() => _loading = true);
    
    try {
      final counts = <String, int>{};
      final db = FirebaseFirestore.instance;
      
      // Count from items (operatorName and createdBy)
      final items = await db.collection('items').get();
      for (final doc in items.docs) {
        final data = doc.data();
        final operatorName = data['operatorName'] as String?;
        final createdBy = data['createdBy'] as String?;
        if (operatorName != null && operatorName.isNotEmpty) {
          counts[operatorName] = (counts[operatorName] ?? 0) + 1;
        }
        if (createdBy != null && createdBy.isNotEmpty && createdBy != operatorName) {
          counts[createdBy] = (counts[createdBy] ?? 0) + 1;
        }
      }
      
      // Skip audit_logs - they are append-only and preserve history
      
      // Count from cart_sessions
      final sessions = await db.collection('cart_sessions').get();
      for (final doc in sessions.docs) {
        final data = doc.data();
        final operatorName = data['operatorName'] as String?;
        if (operatorName != null && operatorName.isNotEmpty) {
          counts[operatorName] = (counts[operatorName] ?? 0) + 1;
        }
      }
      
      // Count from feedback
      final feedback = await db.collection('feedback').get();
      for (final doc in feedback.docs) {
        final data = doc.data();
        final submittedBy = data['submittedBy'] as String?;
        if (submittedBy != null && submittedBy.isNotEmpty) {
          counts[submittedBy] = (counts[submittedBy] ?? 0) + 1;
        }
        final voters = (data['voters'] as List<dynamic>?)?.cast<String>() ?? [];
        for (final voter in voters) {
          if (voter.isNotEmpty) {
            counts[voter] = (counts[voter] ?? 0) + 1;
          }
        }
      }
      
      // Count from library_items
      final libraryItems = await db.collection('library_items').get();
      for (final doc in libraryItems.docs) {
        final data = doc.data();
        final operatorName = data['operatorName'] as String?;
        final checkedOutBy = data['checkedOutBy'] as String?;
        if (operatorName != null && operatorName.isNotEmpty) {
          counts[operatorName] = (counts[operatorName] ?? 0) + 1;
        }
        if (checkedOutBy != null && checkedOutBy.isNotEmpty) {
          counts[checkedOutBy] = (counts[checkedOutBy] ?? 0) + 1;
        }
      }
      
      // Count from usage_logs
      final usageLogs = await db.collection('usage_logs').get();
      for (final doc in usageLogs.docs) {
        final data = doc.data();
        final operatorName = data['operatorName'] as String?;
        if (operatorName != null && operatorName.isNotEmpty) {
          counts[operatorName] = (counts[operatorName] ?? 0) + 1;
        }
      }
      
      setState(() {
        _operatorCounts = counts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading operators: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _performMerge() async {
    if (_sourceOperator == null || _targetOperator == null) return;
    if (_sourceOperator == _targetOperator) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Merge'),
        content: Text(
          'This will replace all occurrences of "$_sourceOperator" with "$_targetOperator" across:\n\n'
          '• Items (operatorName, createdBy)\n'
          '• Cart sessions\n'
          '• Usage logs\n'
          '• Feedback & votes\n'
          '• Library items\n\n'
          'Note: Audit logs are preserved for historical accuracy.\n\n'
          'This cannot be undone. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _merging = true;
      _mergeLog = 'Starting merge of "$_sourceOperator" → "$_targetOperator"...\n';
    });
    
    try {
      final db = FirebaseFirestore.instance;
      final source = _sourceOperator!;
      final target = _targetOperator!;
      
      // Merge in items
      _log('Checking items...');
      final items = await db.collection('items').get();
      int itemsUpdated = 0;
      for (final doc in items.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};
        
        if (data['operatorName'] == source) {
          updates['operatorName'] = target;
        }
        if (data['createdBy'] == source) {
          updates['createdBy'] = target;
        }
        
        if (updates.isNotEmpty) {
          await doc.reference.update(updates);
          itemsUpdated++;
        }
        
        // Also check lot_adjustments subcollection
        final adjustments = await doc.reference.collection('lot_adjustments').get();
        for (final adj in adjustments.docs) {
          final adjData = adj.data();
          if (adjData['operatorName'] == source) {
            await adj.reference.update({'operatorName': target});
          }
        }
      }
      _log('  Updated $itemsUpdated items');
      
      // Skip audit_logs - they are append-only for historical accuracy
      _log('Skipping audit logs (append-only, preserves history)');
      
      // Merge in cart_sessions
      _log('Checking cart sessions...');
      final sessions = await db.collection('cart_sessions').get();
      int sessionsUpdated = 0;
      for (final doc in sessions.docs) {
        if (doc.data()['operatorName'] == source) {
          await doc.reference.update({'operatorName': target});
          sessionsUpdated++;
        }
        
        // Also check lines subcollection
        final lines = await doc.reference.collection('lines').get();
        for (final line in lines.docs) {
          if (line.data()['operatorName'] == source) {
            await line.reference.update({'operatorName': target});
          }
        }
      }
      _log('  Updated $sessionsUpdated cart sessions');
      
      // Merge in feedback
      _log('Checking feedback...');
      final feedback = await db.collection('feedback').get();
      int feedbackUpdated = 0;
      int votesUpdated = 0;
      for (final doc in feedback.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};
        
        if (data['submittedBy'] == source) {
          updates['submittedBy'] = target;
          feedbackUpdated++;
        }
        
        final voters = (data['voters'] as List<dynamic>?)?.cast<String>() ?? [];
        if (voters.contains(source)) {
          final newVoters = voters.where((v) => v != source).toList();
          if (!newVoters.contains(target)) {
            newVoters.add(target);
          }
          updates['voters'] = newVoters;
          updates['voteCount'] = newVoters.length;
          votesUpdated++;
        }
        
        if (updates.isNotEmpty) {
          await doc.reference.update(updates);
        }
        
        // Also check comments subcollection
        final comments = await doc.reference.collection('comments').get();
        for (final comment in comments.docs) {
          if (comment.data()['author'] == source) {
            await comment.reference.update({'author': target});
          }
        }
      }
      _log('  Updated $feedbackUpdated feedback items, $votesUpdated votes');
      
      // Merge in library_items
      _log('Checking library items...');
      final libraryItems = await db.collection('library_items').get();
      int libraryUpdated = 0;
      for (final doc in libraryItems.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};
        
        if (data['operatorName'] == source) {
          updates['operatorName'] = target;
        }
        if (data['checkedOutBy'] == source) {
          updates['checkedOutBy'] = target;
        }
        if (data['createdBy'] == source) {
          updates['createdBy'] = target;
        }
        
        if (updates.isNotEmpty) {
          await doc.reference.update(updates);
          libraryUpdated++;
        }
      }
      _log('  Updated $libraryUpdated library items');
      
      // Merge in usage_logs
      _log('Checking usage logs...');
      final usageLogs = await db.collection('usage_logs').where('operatorName', isEqualTo: source).get();
      int usageLogsUpdated = 0;
      for (final doc in usageLogs.docs) {
        await doc.reference.update({'operatorName': target});
        usageLogsUpdated++;
      }
      _log('  Updated $usageLogsUpdated usage logs');
      
      _log('\n✓ Merge complete!');
      
      // Reload operators
      await _loadOperators();
      
      setState(() {
        _sourceOperator = null;
        _targetOperator = null;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merge completed successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _log('\n✗ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during merge: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _merging = false);
    }
  }

  void _log(String message) {
    setState(() {
      _mergeLog += '$message\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sortedOperators = _operatorCounts.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge Operator Names'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadOperators,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Merge all records from one operator name into another. '
                              'This updates items, sessions, feedback, and library items. '
                              'Audit logs are preserved for historical accuracy.',
                              style: TextStyle(color: cs.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Merge controls
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Source dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('From (will be removed):', 
                              style: TextStyle(fontWeight: FontWeight.w600, color: cs.error)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _sourceOperator,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText: 'Select operator',
                                filled: true,
                                fillColor: cs.errorContainer.withValues(alpha: 0.2),
                              ),
                              isExpanded: true,
                              items: sortedOperators.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text('${e.key} (${e.value})'),
                              )).toList(),
                              onChanged: _merging ? null : (v) => setState(() => _sourceOperator = v),
                            ),
                          ],
                        ),
                      ),
                      
                      // Arrow
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            const SizedBox(height: 32),
                            Icon(Icons.arrow_forward, color: cs.outline, size: 32),
                          ],
                        ),
                      ),
                      
                      // Target dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Into (will be kept):', 
                              style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _targetOperator,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText: 'Select operator',
                                filled: true,
                                fillColor: cs.primaryContainer.withValues(alpha: 0.2),
                              ),
                              isExpanded: true,
                              items: sortedOperators.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text('${e.key} (${e.value})'),
                              )).toList(),
                              onChanged: _merging ? null : (v) => setState(() => _targetOperator = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Error message if same
                  if (_sourceOperator != null && _targetOperator != null && _sourceOperator == _targetOperator)
                    Card(
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Text('Source and target must be different!', 
                              style: TextStyle(color: cs.onErrorContainer)),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Merge button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_sourceOperator != null && 
                                  _targetOperator != null && 
                                  _sourceOperator != _targetOperator && 
                                  !_merging)
                          ? _performMerge
                          : null,
                      icon: _merging 
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.merge),
                      label: Text(_merging ? 'Merging...' : 'Merge Operators'),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Merge log
                  if (_mergeLog.isNotEmpty) ...[
                    Text('Merge Log:', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _mergeLog,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Operator list
                    Text('All Operators (${sortedOperators.length}):', 
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Card(
                        child: ListView.separated(
                          itemCount: sortedOperators.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = sortedOperators[index];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: cs.primaryContainer,
                                child: Text(
                                  entry.key.isNotEmpty ? entry.key[0].toUpperCase() : '?',
                                  style: TextStyle(color: cs.onPrimaryContainer, fontSize: 14),
                                ),
                              ),
                              title: Text(entry.key),
                              trailing: Chip(
                                label: Text('${entry.value}'),
                                visualDensity: VisualDensity.compact,
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
}
