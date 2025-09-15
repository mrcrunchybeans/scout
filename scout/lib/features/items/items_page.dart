import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _db = FirebaseFirestore.instance;

  Future<void> _addSampleItem() async {
    final doc = _db.collection('items').doc(); // auto id
    await doc.set({
      'name': 'Granola Bars',
      'unit': 'each',
      'qtyOnHand': 24,
      'minQty': 12,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _logUse({
    required String itemId,
    required num qty,
  }) async {
    final itemRef = _db.collection('items').doc(itemId);
    final usageRef = _db.collection('usage_logs').doc();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) throw Exception('Item not found');

      final data = snap.data() as Map<String, dynamic>;
      final currentQty = (data['qtyOnHand'] ?? 0) as num;
      final newQty = currentQty - qty;
      if (newQty < 0) throw Exception('Insufficient stock');

      tx.update(itemRef, {
        'qtyOnHand': newQty,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUsedAt': FieldValue.serverTimestamp(),
      });

      tx.set(usageRef, {
        'itemId': itemId,
        'qtyUsed': qty,
        'usedAt': FieldValue.serverTimestamp(),
        // placeholders for future fields:
        'whereLocationId': null,
        'grantId': null,
        'forUseType': null, // 'staff' | 'patient'
        'userId': null,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsQuery = _db
        .collection('items')
        .orderBy('updatedAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('SCOUT — Items')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSampleItem,
        label: const Text('Add sample'),
        icon: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: itemsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No items yet. Tap “Add sample”.'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;
              final name = (data['name'] ?? 'Unnamed') as String;
              final qty = (data['qtyOnHand'] ?? 0).toString();
              final minQty = (data['minQty'] ?? 0).toString();

              return ListTile(
                title: Text(name),
                subtitle: Text('On hand: $qty • Min: $minQty'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Use 1',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () async {
                        try {
                          await _logUse(itemId: d.id, qty: 1);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Use 5',
                      icon: const Icon(Icons.remove_circle),
                      onPressed: () async {
                        try {
                          await _logUse(itemId: d.id, qty: 5);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
