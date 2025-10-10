import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:scout/features/items/new_item_page.dart';
import 'package:scout/widgets/label_sheet_preview.dart';
import '../lookups_management_page.dart';
import '../../services/search_service.dart';
import '../../utils/audit.dart';
import '../../services/label_export_service.dart';

import '../../dev/seed_lookups.dart';

enum SortOption { updatedDesc, nameAsc, nameDesc, categoryAsc, categoryDesc, qtyAsc, qtyDesc, expirationAsc, expirationDesc }
enum ViewMode { active, archived }

class ItemsPage extends StatefulWidget {
  final SearchFilters? initialFilters;
  final bool isFromDashboard;
  final SortOption? initialSort;
  final bool? initialArchived;

  const ItemsPage({super.key, this.initialFilters, this.isFromDashboard = false, this.initialSort, this.initialArchived});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _db = FirebaseFirestore.instance;
  final _searchService = SearchService(
    FirebaseFirestore.instance,
    const SearchConfig(
      strategy: SearchStrategy.hybrid, // Temporarily use hybrid search to bypass Algolia issues
      enableAlgolia: true, // Keep Algolia enabled for when index is populated
      algoliaAppId: 'COMHTF4QM1',
      algoliaSearchApiKey: '86a6aa6baaa3bbfc8e5e75c0c272fa00',
      algoliaWriteApiKey: '3ca7664f0aaf7555ab3c43bd179d17d8',
      algoliaIndexName: 'scout_items',
    ),
  );
  bool _busy = false;
  Timer? _searchDebounce;
  Timer? _urlDebounce;
  // Pagination controls
  final int _pageSize = 50;
  // Paged state
  List<QueryDocumentSnapshot> _docs = [];
  QueryDocumentSnapshot? _lastDoc;
  bool _canPage = false;
  bool _initialLoading = false;
  bool _loadingMore = false;
  int _searchSeq = 0; // used to cancel stale searches
  // Scroll controller for infinite scroll
  final ScrollController _scrollController = ScrollController();
  DateTime? _lastAutoLoadAt;
  // Search controller/focus for keyboard shortcut and programmatic control
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  // Back-to-top control
  bool _showBackToTop = false;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // If we're close to the bottom and more pages are available, load more
    final isScrollingDown = pos.userScrollDirection == ScrollDirection.forward;
    final now = DateTime.now();
    final okCooldown = _lastAutoLoadAt == null || now.difference(_lastAutoLoadAt!).inMilliseconds > 600;
    if (_canPage && !_loadingMore && !_initialLoading && isScrollingDown && pos.extentAfter < 800 && okCooldown) {
      _lastAutoLoadAt = now;
      _loadMore();
    }

