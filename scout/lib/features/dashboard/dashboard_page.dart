import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../main.dart' as main;
import '../../widgets/brand_logo.dart';
import '../items/items_page.dart';
import '../items/new_item_page.dart';
import '../items/item_detail_page.dart';
import '../items/add_audit_inventory_page.dart';
import '../items/bulk_inventory_entry_page.dart';
import '../session/cart_session_page.dart';
import '../session/sessions_list_page.dart';
import 'package:scout/widgets/operator_chip.dart';
import 'package:scout/utils/admin_pin.dart';
import '../admin/admin_page.dart';
import '../reports/usage_report_page.dart';
import '../audit/audit_logs_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/scout dash logo light mode.png'), context);
    precacheImage(const AssetImage('assets/images/scout dash logo dark mode.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final colorScheme = Theme.of(context).colorScheme;

    // --- Server-side flag queries ---
    final lowQ = db
        .collection('items')
        .where('flagLow', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(100);

    final expiringQ = db
        .collection('items')
        .where('flagExpiringSoon', isEqualTo: true)
        .orderBy('earliestExpiresAt')
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
    // NEW: operator chip
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: OperatorChip(),
    ),
    PopupMenuButton<String>(
      onSelected: (v) async {
        final ctx = context; // capture-context for lint safety
        if (v == 'reports') {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => const UsageReportPage()));
        } else if (v == 'admin') {
          final ok = await AdminPin.ensure(ctx); // shows PIN dialog if needed
          if (!ctx.mounted || !ok) return;
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => const AdminPage()));
        } else if (v == 'theme') {
          main.ThemeModeNotifier.instance.toggle();
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'theme', child: Text('Toggle Theme')),
        const PopupMenuItem(value: 'reports', child: Text('Usage Reports')),
        const PopupMenuItem(value: 'admin', child: Text('Admin / Config')),
      ],
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
                  color: colorScheme.tertiary,
                  label: 'Inventory',
                  onTap: () {
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
                                Icons.qr_code_scanner,
                                color: colorScheme.onSurface,
                              ),
                              title: const Text('Add/Audit Inventory'),
                              subtitle: const Text('Scan items to add or adjust stock'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const AddAuditInventoryPage()),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.inventory_2_outlined,
                                color: colorScheme.onSurface,
                              ),
                              title: const Text('Bulk Inventory Entry'),
                              subtitle: const Text('Quick entry for shopping - scan multiple items'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const BulkInventoryEntryPage()),
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.inventory_2,
                                color: colorScheme.onSurface,
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
                              leading: Icon(
                                Icons.add_box,
                                color: colorScheme.onSurface,
                              ),
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
                                color: colorScheme.onSurface,
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
                            ListTile(
                              leading: Icon(
                                Icons.history,
                                color: colorScheme.onSurface,
                              ),
                              title: const Text('Audit Logs'),
                              subtitle: const Text('View all inventory changes'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const AuditLogsPage()),
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
                  color: colorScheme.primary,
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
                  color: colorScheme.secondary,
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
            color: colorScheme.error,
            query: lowQ,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Expiring soon',
            icon: Icons.schedule,
            color: colorScheme.secondary,
            query: expiringQ,
            showEarliestExpiry: true,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Stale (no recent use)',
            icon: Icons.inbox_outlined,
            color: colorScheme.tertiary,
            query: staleQ,
            showLastUsed: true,
          ),
          const SizedBox(height: 12),
          _BucketSection(
            title: 'Excess',
            icon: Icons.inventory,
            color: colorScheme.primary,
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

// --- Dashboard tile now using color scheme ---
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
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha:0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: colorScheme.outline,
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
                  color: colorScheme.surfaceContainerHighest,
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
                  color: colorScheme.onSurface,
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
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
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
    final colorScheme = Theme.of(context).colorScheme;

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
        icon: Icon(Icons.remove_circle_outline, color: colorScheme.onSurface),
        label: Text('Quick use', style: TextStyle(color: colorScheme.onSurface)),
        onPressed: () async {
          await _showQuickAdjustSheet(context, id, name);
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

  Future<void> _showQuickAdjustSheet(BuildContext context, String itemId, String itemName) async {
    try {
      // Get lots for this item, sorted by FEFO (earliest expiration first)
      final lotsQuery = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .collection('lots')
          .where('qtyRemaining', isGreaterThan: 0)
          .get();

      if (lotsQuery.docs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No lots available for this item')),
          );
        }
        return;
      }

      // Sort lots by effective expiration date (FEFO)
      final lots = lotsQuery.docs.map((doc) {
        final data = doc.data();
        final expiresAt = data['expiresAt'] is Timestamp ? (data['expiresAt'] as Timestamp).toDate() : null;
        final openAt = data['openAt'] is Timestamp ? (data['openAt'] as Timestamp).toDate() : null;
        final expiresAfterOpenDays = data['expiresAfterOpenDays'] as int?;
        
        DateTime? effectiveExpiry;
        if (openAt != null && expiresAfterOpenDays != null && expiresAfterOpenDays > 0) {
          final afterOpen = DateTime(openAt.year, openAt.month, openAt.day).add(Duration(days: expiresAfterOpenDays));
          if (expiresAt != null) {
            effectiveExpiry = afterOpen.isBefore(expiresAt) ? afterOpen : expiresAt;
          } else {
            effectiveExpiry = afterOpen;
          }
        } else {
          effectiveExpiry = expiresAt;
        }

        return {
          'id': doc.id,
          'data': data,
          'effectiveExpiry': effectiveExpiry,
        };
      }).toList();

      // Sort by effective expiration (nulls last)
      lots.sort((a, b) {
        final ea = a['effectiveExpiry'] as DateTime?;
        final eb = b['effectiveExpiry'] as DateTime?;
        if (ea == null && eb == null) return 0;
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.compareTo(eb);
      });

      // Use the first lot (FEFO)
      final firstLot = lots.first;
      final lotId = firstLot['id'] as String;
      final lotData = firstLot['data'] as Map<String, dynamic>;
      final qtyRemaining = (lotData['qtyRemaining'] ?? 0) as num;
      final alreadyOpened = lotData['openAt'] != null;

      // Show the adjust sheet
      if (context.mounted) {
        await showAdjustSheet(context, itemId, lotId, qtyRemaining, alreadyOpened);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading lots: $e')),
        );
      }
    }
  }
}