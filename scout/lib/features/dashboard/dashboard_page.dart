import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../items/quick_use_sheet.dart';
import '../items/item_detail_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // --- Server-side flag queries (no composite indexes needed) ---
    final lowQ = db.collection('items')
      .where('flagLow', isEqualTo: true)
      .orderBy('updatedAt', descending: true) // safe with equality filter
      .limit(100);

    final expiringQ = db.collection('items')
      .where('flagExpiringSoon', isEqualTo: true)
      // If you want a nice sort, try earliestExpiresAt; may prompt for an index.
      // .orderBy('earliestExpiresAt')
      .orderBy('earliestExpiresAt')
      .limit(100);

    final staleQ = db.collection('items')
      .where('flagStale', isEqualTo: true)
      .orderBy('updatedAt', descending: true)
      .limit(100);

    final excessQ = db.collection('items')
      .where('flagExcess', isEqualTo: true)
      .orderBy('updatedAt', descending: true)
      .limit(100);

    return Scaffold(
      appBar: AppBar(title: const Text('SCOUT — Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BucketSection(
            title: 'Low stock',
            icon: Icons.arrow_downward,
            color: Colors.red,
            query: lowQ,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Expiring soon',
            icon: Icons.schedule,
            color: Colors.orange,
            query: expiringQ,
            // show earliestExpiresAt in row subtitle
            showEarliestExpiry: true,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Stale (no recent use)',
            icon: Icons.inbox_outlined,
            color: Colors.blueGrey,
            query: staleQ,
            showLastUsed: true,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Excess',
            icon: Icons.inventory,
            color: Colors.green,
            query: excessQ,
          ),
          const SizedBox(height: 24),
          Text(
            'Notes:\n'
            '• Buckets are computed by Cloud Functions and updated automatically.\n'
            '• If you later sort Expiring by earliestExpiresAt and see an index error link, '
            'open it to auto-create the composite index.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BucketSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Query<Map<String, dynamic>> query;
  final bool showEarliestExpiry;
  final bool showLastUsed;

  const _BucketSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.query,
    this.showEarliestExpiry = false,
    this.showLastUsed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return ListTile(
              leading: Icon(icon, color: color),
              title: Text(title),
              subtitle: Text('Error: ${snap.error}'),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return ListTile(
              leading: Icon(icon, color: color),
              title: Text(title),
              subtitle: const Text('Loading...'),
              trailing: const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];

          return ExpansionTile(
            leading: Icon(icon, color: color),
            title: Text(title),
            subtitle: Text('${docs.length} item(s)'),
            children: [
              if (docs.isEmpty)
                const ListTile(title: Text('Nothing here — nice!')),
              for (final d in docs)
                _ItemRow(
                  id: d.id,
                  data: d.data(),
                  showEarliestExpiry: showEarliestExpiry,
                  showLastUsed: showLastUsed,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool showEarliestExpiry;
  final bool showLastUsed;

  const _ItemRow({
    required this.id,
    required this.data,
    required this.showEarliestExpiry,
    required this.showLastUsed,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Unnamed') as String;
    final qty = (data['qtyOnHand'] ?? 0) as num;
    final minQty = (data['minQty'] ?? 0) as num;

    final tsEarliest = data['earliestExpiresAt'];
    final earliestExpiresAt = (tsEarliest is Timestamp) ? tsEarliest.toDate() : null;

    final tsLastUsed = data['lastUsedAt'];
    final lastUsedAt = (tsLastUsed is Timestamp) ? tsLastUsed.toDate() : null;

    String sub = 'On hand: $qty • Min: $minQty';
    if (showEarliestExpiry && earliestExpiresAt != null) {
      sub += ' • Exp: ${MaterialLocalizations.of(context).formatFullDate(earliestExpiresAt)}';
    }
    if (showLastUsed && lastUsedAt != null) {
      sub += ' • Last used: ${MaterialLocalizations.of(context).formatFullDate(lastUsedAt)}';
    }

    return ListTile(
      title: Text(name),
      subtitle: Text(sub),
      // Trailing = Quick Use (unchanged)
      trailing: TextButton.icon(
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Quick use'),
        onPressed: () async {
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => QuickUseSheet(itemId: id, itemName: name),
          );
        },
      ),
      // Tap = go to Item Detail
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailPage(itemId: id, itemName: name),
          ),
        );
      },
    );
  }
}