    // Toggle back-to-top button based on scroll position
    final shouldShow = pos.pixels > 600;
    if (shouldShow != _showBackToTop) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _filters = _filters.copyWith(query: value.trim());
        _loadFirstPage();
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _urlDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
  late SearchFilters _filters;
  SortOption _sortOption = SortOption.updatedDesc;
  ViewMode _viewMode = ViewMode.active;
  bool _selectionMode = false;
  bool _showAdvancedFilters = false;
  Future<List<String>>? _categoriesFuture;
  final Set<String> _selectedIds = {};
  List<String> _visibleIds = [];

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters ?? const SearchFilters();
    if (widget.initialSort != null) _sortOption = widget.initialSort!;
    if (widget.initialArchived == true) _viewMode = ViewMode.archived;
    _searchController.text = _filters.query;
    _categoriesFuture = _loadCategories();
    _loadFirstPage();
    _scrollController.addListener(_onScroll);
  }

  Uri _buildItemsUri() {
    final qp = <String, String>{};
    if (_filters.query.isNotEmpty) qp['q'] = _filters.query;
    if (_filters.hasLowStock == true) qp['low'] = '1';
    if (_filters.hasLots == true) qp['lots'] = '1';
    if (_filters.hasBarcode == true) qp['barcode'] = '1';
  if (_filters.hasMinQty == true) qp['minQty'] = '1';
  if (_filters.hasExpiringSoon == true) qp['expSoon'] = '1';
  if (_filters.hasStale == true) qp['stale'] = '1';
  if (_filters.hasExcess == true) qp['excess'] = '1';
    if (_filters.hasExpired == true) qp['expired'] = '1';
    if (_filters.categories.isNotEmpty) qp['cats'] = _filters.categories.join(',');
    if (_filters.locationIds.isNotEmpty) qp['locs'] = _filters.locationIds.join(',');
    if (_viewMode == ViewMode.archived) qp['archived'] = '1';
    // sort
    final sortMap = {
      SortOption.updatedDesc: 'recent',
      SortOption.nameAsc: 'name-asc',
      SortOption.nameDesc: 'name-desc',
      SortOption.categoryAsc: 'cat-asc',
      SortOption.categoryDesc: 'cat-desc',
      SortOption.qtyAsc: 'qty-asc',
      SortOption.qtyDesc: 'qty-desc',
      SortOption.expirationAsc: 'exp-asc',
      SortOption.expirationDesc: 'exp-desc',
    };
    qp['sort'] = sortMap[_sortOption] ?? 'recent';

    return Uri(path: '/items', queryParameters: qp.isEmpty ? null : qp);
  }

  void _syncUrlDebounced() {
    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final uri = _buildItemsUri();
      final router = GoRouter.of(context);
      if (router.location != uri.toString()) {
        router.go(uri.toString());
      }
    });
  }

  void _loadFirstPage() async {
    final seq = ++_searchSeq;
    setState(() {
      _initialLoading = true;
      _docs = [];
      _lastDoc = null;
      _canPage = false;
    });

    // Reset scroll to top on a new search/filter
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    final sortField = switch (_sortOption) {
      SortOption.updatedDesc => 'updatedAt',
      SortOption.nameAsc || SortOption.nameDesc => 'name',
      SortOption.categoryAsc || SortOption.categoryDesc => 'category',
      SortOption.qtyAsc || SortOption.qtyDesc => 'qtyOnHand',
      SortOption.expirationAsc || SortOption.expirationDesc => 'earliestExpiresAt',
    };
    final sortDescending = switch (_sortOption) {
      SortOption.updatedDesc || SortOption.nameDesc || SortOption.categoryDesc || SortOption.qtyDesc || SortOption.expirationDesc => true,
      SortOption.nameAsc || SortOption.categoryAsc || SortOption.qtyAsc || SortOption.expirationAsc => false,
    };

    try {
      final page = await _searchService.searchItemsPaged(
        filters: _filters,
        showArchived: _viewMode == ViewMode.archived,
        sortField: sortField,
        sortDescending: sortDescending,
        pageSize: _pageSize,
        startAfter: null,
        showAllItems: widget.isFromDashboard,
      );
      if (!mounted || seq != _searchSeq) return; // stale
      setState(() {
        _docs = page.documents;
        _lastDoc = page.lastDocument;
        _canPage = page.canPage;
        _visibleIds = _docs.map((d) => d.id).toList();
        _initialLoading = false;
      });
      // Refresh categories based on the new page
      _categoriesFuture = _loadCategories();
      _syncUrlDebounced();
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _initialLoading = false;
      });
      // Show basic error inline
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search error: $e')));
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_canPage) return;
    setState(() => _loadingMore = true);

    final sortField = switch (_sortOption) {
      SortOption.updatedDesc => 'updatedAt',
      SortOption.nameAsc || SortOption.nameDesc => 'name',
      SortOption.categoryAsc || SortOption.categoryDesc => 'category',
      SortOption.qtyAsc || SortOption.qtyDesc => 'qtyOnHand',
      SortOption.expirationAsc || SortOption.expirationDesc => 'earliestExpiresAt',
    };
    final sortDescending = switch (_sortOption) {
      SortOption.updatedDesc || SortOption.nameDesc || SortOption.categoryDesc || SortOption.qtyDesc || SortOption.expirationDesc => true,
      SortOption.nameAsc || SortOption.categoryAsc || SortOption.qtyAsc || SortOption.expirationAsc => false,
    };

    try {
      final page = await _searchService.searchItemsPaged(
        filters: _filters,
        showArchived: _viewMode == ViewMode.archived,
        sortField: sortField,
        sortDescending: sortDescending,
        pageSize: _pageSize,
        startAfter: _lastDoc,
        showAllItems: widget.isFromDashboard,
      );
      if (!mounted) return;
      setState(() {
        _docs.addAll(page.documents);
        _lastDoc = page.lastDocument;
        _canPage = page.canPage;
        _visibleIds = _docs.map((d) => d.id).toList();
      });
      // Update categories using current accumulated docs
      _categoriesFuture = _loadCategories();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load more error: $e')));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<List<String>> _loadCategories({bool broad = false}) async {
    try {
      // Fast path: derive categories from currently loaded page
      if (!broad) {
        final set = <String>{};
        for (final d in _docs) {
          final data = d.data() as Map<String, dynamic>;
          final cat = (data['category'] ?? '') as String;
          if (cat.isNotEmpty) set.add(cat);
        }
        final list = set.toList()..sort();
        if (list.isNotEmpty) return list;
      }

      // Broader sample: fetch a limited slice ordered by category
      Query query = _db.collection('items');
      if (_viewMode == ViewMode.archived) {
        query = query.where('archived', isEqualTo: true);
      }
      // Prefer to fetch a reasonable sample instead of full collection scan
      query = query.orderBy('category').limit(broad ? 1000 : 300);
      final q = await query.get();
      final set = <String>{};
      for (final d in q.docs) {
        final data = d.data() as Map<String, dynamic>?;
        final cat = (data == null ? '' : (data['category'] ?? '')) as String;
        if (cat.isNotEmpty) set.add(cat);
      }
      final list = set.toList()..sort();
      return list;
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    // sort field/direction are computed in _updateSearchFuture()

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Press '/' anywhere to focus the search field (and prevent typing '/').
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.slash) {
          if (!_searchFocus.hasFocus) {
            _searchFocus.requestFocus();
            // Clear the slash character that may have been typed into the TextField
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Dashboard',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
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
          // Share current filters URL
          IconButton(
            tooltip: 'Copy shareable link',
            icon: const Icon(Icons.link),
            onPressed: () async {
              final ctx = context;
              final uri = _buildItemsUri();
              // Build absolute URL for web sharing
              final absolute = Uri.base.resolve(uri.toString()).toString();
              await Clipboard.setData(ClipboardData(text: absolute));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
            },
          ),
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all visible',
              onPressed: _visibleIds.isEmpty
                  ? null
                  : () {
                      setState(() => _selectedIds.addAll(_visibleIds));
                    },
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedIds.isEmpty ? null : _bulkDelete,
            ),
            IconButton(
              icon: Icon(_viewMode == ViewMode.active ? Icons.archive : Icons.unarchive),
              onPressed: _selectedIds.isEmpty ? null : _bulkArchive,
            ),
            IconButton(
              icon: const Icon(Icons.label),
              tooltip: 'Export Labels',
              onPressed: _selectedIds.isEmpty ? null : _exportLabels,
            ),
            Text('${_selectedIds.length} selected'),
          ] else ...[
            IconButton(
              tooltip: 'Dashboard',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: () {
                context.go('/');
              },
            ),
            // Quick Select-all visible button (when not in bulk mode)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all visible',
              onPressed: _visibleIds.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectionMode = true;
                        _selectedIds.addAll(_visibleIds);
                      });
                    },
            ),
            PopupMenuButton<String>(
              tooltip: 'Tools',
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
                      builder: (_) => Theme(
                        data: Theme.of(context),
                        child: AlertDialog(
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
                      ),
                    );
                    if (ok == true) {
                      await resetAndSeedLookups();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lookups reset & seeded.')),
                      );
                    }
                  } else if (key == 'sync-algolia') {
                    setState(() => _busy = true);
                    try {
                      await _searchService.syncItemsToAlgolia();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Items synced to Algolia successfully')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to sync to Algolia: $e')),
                      );
                    } finally {
                      setState(() => _busy = false);
                    }
                  } else if (key == 'toggle-view') {
                    setState(() {
                      _viewMode = _viewMode == ViewMode.active ? ViewMode.archived : ViewMode.active;
                      _categoriesFuture = _loadCategories(); // Refresh categories when view mode changes
                    });
                    _loadFirstPage();
                  } else if (key == 'bulk-edit') {
                    setState(() => _selectionMode = true);
                  } else if (key == 'manage-lookups') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LookupsManagementPage()),
                    );
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
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'toggle-view', child: Text('Show ${_viewMode == ViewMode.active ? 'Archived' : 'Active'}')),
                const PopupMenuItem(value: 'bulk-edit', child: Text('Bulk Edit')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'sync-algolia', child: Text('Sync to Algolia')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'seed-once', child: Text('Seed (only if empty)')),
                const PopupMenuItem(value: 'reseed-merge', child: Text('Reseed (merge by code)')),
                const PopupMenuItem(value: 'reset-seed', child: Text('Reset & seed (destructive)')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'manage-lookups', child: Text('Manage Lookups')),
              ],
              icon: const Icon(Icons.settings),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showAdvancedFilters ? 520 : 220),
          child: SafeArea(
            top: false,
            child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                      tooltip: 'Scan barcode',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.keyboard, size: 14, color: Colors.grey),
                    SizedBox(width: 6),
                    Text("Tip: Press '/' to focus search", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 6),
                _buildActiveFiltersSummary(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Sort: '),
                    DropdownButton<SortOption>(
                      value: _sortOption,
                      items: const [
                        DropdownMenuItem(value: SortOption.updatedDesc, child: Text('Recent')),
                        DropdownMenuItem(value: SortOption.nameAsc, child: Text('Name (A-Z)')),
                        DropdownMenuItem(value: SortOption.nameDesc, child: Text('Name (Z-A)')),
                        DropdownMenuItem(value: SortOption.categoryAsc, child: Text('Category (A-Z)')),
                        DropdownMenuItem(value: SortOption.categoryDesc, child: Text('Category (Z-A)')),
                        DropdownMenuItem(value: SortOption.qtyAsc, child: Text('Quantity (Low-High)')),
                        DropdownMenuItem(value: SortOption.qtyDesc, child: Text('Quantity (High-Low)')),
                        DropdownMenuItem(value: SortOption.expirationAsc, child: Text('Expiration (Soonest)')),
                        DropdownMenuItem(value: SortOption.expirationDesc, child: Text('Expiration (Latest)')),
                      ],
                      onChanged: (value) => setState(() {
                            _sortOption = value!;
                            _loadFirstPage();
                          }),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _showAdvancedFilters = !_showAdvancedFilters;
                        if (_showAdvancedFilters) {
                          _categoriesFuture = _loadCategories();
                        }
                      }),
                      icon: Icon(_showAdvancedFilters ? Icons.filter_list_off : Icons.filter_list),
                      label: Text(_showAdvancedFilters ? 'Hide Filters' : 'Advanced Filters'),
                    ),
                  ],
                ),
                if (_showAdvancedFilters) ...[
                  const SizedBox(height: 8),
                  _buildAdvancedFilters(),
                ],
              ],
            ),
            ),
          ),
        ),
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showBackToTop)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                heroTag: 'top',
                tooltip: 'Back to top',
                onPressed: () {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                  }
                },
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          _selectionMode
              ? FloatingActionButton(
                  heroTag: 'close',
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  }),
                  child: const Icon(Icons.close),
                )
              : FloatingActionButton.extended(
                  heroTag: 'new',
                  onPressed: () async {
                    final ctx = context;
                    final created = await Navigator.of(ctx).push<bool>(
                      MaterialPageRoute(builder: (_) => const NewItemPage()),
                    );
                    if (!ctx.mounted) return;
                    if (created == true) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Item created')),
                      );
                    }
                  },
                  label: const Text('New item'),
                  icon: const Icon(Icons.add_box),
                ),
        ],
      ),

      body: Builder(
        builder: (context) {
          if (_initialLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Populate visible ids so select-all can work without refetching
          _visibleIds = _docs.map((d) => d.id).toList();

          if (_docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text('No ${_viewMode == ViewMode.active ? 'active' : 'archived'} items',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Tap “New item” to add your first inventory item.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_box),
                      label: const Text('New item'),
                      onPressed: () async {
                        final ctx = context;
                        final created = await Navigator.of(ctx).push<bool>(
                          MaterialPageRoute(builder: (_) => const NewItemPage()),
                        );
                        if (!ctx.mounted) return;
                        if (created == true) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Item created')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          final maybeMore = _canPage;
          return ListView.separated(
            controller: _scrollController,
            itemCount: _docs.length + (maybeMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (maybeMore && i == _docs.length) {
                return ListTile(
                  title: Center(child: _loadingMore ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more')),
                  onTap: _loadingMore ? null : _loadMore,
                );
              }
              final d = _docs[i];
              final data = d.data() as Map<String, dynamic>;
              final name = (data['name'] ?? 'Unnamed') as String;
              final category = (data['category'] ?? '') as String;
              final qty = (data['qtyOnHand'] ?? 0);
              final minQty = (data['minQty'] ?? 0);
              final hasLots = (data['lots'] != null && (data['lots'] as List?)?.isNotEmpty == true);
              final expirationDate = data['earliestExpiresAt'] != null ? (data['earliestExpiresAt'] as Timestamp).toDate() : null;

              Color? tileColor;
              if (expirationDate != null) {
                final now = DateTime.now();
                final daysUntilExpiration = expirationDate.difference(now).inDays;
                if (expirationDate.isBefore(now)) {
                  tileColor = Colors.red.withValues(alpha:0.1);
                } else if (daysUntilExpiration <= 14) {
                  tileColor = Colors.yellow.withValues(alpha:0.1);
                }
              }

              return ListTile(
                tileColor: tileColor,
                leading: _selectionMode
                    ? Checkbox(
                        value: _selectedIds.contains(d.id),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedIds.add(d.id);
                            } else {
                              _selectedIds.remove(d.id);
                            }
                          });
                        },
                      )
                    : null,
                title: Text(name),
                subtitle: Text(
                    '${category.isNotEmpty ? '$category • ' : ''}Qty: $qty • Min: $minQty${hasLots ? ' • Has lots' : ''}'),
                onTap: _selectionMode
                    ? () {
                        setState(() {
                          if (_selectedIds.contains(d.id)) {
                            _selectedIds.remove(d.id);
                          } else {
                            _selectedIds.add(d.id);
                          }
                        });
                      }
                    : () {
                        GoRouter.of(context).go('/items/${d.id}');
                      },
                onLongPress: !_selectionMode ? () => setState(() => _selectionMode = true) : null,
                trailing: _selectionMode
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            final result = await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => NewItemPage(
                                itemId: d.id,
                                existingItem: data,
                              ),
                            ));
                            if (result == true) {
                               _loadFirstPage();
                            }
                          } else if (action == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => Theme(
                                data: Theme.of(context),
                                child: AlertDialog(
                                  title: const Text('Delete Item'),
                                  content: Text('Delete "$name"? This cannot be undone.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                  ],
                                ),
                              ),
                            );
                            if (ok == true) {
                              await _db.collection('items').doc(d.id).delete();

                              await Audit.log('item.delete', {
                                'itemId': d.id,
                                'name': name,
                                'category': data['category'],
                                'baseUnit': data['baseUnit'],
                                'qtyOnHand': data['qtyOnHand'],
                              });

                              try {
                                await _searchService.syncItemToAlgolia(d.id);
                              } catch (e) {
                                debugPrint('Failed to sync deletion to Algolia: $e');
                              }
                              _loadFirstPage();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "$name"')));
                            }
                          } else if (action == 'archive') {
                            await _db.collection('items').doc(d.id).update({'archived': _viewMode == ViewMode.active});
                            try {
                              await _searchService.syncItemToAlgolia(d.id);
                            } catch (e) {
                              debugPrint('Failed to sync archive to Algolia: $e');
                            }
                            setState(() {
                              _categoriesFuture = _loadCategories();
                            });
                            _loadFirstPage();
                            if (!context.mounted) return;
                          } else if (action == 'copy') {
                            final details = '$name\n${category.isNotEmpty ? 'Category: $category\n' : ''}Qty: $qty • Min: $minQty${hasLots ? ' • Has lots' : ''}';
                            await Clipboard.setData(ClipboardData(text: details));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Item details copied to clipboard')));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'copy', child: Text('Copy Details')),
                          PopupMenuItem(value: 'edit', child: Text('Edit Item')),
                          PopupMenuItem(value: 'archive', child: Text('Archive/Unarchive')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
              );
            },
          );
        },
      ),
    ),
  );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Barcode')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null) {
                  Navigator.of(context).pop(code);
                }
              }
            },
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() => _filters = _filters.copyWith(query: result));
      _loadFirstPage();
    }
  }

  Widget _buildActiveFiltersSummary() {
    final chips = <Widget>[];

    void addBoolChip(bool? flag, String label, void Function() onClear) {
      if (flag == true) {
        chips.add(InputChip(
          label: Text(label),
          onDeleted: onClear,
        ));
      }
    }

    if (_filters.query.isNotEmpty) {
      chips.add(InputChip(
        avatar: const Icon(Icons.search, size: 16),
        label: Text(_filters.query, overflow: TextOverflow.ellipsis),
        onDeleted: () {
          setState(() {
            _searchController.clear();
            _filters = _filters.copyWith(query: '');
            _loadFirstPage();
          });
        },
      ));
    }

    addBoolChip(_filters.hasLowStock, 'Low stock', () {
      setState(() {
        _filters = _filters.copyWith(hasLowStock: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasLots, 'Has lots', () {
      setState(() {
        _filters = _filters.copyWith(hasLots: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasBarcode, 'Has barcode', () {
      setState(() {
        _filters = _filters.copyWith(hasBarcode: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasMinQty, 'Has min qty', () {
      setState(() {
        _filters = _filters.copyWith(hasMinQty: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasExpiringSoon, 'Expiring soon', () {
      setState(() {
        _filters = _filters.copyWith(hasExpiringSoon: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasStale, 'Stale', () {
      setState(() {
        _filters = _filters.copyWith(hasStale: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasExcess, 'Excess', () {
      setState(() {
        _filters = _filters.copyWith(hasExcess: null);
        _loadFirstPage();
      });
    });
    addBoolChip(_filters.hasExpired, 'Expired', () {
      setState(() {
        _filters = _filters.copyWith(hasExpired: null);
        _loadFirstPage();
      });
    });

    for (final cat in _filters.categories) {
      chips.add(InputChip(
        avatar: const Icon(Icons.category, size: 16),
        label: Text(cat),
        onDeleted: () {
          setState(() {
            final set = Set<String>.from(_filters.categories)..remove(cat);
            _filters = _filters.copyWith(categories: set);
            _loadFirstPage();
          });
        },
      ));
    }

    for (final loc in _filters.locationIds) {
      chips.add(InputChip(
        avatar: const Icon(Icons.place, size: 16),
        label: Text(loc),
        onDeleted: () {
          setState(() {
            final set = Set<String>.from(_filters.locationIds)..remove(loc);
            _filters = _filters.copyWith(locationIds: set);
            _loadFirstPage();
          });
        },
      ));
    }

    if (_viewMode == ViewMode.archived) {
      chips.add(InputChip(
        avatar: const Icon(Icons.archive, size: 16),
        label: const Text('Archived view'),
        onDeleted: () {
          setState(() {
            _viewMode = ViewMode.active;
            _categoriesFuture = _loadCategories();
            _loadFirstPage();
          });
        },
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _searchController.clear();
              _filters = const SearchFilters();
              _viewMode = ViewMode.active;
              _categoriesFuture = _loadCategories();
              _loadFirstPage();
            });
          },
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Future<void> _bulkDelete() async {
    final ctx = context;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => Theme(
        data: Theme.of(context),
        child: AlertDialog(
          title: const Text('Delete Items'),
          content: Text('Delete $count selected items? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final itemsData = <String, Map<String, dynamic>>{};
      for (final id in _selectedIds) {
        try {
          final doc = await _db.collection('items').doc(id).get();
          if (doc.exists) {
            itemsData[id] = doc.data()!;
          }
        } catch (e) {
          debugPrint('Failed to fetch data for item $id: $e');
        }
      }

      final batch = _db.batch();
      for (final id in _selectedIds) {
        batch.delete(_db.collection('items').doc(id));
      }
      await batch.commit();

      for (final id in _selectedIds) {
        final data = itemsData[id];
        if (data != null) {
          await Audit.log('item.delete', {
            'itemId': id,
            'name': data['name'] ?? 'Unknown',
            'category': data['category'],
            'baseUnit': data['baseUnit'],
            'qtyOnHand': data['qtyOnHand'],
            'bulkDelete': true,
          });
        } else {
          await Audit.log('item.delete', {
            'itemId': id,
            'bulkDelete': true,
            'error': 'Could not fetch item data before deletion',
          });
        }
      }

      for (final id in _selectedIds) {
        try {
          await _searchService.syncItemToAlgolia(id);
        } catch (e) {
          debugPrint('Failed to sync deletion to Algolia for $id: $e');
        }
      }

      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _loadFirstPage();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Deleted $count items')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _bulkArchive() async {
    final ctx = context;
    final count = _selectedIds.length;
    final archiving = _viewMode == ViewMode.active;
    setState(() => _busy = true);
    try {
      final batch = _db.batch();
      for (final id in _selectedIds) {
        batch.update(_db.collection('items').doc(id), {'archived': archiving});
      }
      await batch.commit();
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _categoriesFuture = _loadCategories();
      });
      _loadFirstPage();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${archiving ? 'Archived' : 'Unarchived'} $count items')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _exportLabels() async {
    final ctx = context;

    // Ask: Which label number to start from? (1–30, convert to 0–29)
    final startLabel = await showDialog<int>(
      context: context,
      builder: (context) {
        int selectedLabel = 1; // Default
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Export Labels'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pick a starting slot (tap) or use the dropdown.'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: LabelSheetPreview(
                    selectedIndex: selectedLabel - 1,
                    onSelected: (i) => setState(() => selectedLabel = i + 1),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Starting Label',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedLabel,
                  items: List.generate(30, (index) => index + 1)
                      .map((labelNum) => DropdownMenuItem(
                            value: labelNum,
                            child: Text('Label $labelNum'),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => selectedLabel = value ?? 1),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Avery 5160 sheets have 30 labels (3 columns × 10 rows).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(selectedLabel),
                child: const Text('Generate Labels'),
              ),
            ],
          ),
        );
      },
    );

    if (startLabel == null) return; // User cancelled
    final startIndex = startLabel - 1; // convert to 0-based

    setState(() => _busy = true);
    try {
      // Get lots data for selected items
      final lotsData = await LabelExportService.getLotsForItems(_selectedIds.toList());

      if (lotsData.isEmpty) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('No lots found for selected items')),
        );
        return;
      }

      // Export labels using the service with the selected startIndex
      await LabelExportService.exportLabels(lotsData, startIndex: startIndex);

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Generated labels for ${lotsData.length} lots (starting from label $startLabel)')),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Failed to export labels: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _buildAdvancedFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _filters = const SearchFilters();
                    _loadFirstPage();
                  }),
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Filters
            const Text('Quick Filters', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Low Stock'),
                  selected: _filters.hasLowStock == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasLowStock: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Has Lots'),
                  selected: _filters.hasLots == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasLots: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Has Barcode'),
                  selected: _filters.hasBarcode == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasBarcode: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Has Min Qty'),
                  selected: _filters.hasMinQty == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasMinQty: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Expiring Soon'),
                  selected: _filters.hasExpiringSoon == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasExpiringSoon: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Stale'),
                  selected: _filters.hasStale == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasStale: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Excess'),
                  selected: _filters.hasExcess == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasExcess: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
                FilterChip(
                  label: const Text('Expired'),
                  selected: _filters.hasExpired == true,
                  onSelected: (selected) => setState(() {
                    _filters = _filters.copyWith(hasExpired: selected ? true : null);
                    _loadFirstPage();
                  }),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Categories
            FutureBuilder<List<String>>(
              future: _categoriesFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                final categories = snap.data ?? <String>[];
                if (categories.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      const Text('No categories found for the current page.', style: TextStyle(color: Colors.grey)),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _categoriesFuture = _loadCategories()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload (page)'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => setState(() => _categoriesFuture = _loadCategories(broad: true)),
                            icon: const Icon(Icons.travel_explore),
                            label: const Text('Find more (broader sample)'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _categoriesFuture = _loadCategories()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reload (page)'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => setState(() => _categoriesFuture = _loadCategories(broad: true)),
                          icon: const Icon(Icons.travel_explore),
                          label: const Text('Find more (broader sample)'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map((category) => FilterChip(
                                label: Text(category),
                                selected: _filters.categories.contains(category),
                                onSelected: (selected) {
                                  setState(() {
                                    final newCategories = Set<String>.from(_filters.categories);
                                    if (selected) {
                                      newCategories.add(category);
                                    } else {
                                      newCategories.remove(category);
                                    }
                                    _filters = _filters.copyWith(categories: newCategories);
                                    _loadFirstPage();
                                  });
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // Locations (if any are selected, show them)
            if (_filters.locationIds.isNotEmpty) ...[
              const Text('Locations', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filters.locationIds
                    .map((locationId) => FilterChip(
                          label: Text(locationId),
                          selected: true,
                          onSelected: (selected) {
                            if (!selected) {
                              setState(() {
                                final newLocationIds = Set<String>.from(_filters.locationIds);
                                newLocationIds.remove(locationId);
                                _filters = _filters.copyWith(locationIds: newLocationIds);
                                _loadFirstPage();
                              });
                            }
                          },
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
