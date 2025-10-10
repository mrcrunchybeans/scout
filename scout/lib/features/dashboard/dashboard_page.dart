import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../main.dart' as main;
import '../../widgets/brand_logo.dart';
import '../../services/version_service.dart';
import '../items/new_item_page.dart';
import '../items/item_detail_page.dart';
import '../items/add_audit_inventory_page.dart';
import '../items/bulk_inventory_entry_page.dart';
import '../session/cart_session_page.dart';
import 'package:scout/widgets/operator_chip.dart';
import 'package:scout/utils/admin_pin.dart';
import '../admin/admin_page.dart';
import '../reports/usage_report_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    // Clear version cache on dashboard load to ensure fresh version display
    VersionService.clearCache();
    // Check if operator name is set, prompt if not
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOperatorName();
    });
  }

  Future<void> _checkOperatorName() async {
    final currentName = main.OperatorStore.name.value;
    if (currentName == null || currentName.isEmpty) {
      if (!mounted) return;
      await _showOperatorDialog();
    }
  }

  Future<void> _showOperatorDialog() async {
    final controller = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    final picked = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // Make it required
      builder: (_) => AlertDialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        title: Text(
          'Welcome to SCOUT',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Please enter your name to get started.',
              style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Your name',
                hintText: 'e.g. Mephibosheth',
                labelStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
                hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(width: 1.5, color: colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Get Started'),
          ),
        ],
      ),
    );

    if (picked != null && picked.isNotEmpty && mounted) {
      await main.OperatorStore.set(picked);
    } else if (picked != null && picked.isEmpty && mounted) {
      // If they somehow submit empty, show again
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkOperatorName();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload logo images for better performance
    precacheImage(const AssetImage('assets/images/scout dash logo light mode.png'), context);
    precacheImage(const AssetImage('assets/images/scout dash logo dark mode.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final colorScheme = Theme.of(context).colorScheme;

  // --- Server-side flag queries for lists ---
  final lowQ = db
    .collection('items')
    .where('flagLow', isEqualTo: true)
    .where('archived', isEqualTo: false);

  final expiringQ = db
    .collection('items')
    .where('flagExpiringSoon', isEqualTo: true)
    .where('archived', isEqualTo: false)
    .orderBy('earliestExpiresAt');

  final staleQ = db
    .collection('items')
    .where('flagStale', isEqualTo: true)
    .where('archived', isEqualTo: false);

  final expiredQ = db
    .collection('items')
    .where('flagExpired', isEqualTo: true)
    .where('archived', isEqualTo: false);

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
        } else if (v == 'recalc-stats') {
          final ok = await AdminPin.ensure(ctx);
          if (!ctx.mounted || !ok) return;
          final confirm = await showDialog<bool>(
            context: ctx,
            builder: (_) => AlertDialog(
              title: const Text('Recalculate Dashboard Counts?'),
              content: const Text('This recomputes low/expiring/stale/expired counts from all items.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recalculate')),
              ],
            ),
          );
          if (confirm == true) {
            try {
              await FirebaseFunctions.instance.httpsCallable('recalcDashboardStatsManual')();
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Recalculation started')));
            } catch (e) {
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $e')));
            }
          }
        } else if (v == 'theme') {
          main.ThemeModeNotifier.instance.toggle();
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'theme', child: Text('Toggle Theme')),
        const PopupMenuItem(value: 'reports', child: Text('Usage Reports')),
        const PopupMenuItem(value: 'admin', child: Text('Admin / Config')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'recalc-stats', child: Text('Recalc Dashboard Counts')),
      ],
    ),
  ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Primary Action Buttons - Large and prominent (2x3 grid)
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.inventory_2_outlined,
                  color: colorScheme.primary,
                  label: 'Bulk Entry',
                  subtitle: 'Scan multiple items',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BulkInventoryEntryPage()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.qr_code_scanner,
                  color: colorScheme.secondary,
                  label: 'Add/Audit',
                  subtitle: 'Single item entry',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddAuditInventoryPage()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.playlist_add_check_circle,
                  color: colorScheme.tertiary,
                  label: 'Cart Session',
                  subtitle: 'Start session',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CartSessionPage()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.inventory_2,
                  color: colorScheme.primary.withValues(alpha: 0.8), // Darker version of primary
                  label: 'View Items',
                  subtitle: 'Browse inventory',
                  onTap: () {
                    context.go('/items');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.list_alt,
                  color: Colors.blue.shade600,
                  label: 'Sessions',
                  subtitle: 'View session history',
                  onTap: () {
                    context.go('/sessions');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryActionButton(
                  icon: Icons.add_box,
                  color: Colors.green.shade600,
                  label: 'New Item',
                  subtitle: 'Add to inventory',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NewItemPage()),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Welcome message
          Center(
            child: Column(
              children: [
                Text(
                  'Welcome to SCOUT',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your inventory with ease',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Inventory Status Overview
          Text(
            'Quick Status',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('meta').doc('dashboard_stats').snapshots(),
            builder: (context, statsSnap) {
              final stats = statsSnap.data?.data();
              final lowCount = (stats?['low'] as num?)?.toInt() ?? 0;
              final expiringCount = (stats?['expiring'] as num?)?.toInt() ?? 0;
              final staleCount = (stats?['stale'] as num?)?.toInt() ?? 0;
              final expiredCount = (stats?['expired'] as num?)?.toInt() ?? 0;
              final updatedAtTs = stats?['updatedAt'];
              DateTime? updatedAt;
              if (updatedAtTs is Timestamp) {
                updatedAt = updatedAtTs.toDate();
              }
              String updatedLabel() {
                if (updatedAt == null) return 'Updated: —';
                final dt = updatedAt.toLocal();
                String two(int n) => n.toString().padLeft(2, '0');
                final y = dt.year.toString();
                final m = two(dt.month);
                final d = two(dt.day);
                final hh = two(dt.hour);
                final mm = two(dt.minute);
                return 'Updated at $y-$m-$d $hh:$mm';
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatusCardStatic(
                          title: 'Low Stock',
                          count: lowCount,
                          icon: Icons.arrow_downward,
                          color: colorScheme.error,
                          filterType: 'low',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatusCardStatic(
                          title: 'Expiring Soon',
                          count: expiringCount,
                          icon: Icons.schedule,
                          color: colorScheme.secondary,
                          filterType: 'expiring',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatusCardStatic(
                          title: 'Stale',
                          count: staleCount,
                          icon: Icons.inbox_outlined,
                          color: colorScheme.tertiary,
                          filterType: 'stale',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatusCardStatic(
                          title: 'Expired',
                          count: expiredCount,
                          icon: Icons.warning,
                          color: Colors.red.shade700,
                          filterType: 'expired',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      updatedLabel(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatusCard(
                  title: 'Stale',
                  count: 0,
                  icon: Icons.inbox_outlined,
                  color: colorScheme.tertiary,
                  stream: staleQ.snapshots(),
                  filterType: 'stale',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatusCard(
                  title: 'Expired',
                  count: 0,
                  icon: Icons.warning,
                  color: Colors.red.shade700,
                  stream: expiredQ.snapshots(),
                  filterType: 'expired',
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Items Needing Attention
          Text(
            'Items Needing Attention',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _BucketSection(
            title: 'Low stock items',
            icon: Icons.arrow_downward,
            color: colorScheme.error,
            query: lowQ,
            maxItems: 10,
            bucketParam: 'low',
          ),
          const SizedBox(height: 8),
          _BucketSection(
            title: 'Expiring soon',
            icon: Icons.schedule,
            color: colorScheme.secondary,
            query: expiringQ,
            showEarliestExpiry: true,
            maxItems: 10,
            bucketParam: 'expiring',
          ),
          const SizedBox(height: 8),
          _BucketSection(
            title: 'Stale items',
            icon: Icons.inbox_outlined,
            color: colorScheme.tertiary,
            query: staleQ,
            showLastUsed: true,
            maxItems: 10,
            bucketParam: 'stale',
          ),

          const SizedBox(height: 40),

          // Version Footer
          FutureBuilder<String>(
            future: VersionService.getVersion(),
            builder: (context, snapshot) {
              final version = snapshot.data ?? 'Loading...';
              return Center(
                child: Text(
                  'SCOUT v$version',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- Primary Action Button (Large, prominent) ---
class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: colorScheme.outline.withValues(alpha:0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Status Card (Shows count with icon) ---
class _StatusCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String filterType;

  const _StatusCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.stream,
    required this.filterType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder(
      stream: stream,
      builder: (context, snap) {
        final actualCount = snap.data?.docs.length ?? 0;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Navigate to items page - filters will be handled by the items page itself
            context.go('/items');
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 32, color: color),
                const SizedBox(height: 8),
                Text(
                  actualCount.toString(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Bucket Section ---
class _BucketSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Query<Map<String, dynamic>> query;
  final bool showEarliestExpiry;
  final bool showLastUsed;
  final int? maxItems; // limit visible rows for performance
  final String? bucketParam; // optional quick-filter param to pass to items

  const _BucketSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.query,
    this.showEarliestExpiry = false,
    this.showLastUsed = false,
    this.maxItems,
    this.bucketParam,
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
          final int cap = maxItems ?? docs.length;
          final visibleDocs = docs.take(cap).toList();

          return ExpansionTile(
            leading: Icon(icon, color: color),
            title: Text(title),
            subtitle: Text('${docs.length} item(s)'),
            children: [
              if (docs.isEmpty) const ListTile(title: Text('Nothing here — nice!')),
              for (final d in visibleDocs)
                _ItemRow(
                  id: d.id,
                  data: d.data(),
                  showEarliestExpiry: showEarliestExpiry,
                  showLastUsed: showLastUsed,
                ),
              if (docs.length > (maxItems ?? docs.length))
                ListTile(
                  title: const Text('See all'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(bucketParam == null ? '/items' : '/items?bucket=$bucketParam'),
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
        GoRouter.of(context).go('/items/$id');
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

// Static status card that displays a provided count (from aggregated stats)
class _StatusCardStatic extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final String filterType;

  const _StatusCardStatic({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.filterType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/items?bucket=$filterType'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}