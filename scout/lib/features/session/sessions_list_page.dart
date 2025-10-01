import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'cart_session_page.dart';

class SessionsListPage extends StatefulWidget {
  const SessionsListPage({super.key});

  @override
  State<SessionsListPage> createState() => _SessionsListPageState();
}

class _SessionsListPageState extends State<SessionsListPage> {
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    final openQ = db
        .collection('cart_sessions')
        .where('status', isEqualTo: 'open')
        .orderBy('updatedAt', descending: true)
        .limit(50);

    // Build query for completed sessions based on show deleted filter
    Query<Map<String, dynamic>> closedQ;
    if (_showDeleted) {
      closedQ = db
          .collection('cart_sessions')
          .where('status', whereIn: ['closed', 'deleted'])
          .orderBy('updatedAt', descending: true)
          .limit(50);
    } else {
      closedQ = db
          .collection('cart_sessions')
          .where('status', isEqualTo: 'closed')
          .orderBy('closedAt', descending: true)
          .limit(50);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sessions'),
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(_showDeleted ? Icons.visibility_off : Icons.visibility),
              tooltip: _showDeleted ? 'Hide Deleted' : 'Show Deleted',
              onPressed: () {
                setState(() {
                  _showDeleted = !_showDeleted;
                });
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.edit_note), text: 'Open Drafts'),
              Tab(
                icon: const Icon(Icons.history), 
                text: _showDeleted ? 'All Sessions' : 'Completed'
              ),
            ],
            indicatorWeight: 3,
            labelStyle: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('New Session'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartSessionPage()),
            );
          },
        ),
        body: TabBarView(
          children: [
            _SessionsBucket(query: openQ, isOpenBucket: true, showDeleted: false),
            _SessionsBucket(query: closedQ, isOpenBucket: false, showDeleted: _showDeleted),
          ],
        ),
      ),
    );
  }
}

