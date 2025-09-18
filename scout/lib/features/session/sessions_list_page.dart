import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'cart_session_page.dart';

class SessionsListPage extends StatelessWidget {
  const SessionsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    final openQ = db
        .collection('cart_sessions')
        .where('status', isEqualTo: 'open')
        .orderBy('updatedAt', descending: true)
        .limit(50);

    final closedQ = db
        .collection('cart_sessions')
        .where('status', isEqualTo: 'closed')
        .orderBy('closedAt', descending: true)
        .limit(50);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sessions'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Open drafts'),
            Tab(text: 'Recent closed'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New session'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartSessionPage()),
            );
          },
        ),
        body: TabBarView(
          children: [
            _SessionsBucket(query: openQ, isOpenBucket: true),
            _SessionsBucket(query: closedQ, isOpenBucket: false),
          ],
        ),
      ),
    );
  }
}

class _SessionsBucket extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final bool isOpenBucket;
  const _SessionsBucket({required this.query, required this.isOpenBucket});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(isOpenBucket ? 'No open drafts' : 'No recent sessions'),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['interventionName'] ?? 'Untitled session') as String;
            final status = ((m['status'] ?? 'open') as String).toUpperCase();
            final tsStart = m['startedAt'];
            final tsUpdated = m['updatedAt'];
            final tsClosed = m['closedAt'];

            String sub = '';
            final ml = MaterialLocalizations.of(ctx);
            if (tsStart is Timestamp) sub += 'Started: ${ml.formatFullDate(tsStart.toDate())} • ';
            if (isOpenBucket && tsUpdated is Timestamp) {
              sub += 'Updated: ${ml.formatFullDate(tsUpdated.toDate())}';
            }
            if (!isOpenBucket && tsClosed is Timestamp) {
              sub += 'Closed: ${ml.formatFullDate(tsClosed.toDate())}';
            }

            return ListTile(
              title: Text(name),
              subtitle: Text(sub.isEmpty ? status : '[$status • $sub['),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOpenBucket)
                    IconButton(
                      tooltip: 'Delete draft',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete draft?'),
                            content: const Text('This will remove the session and its lines.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _deleteSessionWithLines(d.reference);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Draft deleted')));
                          }
                        }
                      },
                    ),
                  TextButton.icon(
                    icon: Icon(isOpenBucket ? Icons.open_in_new : Icons.visibility),
                    label: Text(isOpenBucket ? 'Resume' : 'View'),
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => CartSessionPage(sessionId: d.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _deleteSessionWithLines(DocumentReference<Map<String, dynamic>> sref) async {
    // delete subcollection lines (paged)
    const page = 300;
    while (true) {
      final lines = await sref.collection('lines').limit(page).get();
      if (lines.docs.isEmpty) break;
      final batch = sref.firestore.batch();
      for (final l in lines.docs) {
        batch.delete(l.reference);
      }
      await batch.commit();
    }
    await sref.delete();
  }
}
