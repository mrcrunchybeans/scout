import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../main.dart';
import '../../widgets/brand_logo.dart';
import '../items/quick_use_sheet.dart';
import '../items/items_page.dart';
import '../items/new_item_page.dart';
import '../items/item_detail_page.dart';
import '../session/cart_session_page.dart';
import '../session/sessions_list_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // --- Server-side flag queries (composite indexes added previously) ---
    final lowQ = db
        .collection('items')
        .where('flagLow', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(100);

    final expiringQ = db
        .collection('items')
        .where('flagExpiringSoon', isEqualTo: true)
        .orderBy('earliestExpiresAt') // ascending = soonest first
        .limit(100);

    final staleQ = db
        .collection('items')
        .where('flagStale', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(100);

    final excessQ = db
        .collection('items')
        .where('flagExcess', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(100);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 200,
        titleSpacing: 0,
        title: const Center(child: BrandLogo(height: 120)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              icon: Icon(Icons.brightness_6, color: Theme.of(context).colorScheme.primary),
              tooltip: 'Toggle theme',
              onPressed: () {
                ThemeModeNotifier.instance.toggle();
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Top action tiles
          Row(
            children: [
              Expanded(
                child: _DashboardTile(
                  icon: Icons.inventory_2,
          color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1FCFC0) // dark teal
            : Colors.teal,
                  label: 'Inventory',
                  onTap: () {
                    // Action sheet for inventory tasks
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (ctx) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.inventory_2,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1FCFC0)
                                    : Colors.teal,
                              ),
                              title: const Text('Manage Inventory'),
                              subtitle: const Text('View and edit all items'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ItemsPage()),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.add_box, color: Colors.green),
                              title: const Text('Add New Item'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const NewItemPage()),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.playlist_add,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF4FC3F7) // lighter blue for dark
                                    : Colors.blue,
                              ),
                              title: const Text('Add New Batch/Lot'),
                              subtitle: const Text('From item detail'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ItemsPage()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardTile(
                  icon: Icons.playlist_add_check_circle,
                  color: Colors.indigo,
                  label: 'Start Cart Session',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CartSessionPage()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardTile(
                  icon: Icons.history,
                  color: Colors.orange,
                  label: 'Sessions',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SessionsListPage()),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Buckets
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
            showEarliestExpiry: true,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Stale (no recent use)',
            icon: Icons.inbox_outlined,
      color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF607D8B) // blueGrey for dark
        : Colors.blueGrey,
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
            '• Sorting “Expiring soon” uses earliest lot expiration; if you ever see an index error link, open it to auto-create the index.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// --- Modern glassy dashboard tile ---
class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _DashboardTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Custom tile color: rgb(179, 224, 215)
    const customTileColor = Color.fromRGBO(67, 195, 170, 1);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color.fromARGB(255, 162, 224, 212),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : customTileColor.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white12 : customTileColor.withValues(alpha: 0.10),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: customTileColor.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(icon, size: 38, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 0.2,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ),
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
    // Use a lighter background for the bucket cards
    return Card(
      elevation: 1,
      color: const Color.fromARGB(255, 218, 255, 246), // very light mint/teal
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
              if (docs.isEmpty) const ListTile(title: Text('Nothing here — nice!')),
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