class _SessionsBucket extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final bool isOpenBucket;
  final bool showDeleted;
  const _SessionsBucket({
    required this.query, 
    required this.isOpenBucket,
    required this.showDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Error loading sessions', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${snap.error}', style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          );
        }
        
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOpenBucket ? Icons.note_add : Icons.history, 
                  size: 64, 
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  isOpenBucket ? 'No draft sessions' : 'No completed sessions',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isOpenBucket 
                    ? 'Create a new session to get started'
                    : 'Completed sessions will appear here',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i];
            final m = d.data();
            return _SessionCard(
              doc: d,
              data: m,
              isOpenBucket: isOpenBucket,
              showDeleted: showDeleted,
            );
          },
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic> data;
  final bool isOpenBucket;
  final bool showDeleted;

  const _SessionCard({
    required this.doc,
    required this.data,
    required this.isOpenBucket,
    required this.showDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['interventionName'] ?? 'Untitled Session') as String;
    final location = data['locationText'] as String?;
    final notes = data['notes'] as String?;
    final status = ((data['status'] ?? 'open') as String).toUpperCase();
    final isDeleted = status == 'DELETED';
    
    final tsStart = data['startedAt'];
    final tsUpdated = data['updatedAt'];
    final tsClosed = data['closedAt'];
    
    DateTime? startDate, lastActivity, closedDate;
    if (tsStart is Timestamp) startDate = tsStart.toDate();
    if (tsUpdated is Timestamp) lastActivity = tsUpdated.toDate();
    if (tsClosed is Timestamp) closedDate = tsClosed.toDate();
    
    final ml = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDeleted ? 0.5 : 1,
      child: Container(
        decoration: isDeleted ? BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.red.shade300,
            width: 1,
          ),
        ) : null,
        child: Opacity(
          opacity: isDeleted ? 0.6 : 1.0,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isDeleted ? null : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CartSessionPage(sessionId: doc.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Header row with title and status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: isDeleted ? TextDecoration.lineThrough : null,
                            color: isDeleted ? theme.colorScheme.onSurfaceVariant : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (location != null && location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOpenBucket 
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOpenBucket
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Notes section
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.note,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notes,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Date information and actions
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (startDate != null) ...[
                          _DateInfo(
                            icon: Icons.play_circle_outline,
                            label: 'Started',
                            date: startDate,
                            materialLocalizations: ml,
                          ),
                        ],
                        if (isOpenBucket && lastActivity != null) ...[
                          const SizedBox(height: 4),
                          _DateInfo(
                            icon: Icons.update,
                            label: 'Updated',
                            date: lastActivity,
                            materialLocalizations: ml,
                            isRelative: true,
                          ),
                        ],
                        if (!isOpenBucket && closedDate != null) ...[
                          const SizedBox(height: 4),
                          _DateInfo(
                            icon: Icons.check_circle_outline,
                            label: 'Completed',
                            date: closedDate,
                            materialLocalizations: ml,
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isOpenBucket) ...[
                        IconButton(
                          tooltip: 'Delete draft',
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () => _showDeleteConfirmation(context, doc),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Resume'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CartSessionPage(sessionId: doc.id),
                              ),
                            );
                          },
                        ),
                      ] else ...[
                        IconButton(
                          tooltip: 'Delete completed session',
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () => _showDeleteCompletedConfirmation(context, doc),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: const Text('View'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CartSessionPage(sessionId: doc.id),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  void _showDeleteConfirmation(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft Session?'),
        content: const Text(
          'This will permanently remove this session and all its items. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        // Mark session as deleted instead of actually deleting it (due to permission restrictions)
        final db = FirebaseFirestore.instance;
        await db.collection('cart_sessions').doc(doc.id).set({
          'status': 'deleted',
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedBy': 'user',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        // Mark lines as deleted instead of deleting them
        final linesQuery = await doc.reference.collection('lines').get();
        final batch = db.batch();
        for (final lineDoc in linesQuery.docs) {
          batch.set(lineDoc.reference, {
            'deleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Draft session deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting session: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _showDeleteCompletedConfirmation(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Completed Session?'),
        content: const Text(
          'This will permanently remove this session and reverse its inventory deductions.\n\n'
          'Items used in this session will be added back to inventory. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete & Reverse'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        await _deleteCompletedSessionWithInventoryReverse(doc);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Completed session deleted and inventory restored'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting session: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  static Future<void> _deleteCompletedSessionWithInventoryReverse(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final db = FirebaseFirestore.instance;
    final sessionId = doc.id;
    
    debugPrint('Starting deletion with inventory reversal for session: $sessionId');
    
    // First, reverse the inventory deductions
    await _reverseSessionInventory(sessionId, db);
    
    // Mark session as deleted instead of actually deleting it (due to permission restrictions)
    await db.collection('cart_sessions').doc(sessionId).set({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': 'user', // You could add actual user ID here if needed
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // Mark lines as deleted instead of deleting them
    final linesQuery = await doc.reference.collection('lines').get();
    final batch = db.batch();
    for (final lineDoc in linesQuery.docs) {
      batch.set(lineDoc.reference, {
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> _reverseSessionInventory(String sessionId, FirebaseFirestore db) async {
    // Get the session document to access the lines and their quantities
    final sessionDoc = await db.collection('cart_sessions').doc(sessionId).get();
    if (!sessionDoc.exists) {
      debugPrint('Session not found for reversal: $sessionId');
      return;
    }

    final sessionData = sessionDoc.data()!;
    final sessionStatus = sessionData['status'] as String?;
    
    // Only reverse inventory for completed sessions (not drafts)
    // Check for both 'closed' and 'deleted' since deleted sessions were originally closed
    if (sessionStatus != 'closed' && sessionStatus != 'deleted') {
      debugPrint('Session is not closed/deleted, no inventory to reverse: $sessionStatus');
      return;
    }

    // Get the usage logs for this session to know what was actually deducted
    final usageLogsQuery = await db.collection('usage_logs')
        .where('sessionId', isEqualTo: sessionId)
        .where('isReversal', isEqualTo: false)
        .get();
    
    debugPrint('Found ${usageLogsQuery.docs.length} usage logs for session $sessionId');
    
    // Group by lot/item to sum up total quantities to reverse
    final Map<String, Map<String, dynamic>> lotReversals = {};
    
    for (final usageDoc in usageLogsQuery.docs) {
      final usageData = usageDoc.data();
      final itemId = usageData['itemId'] as String?;
      final lotId = usageData['lotId'] as String?;
      final qtyUsed = (usageData['qtyUsed'] as num?)?.toDouble() ?? 0.0;
      
      debugPrint('Usage log: itemId=$itemId, lotId=$lotId, qtyUsed=$qtyUsed');
      
      if (itemId == null || qtyUsed <= 0) continue;
      
      final key = lotId ?? itemId;
      if (!lotReversals.containsKey(key)) {
        lotReversals[key] = {
          'itemId': itemId,
          'lotId': lotId,
          'totalToReverse': 0.0,
          'unit': usageData['unit'] as String? ?? 'each',
        };
      }
      lotReversals[key]!['totalToReverse'] = 
          (lotReversals[key]!['totalToReverse'] as double) + qtyUsed;
    }

    debugPrint('Grouped reversals: ${lotReversals.length} items/lots to reverse');

    // Process each lot/item reversal in separate transactions
    for (final reversal in lotReversals.values) {
      final itemId = reversal['itemId'] as String;
      final lotId = reversal['lotId'] as String?;
      final totalToReverse = reversal['totalToReverse'] as double;
      
      debugPrint('Processing reversal: itemId=$itemId, lotId=$lotId, totalToReverse=$totalToReverse');
      
      if (totalToReverse <= 0) continue;

      await db.runTransaction((tx) async {
        if (lotId != null) {
          // Reverse lot-based deduction
          final lotRef = db.collection('items').doc(itemId).collection('lots').doc(lotId);
          final lotDoc = await tx.get(lotRef);
          
          if (lotDoc.exists) {
            final currentQty = ((lotDoc.data()?['qtyRemaining'] as num?) ?? 0).toDouble();
            final newQty = currentQty + totalToReverse;
            
            debugPrint('Reversing lot: currentQty=$currentQty, newQty=$newQty');
            
            tx.set(lotRef, {
              'qtyRemaining': newQty,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            debugPrint('Lot document not found: $itemId/$lotId');
          }
        } else {
          // Reverse item-based deduction  
          final itemRef = db.collection('items').doc(itemId);
          final itemDoc = await tx.get(itemRef);
          
          if (itemDoc.exists) {
            final currentQty = ((itemDoc.data()?['qtyOnHand'] as num?) ?? 0).toDouble();
            final newQty = currentQty + totalToReverse;
            
            debugPrint('Reversing item: currentQty=$currentQty, newQty=$newQty');
            
            tx.set(itemRef, {
              'qtyOnHand': newQty,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            debugPrint('Item document not found: $itemId');
          }
        }
      });
    }
    
    // Create reversal entries for audit trail based on usage logs
    final batch = db.batch();
    for (final usageDoc in usageLogsQuery.docs) {
      final usageData = usageDoc.data();
      final qtyUsed = (usageData['qtyUsed'] as num?)?.toDouble() ?? 0.0;
      
      if (qtyUsed <= 0) continue;
      
      // Create a reversal entry in usage_logs
      final reversalRef = db.collection('usage_logs').doc();
      batch.set(reversalRef, {
        'sessionId': sessionId,
        'itemId': usageData['itemId'],
        'lotId': usageData['lotId'],
        'qtyUsed': -qtyUsed, // Negative to indicate reversal
        'unit': usageData['unit'],
        'usedAt': FieldValue.serverTimestamp(),
        'interventionId': usageData['interventionId'],
        'interventionName': usageData['interventionName'],
        'grantId': usageData['grantId'],
        'notes': 'Reversal: Session deleted',
        'originalUsageId': usageDoc.id,
        'isReversal': true,
        'operatorName': usageData['operatorName'],
        'createdBy': sessionData['createdBy'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

class _DateInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final DateTime date;
  final MaterialLocalizations materialLocalizations;
  final bool isRelative;

  const _DateInfo({
    required this.icon,
    required this.label,
    required this.date,
    required this.materialLocalizations,
    this.isRelative = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    
    String dateText;
    if (isRelative) {
      final diff = now.difference(date);
      if (diff.inDays > 0) {
        dateText = '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        dateText = '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        dateText = '${diff.inMinutes}m ago';
      } else {
        dateText = 'Just now';
      }
    } else {
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        dateText = 'Today';
      } else if (date.year == now.year && 
                 date.month == now.month && 
                 date.day == now.day - 1) {
        dateText = 'Yesterday';
      } else {
        dateText = materialLocalizations.formatShortDate(date);
      }
    }

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          dateText,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}