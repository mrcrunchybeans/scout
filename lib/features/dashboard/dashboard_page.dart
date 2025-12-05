import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:scout/utils/operator_store.dart';
import 'package:scout/main.dart' show ThemeModeNotifier;
import '../../widgets/brand_logo.dart';
import '../../services/version_service.dart';
import '../items/new_item_page.dart';
import '../items/bulk_inventory_entry_page.dart';
import '../items/add_audit_inventory_page.dart';
import '../session/cart_session_page.dart';
import 'package:scout/widgets/operator_chip.dart';
import 'package:scout/utils/admin_pin.dart';
import '../admin/admin_page.dart';
import '../reports/usage_report_page.dart';
import '../library/library_management_page.dart';
import '../budget/budget_page.dart';

enum _DashboardMenuAction {
  reports,
  admin,
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Future<String> _versionFuture;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _dashboardStatsStream;

  @override
  void initState() {
    super.initState();
    // Clear version cache on dashboard load to ensure fresh version display
    VersionService.clearCache();
    _versionFuture = VersionService.getVersion();
    _dashboardStatsStream = FirebaseFirestore.instance.collection('meta').doc('dashboard_stats').snapshots();
    // Check if operator name is set, prompt if not
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOperatorName();
    });
  }

  Future<void> _checkOperatorName() async {
    final currentName = OperatorStore.name.value;
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
      await OperatorStore.set(picked);
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 1100;
    // Slightly reduce the header height to tighten top whitespace on web
    final appBarHeight = isWideScreen ? 140.0 : 120.0;
    final logoHeight = isWideScreen ? 100.0 : 90.0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: appBarHeight,
        titleSpacing: 0,
        title: Center(child: BrandLogo(height: logoHeight)),
        actions: [
          // Operator chip
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: OperatorChip(),
          ),
          // Theme toggle button - clearly visible
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Toggle theme',
            onPressed: () => ThemeModeNotifier.instance.toggle(),
          ),
          // Simplified menu
          PopupMenuButton<_DashboardMenuAction>(
            onSelected: (v) async {
              final ctx = context;
              if (v == _DashboardMenuAction.reports) {
                Navigator.push(ctx, MaterialPageRoute(builder: (_) => const UsageReportPage()));
              } else if (v == _DashboardMenuAction.admin) {
                final ok = await AdminPin.ensure(ctx);
                if (!ctx.mounted || !ok) return;
                Navigator.push(ctx, MaterialPageRoute(builder: (_) => const AdminPage()));
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: _DashboardMenuAction.reports,
                child: ListTile(
                  leading: Icon(Icons.bar_chart),
                  title: Text('Usage Reports'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const PopupMenuItem(
                value: _DashboardMenuAction.admin,
                child: ListTile(
                  leading: Icon(Icons.admin_panel_settings),
                  title: Text('Admin / Config'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        // Trim top padding a bit to bring content closer to the logo header
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Removed the extra spacer to reduce large top gap

          // Primary Actions + Quick Status (stacked vertically)
          LayoutBuilder(
            builder: (context, constraints) {
              Widget buildActionsGrid() {
                // Seven tiles in a 3-column grid
                final tiles = <Widget>[
                  _PrimaryActionButton(
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
                  _PrimaryActionButton(
                    icon: Icons.qr_code_scanner,
                    color: Colors.blue.shade600,
                    label: 'Add/Audit',
                    subtitle: 'Single item entry',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddAuditInventoryPage()),
                      );
                    },
                  ),
                  _PrimaryActionButton(
                    icon: Icons.playlist_add_check_circle,
                    color: Colors.teal.shade700,
                    label: 'Cart Session',
                    subtitle: 'Start session',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CartSessionPage()),
                      );
                    },
                  ),
                  _PrimaryActionButton(
                    icon: Icons.inventory_2,
                    color: Colors.purple.shade600,
                    label: 'Intervention Kits',
                    subtitle: 'Track kit usage',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LibraryManagementPage()),
                      );
                    },
                  ),
                  _PrimaryActionButton(
                    icon: Icons.inventory_2,
                    color: colorScheme.primary.withValues(alpha: 0.85),
                    label: 'View Items',
                    subtitle: 'Browse inventory',
                    onTap: () => context.go('/items'),
                  ),
                  _PrimaryActionButton(
                    icon: Icons.list_alt,
                    color: Colors.blue.shade600,
                    label: 'Sessions',
                    subtitle: 'View session history',
                    onTap: () => context.go('/sessions'),
                  ),
                  _PrimaryActionButton(
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
                  _PrimaryActionButton(
                    icon: Icons.account_balance_wallet,
                    color: Colors.amber.shade700,
                    label: 'Team Budget',
                    subtitle: 'Collaborative budget management\nPassword: spiritualcare',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BudgetPage()),
                      );
                    },
                  ),
                  _PrimaryActionButton(
                    icon: Icons.feedback_outlined,
                    color: Colors.deepPurple.shade500,
                    label: 'Feedback',
                    subtitle: 'Bugs & feature requests',
                    onTap: () => context.go('/feedback'),
                  ),
                ];

                // Build a 3-column grid with 3 rows
                return Column(
                  children: [
                    // Row 1: Bulk Entry, Add/Audit, Cart Session
                    Row(
                      children: [
                        Expanded(child: tiles[0]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[1]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[2]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Row 2: Library, View Items, Sessions
                    Row(
                      children: [
                        Expanded(child: tiles[3]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[4]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[5]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Row 3: New Item, Team Budget, Feedback
                    Row(
                      children: [
                        Expanded(child: tiles[6]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[7]),
                        const SizedBox(width: 16),
                        Expanded(child: tiles[8]),
                      ],
                    ),
                  ],
                );
              }

              Widget buildQuickStatus() {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: db.collection('meta').doc('dashboard_stats').snapshots(),
                  builder: (context, statsSnap) {
                    final stats = statsSnap.data?.data();
                    final lowCount = (stats?['low'] as num?)?.toInt() ?? 0;
                    final expiringCount = (stats?['expiring'] as num?)?.toInt() ?? 0;
                    final staleCount = (stats?['stale'] as num?)?.toInt() ?? 0;
                    final expiredCount = (stats?['expired'] as num?)?.toInt() ?? 0;
                    final updatedAtTs = stats?['updatedAt'];
                    DateTime? updatedAt;
                    if (updatedAtTs is Timestamp) updatedAt = updatedAtTs.toDate();
                    String updatedLabel() {
                      if (updatedAt == null) return 'Updated: —';
                      final dt = updatedAt.toLocal();
                      String two(int n) => n.toString().padLeft(2, '0');
                      return 'Updated at ${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
                    }

                    final cards = [
                      _StatusCardStatic(title: 'Low Stock', count: lowCount, icon: Icons.arrow_downward, color: colorScheme.error, filterType: 'low'),
                      _StatusCardStatic(title: 'Expiring Soon', count: expiringCount, icon: Icons.schedule, color: colorScheme.secondary, filterType: 'expiring'),
                      _StatusCardStatic(title: 'Stale', count: staleCount, icon: Icons.inbox_outlined, color: colorScheme.tertiary, filterType: 'stale'),
                      _StatusCardStatic(title: 'Expired', count: expiredCount, icon: Icons.warning, color: Colors.red.shade700, filterType: 'expired'),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Items needing attention',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Always use 2x2 grid layout since Quick Status is below the tiles
                        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 8), Expanded(child: cards[1])]),
                        const SizedBox(height: 8),
                        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 8), Expanded(child: cards[3])]),
                        const SizedBox(height: 8),
                        Text(updatedLabel(), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      ],
                    );
                  },
                );
              }

              // Always stack: tiles on top, Quick Status below
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildActionsGrid(),
                  const SizedBox(height: 32),
                  // Welcome section
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
                  const SizedBox(height: 32),
                  buildQuickStatus(),
                ],
              );
            },
          ),

          const SizedBox(height: 40),

          // Version & Data Refresh Footer
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _dashboardStatsStream,
            builder: (context, statsSnap) {
              final stats = statsSnap.data?.data();
              final updatedAtTs = stats?['updatedAt'];
              DateTime? updatedAt;
              if (updatedAtTs is Timestamp) {
                updatedAt = updatedAtTs.toDate();
              }

              final refreshLabel = updatedAt != null
                  ? 'Data refreshed ${MaterialLocalizations.of(context).formatMediumDate(updatedAt.toLocal())}'
                  : 'Data refresh pending';

              return FutureBuilder<String>(
                future: _versionFuture,
                builder: (context, snapshot) {
                  final version = snapshot.data ?? 'Loading...';
                  final textTheme = Theme.of(context).textTheme.bodySmall;
                  final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SCOUT v$version',
                        style: textTheme?.copyWith(color: mutedColor, fontWeight: FontWeight.w300),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        refreshLabel,
                        style: textTheme?.copyWith(color: mutedColor, fontWeight: FontWeight.w300),
                      ),
                    ],
                  );
                },
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