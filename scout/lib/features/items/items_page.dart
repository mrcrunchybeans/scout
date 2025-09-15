import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../dev/seed_lookups.dart';
import 'quick_use_sheet.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _db = FirebaseFirestore.instance;
  bool _busy = false; // show spinner & disable menu while seeding

  Future<void> _addSampleItem() async {
    final doc = _db.collection('items').doc();
    await doc.set({
      'name': 'Granola Bars',
      'unit': 'each',
      'qtyOnHand': 24,
      'minQty': 12,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsQuery = _db
        .collection('items')
        .orderBy('updatedAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SCOUT — Items'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Lookup tools',
            enabled: !_busy,
            onSelected: (key) async {
              setState(() => _busy = true);
              try {
                if (key == 'seed-once') {
                  await seedLookups();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Seeded (only empty collections).')),
                  );
                } else if (key == 'reseed-merge') {
                  await reseedLookupsMerge();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lookups upserted by code.')),
                  );
                } else if (key == 'reset-seed') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reset & seed lookups?'),
                      content: const Text('This will DELETE all lookup docs, then reseed.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await resetAndSeedLookups();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lookups reset & seeded.')),
                    );
                  }
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'seed-once',    child: Text('Seed (only if empty)')),
              PopupMenuItem(value: 'reseed-merge', child: Text('Reseed (merge by code)')),
              PopupMenuItem(value: 'reset-seed',   child: Text('Reset & seed (destructive)')),
            ],
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSampleItem,
        label: const Text('Add sample'),
        icon: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: itemsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Firestore error: ${snap.error}'));
          }
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
                trailing: IconButton(
                  tooltip: 'Quick use',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => QuickUseSheet(itemId: d.id, itemName: name),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
