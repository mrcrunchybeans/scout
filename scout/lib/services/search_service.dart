import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:algolia_helper_flutter/algolia_helper_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Search strategy for different filtering approaches
enum SearchStrategy {
  /// Use Firestore server-side queries where possible, client-side for complex filters
  hybrid,
  /// Use only client-side filtering (current approach)
  clientSide,
  /// Use external search service like Algolia (future implementation)
  external,
}

/// Configuration for search behavior
class SearchConfig {
  final SearchStrategy strategy;
  final int maxClientSideItems;
  final bool enableAlgolia;
  final String? algoliaAppId;
  final String? algoliaSearchApiKey;
  final String? algoliaWriteApiKey;
  final String? algoliaIndexName;

  const SearchConfig({
    this.strategy = SearchStrategy.hybrid,
    this.maxClientSideItems = 500,
    this.enableAlgolia = false,
    this.algoliaAppId,
    this.algoliaSearchApiKey,
    this.algoliaWriteApiKey,
    this.algoliaIndexName,
  });
}

/// Search filters matching the UI filters
class SearchFilters {
  final String query;
  final Set<String> categories;
  final Set<String> baseUnits;
  final RangeValues? qtyRange;
  final bool? hasLowStock;
  final bool? hasLots;
  final bool? hasBarcode;
  final bool? hasMinQty;

  const SearchFilters({
    this.query = '',
    this.categories = const {},
    this.baseUnits = const {},
    this.qtyRange,
    this.hasLowStock,
    this.hasLots,
    this.hasBarcode,
    this.hasMinQty,
  });

  bool get isEmpty => query.isEmpty && categories.isEmpty && baseUnits.isEmpty && qtyRange == null && hasLowStock == null && hasLots == null && hasBarcode == null && hasMinQty == null;

  bool get hasServerSideFilters => categories.isNotEmpty || baseUnits.isNotEmpty || qtyRange != null || hasLowStock != null || hasLots != null || hasBarcode != null || hasMinQty != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchFilters &&
        other.query == query &&
        other.categories.length == categories.length &&
        other.categories.containsAll(categories) &&
        other.baseUnits.length == baseUnits.length &&
        other.baseUnits.containsAll(baseUnits) &&
        other.qtyRange == qtyRange &&
        other.hasLowStock == hasLowStock &&
        other.hasLots == hasLots &&
        other.hasBarcode == hasBarcode &&
        other.hasMinQty == hasMinQty;
  }

  @override
  int get hashCode {
    return Object.hash(
      query,
      Object.hashAll(categories.toList()..sort()),
      Object.hashAll(baseUnits.toList()..sort()),
      qtyRange,
      hasLowStock,
      hasLots,
      hasBarcode,
      hasMinQty,
    );
  }

  SearchFilters copyWith({
    String? query,
    Set<String>? categories,
    Set<String>? baseUnits,
    RangeValues? qtyRange,
    bool? hasLowStock,
    bool? hasLots,
    bool? hasBarcode,
    bool? hasMinQty,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      categories: categories ?? this.categories,
      baseUnits: baseUnits ?? this.baseUnits,
      qtyRange: qtyRange ?? this.qtyRange,
      hasLowStock: hasLowStock ?? this.hasLowStock,
      hasLots: hasLots ?? this.hasLots,
      hasBarcode: hasBarcode ?? this.hasBarcode,
      hasMinQty: hasMinQty ?? this.hasMinQty,
    );
  }
}

/// Result of a search operation
class SearchResult {
  final List<QueryDocumentSnapshot> documents;
  final bool usedServerSideFiltering;
  final int totalServerSideResults;
  final String? searchStrategy;

  const SearchResult({
    required this.documents,
    this.usedServerSideFiltering = false,
    this.totalServerSideResults = 0,
    this.searchStrategy,
  });
}

/// Service for handling search operations across different strategies
class SearchService {
  final FirebaseFirestore _db;
  final SearchConfig _config;

  SearchService(this._db, [SearchConfig? config])
      : _config = config ?? const SearchConfig();

  /// Search items with the given filters and view mode
  Future<SearchResult> searchItems({
    required SearchFilters filters,
    required bool showArchived,
    required String sortField,
    required bool sortDescending,
    int limit = 1000,
  }) async {
    switch (_config.strategy) {
      case SearchStrategy.hybrid:
        return _searchHybrid(filters, showArchived, sortField, sortDescending, limit);
      case SearchStrategy.clientSide:
        return _searchClientSide(filters, showArchived, sortField, sortDescending, limit);
      case SearchStrategy.external:
        // Try external search first, fall back to hybrid if offline or fails
        try {
          return await _searchExternal(filters, showArchived, sortField, sortDescending, limit);
        } catch (e) {
          // Fall back to hybrid search on network errors or configuration issues
          return _searchHybrid(filters, showArchived, sortField, sortDescending, limit);
        }
    }
  }

  /// Hybrid search: server-side where possible, client-side for complex queries
  Future<SearchResult> _searchHybrid(
    SearchFilters filters,
    bool showArchived,
    String sortField,
    bool sortDescending,
    int limit,
  ) async {
    // Start with base query
    Query query = _db.collection('items');

    // Filter archived status - only filter if showing archived items
    // For active items, we don't filter since items without 'archived' field should be considered active
    if (showArchived) {
      query = query.where('archived', isEqualTo: true);
    }

    // Apply server-side filters where possible
    bool usedServerSide = false;

    // Category filtering (server-side)
    if (filters.categories.isNotEmpty) {
      // Firestore array-contains-any for multiple categories
      query = query.where('category', whereIn: filters.categories.toList());
      usedServerSide = true;
    }

    // Quantity range filtering (server-side for simple cases)
    if (filters.qtyRange != null) {
      final range = filters.qtyRange!;
      if (range.start > 0) {
        query = query.where('qtyOnHand', isGreaterThanOrEqualTo: range.start);
      }
      if (range.end < double.maxFinite) {
        query = query.where('qtyOnHand', isLessThanOrEqualTo: range.end);
      }
      usedServerSide = true;
    }

    // Low stock and has lots require client-side filtering
    final needsClientSide = filters.query.isNotEmpty || filters.hasLowStock != null || filters.hasLots != null;

    // Apply sorting
    query = query.orderBy(sortField, descending: sortDescending);

    // Apply limit (increase for client-side processing)
    final serverLimit = needsClientSide ? _config.maxClientSideItems : limit;
    query = query.limit(serverLimit);

    final snapshot = await query.get();

    if (!needsClientSide) {
      // Pure server-side result
      return SearchResult(
        documents: snapshot.docs,
        usedServerSideFiltering: true,
        totalServerSideResults: snapshot.docs.length,
        searchStrategy: 'server-side',
      );
    }

    // Apply client-side filtering
    final filteredDocs = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '') as String;
      final barcode = (data['barcode'] ?? '') as String;
      final category = (data['category'] ?? '') as String;
      final baseUnit = (data['baseUnit'] ?? '') as String;
      final qty = (data['qtyOnHand'] ?? 0) as num;
      final minQty = (data['minQty'] ?? 0) as num;
      final hasLots = (data['lots'] != null && (data['lots'] as List?)?.isNotEmpty == true);
      final hasBarcode = barcode.isNotEmpty;
      final hasMinQtySet = minQty > 0;
      final isArchived = (data['archived'] ?? false) as bool;

      // Filter by archived status (client-side for active items)
      if (!showArchived && isArchived) {
        return false;
      }

      // Text search - search both name and barcode fields
      if (filters.query.isNotEmpty) {
        final query = filters.query.toLowerCase();
        final nameMatch = name.toLowerCase().contains(query);
        final barcodeMatch = barcode.toLowerCase().contains(query);
        if (!nameMatch && !barcodeMatch) {
          return false;
        }
      }

      // Category filter
      if (filters.categories.isNotEmpty && !filters.categories.contains(category)) {
        return false;
      }

      // Base unit filter
      if (filters.baseUnits.isNotEmpty && !filters.baseUnits.contains(baseUnit)) {
        return false;
      }

      // Low stock filter
      if (filters.hasLowStock == true && qty >= minQty) {
        return false;
      }

      // Has lots filter
      if (filters.hasLots != null && hasLots != filters.hasLots!) {
        return false;
      }

      // Has barcode filter
      if (filters.hasBarcode != null && hasBarcode != filters.hasBarcode!) {
        return false;
      }

      // Has minimum quantity filter
      if (filters.hasMinQty != null && hasMinQtySet != filters.hasMinQty!) {
        return false;
      }

      return true;
    }).toList();

    // Limit final results
    final finalDocs = filteredDocs.take(limit).toList();

    return SearchResult(
      documents: finalDocs,
      usedServerSideFiltering: usedServerSide,
      totalServerSideResults: snapshot.docs.length,
      searchStrategy: 'hybrid (server+client)',
    );
  }

  /// Client-side only search (fallback)
  Future<SearchResult> _searchClientSide(
    SearchFilters filters,
    bool showArchived,
    String sortField,
    bool sortDescending,
    int limit,
  ) async {
    Query query = _db.collection('items')
        .orderBy(sortField, descending: sortDescending)
        .limit(_config.maxClientSideItems);

    final snapshot = await query.get();
    final allDocs = snapshot.docs;

    final filteredDocs = allDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '') as String;
      final category = (data['category'] ?? '') as String;
      final qty = (data['qtyOnHand'] ?? 0) as num;
      final minQty = (data['minQty'] ?? 0) as num;
      final hasLots = (data['lots'] != null && (data['lots'] as List?)?.isNotEmpty == true);
      final isArchived = (data['archived'] ?? false) as bool;

      // Filter by archived status
      if (!showArchived && isArchived) {
        return false;
      }

      // Apply filters only if they exist
      if (filters.isEmpty) {
        return true;
      }

      // Text search
      if (filters.query.isNotEmpty && !name.toLowerCase().contains(filters.query.toLowerCase())) {
        return false;
      }

      // Category filter
      if (filters.categories.isNotEmpty && !filters.categories.contains(category)) {
        return false;
      }

      // Quantity range filter
      if (filters.qtyRange != null) {
        if (qty < filters.qtyRange!.start || qty > filters.qtyRange!.end) {
          return false;
        }
      }

      // Low stock filter
      if (filters.hasLowStock == true && qty >= minQty) {
        return false;
      }

      // Has lots filter
      if (filters.hasLots != null && hasLots != filters.hasLots!) {
        return false;
      }

      return true;
    }).toList();

    final finalDocs = filteredDocs.take(limit).toList();

    return SearchResult(
      documents: finalDocs,
      usedServerSideFiltering: false,
      totalServerSideResults: 0,
      searchStrategy: 'client-side',
    );
  }

  /// External search service (Algolia implementation)
  Future<SearchResult> _searchExternal(
    SearchFilters filters,
    bool showArchived,
    String sortField,
    bool sortDescending,
    int limit,
  ) async {
    // Check if Algolia is configured
    if (!_config.enableAlgolia ||
        _config.algoliaAppId == null ||
        _config.algoliaSearchApiKey == null ||
        _config.algoliaIndexName == null) {
      return _searchHybrid(filters, showArchived, sortField, sortDescending, limit);
    }

    try {
      // Create HitsSearcher with Algolia credentials
      final searcher = HitsSearcher(
        applicationID: _config.algoliaAppId!,
        apiKey: _config.algoliaSearchApiKey!,
        indexName: _config.algoliaIndexName!,
      );

      // Set up filter state for advanced filtering
      final filterState = FilterState();

      // Apply initial search state
      searcher.applyState((state) => state.copyWith(
        query: filters.query,
        page: 0,
        hitsPerPage: limit,
      ));

      // Apply filters separately if needed
      final algoliaFilters = _buildAlgoliaFilters(filters, showArchived);
      if (algoliaFilters.isNotEmpty) {
        // Note: Filter application might need to be done differently with algolia_helper_flutter
        // This is a simplified version - advanced filtering may need FilterState
      }

      // Get search results
      final response = await searcher.responses.first;

      // Extract document IDs from Algolia results
      final hits = response.hits;
      if (hits.isEmpty) {
        return SearchResult(
          documents: [],
          usedServerSideFiltering: true,
          totalServerSideResults: 0,
          searchStrategy: 'algolia',
        );
      }

      // Extract document IDs from Algolia results (assuming objectID is the Firestore doc ID)
      final docIds = hits.map((hit) => hit['objectID'] as String).toList();

      // Fetch documents from Firestore
      final docs = await Future.wait(
        docIds.map((id) => _db.collection('items').doc(id).get()),
      );

      // Filter out any documents that don't exist and cast to QueryDocumentSnapshot
      final validDocs = docs
          .where((doc) => doc.exists)
          .cast<QueryDocumentSnapshot>()
          .toList();

      // Clean up
      searcher.dispose();
      filterState.dispose();

      return SearchResult(
        documents: validDocs,
        usedServerSideFiltering: true,
        totalServerSideResults: response.nbHits,
        searchStrategy: 'algolia',
      );
    } catch (e) {
      // Fall back to hybrid search on any error
      return _searchHybrid(filters, showArchived, sortField, sortDescending, limit);
    }
  }

  /// Build Algolia filter string from SearchFilters
  String _buildAlgoliaFilters(SearchFilters filters, bool showArchived) {
    final filterParts = <String>[];

    // Archived filter
    if (!showArchived) {
      filterParts.add('archived:false');
    } else {
      filterParts.add('archived:true');
    }

    // Category filter
    if (filters.categories.isNotEmpty) {
      final categoryFilters = filters.categories.map((cat) => 'category:"$cat"').join(' OR ');
      filterParts.add('($categoryFilters)');
    }

    // Quantity range filter
    if (filters.qtyRange != null) {
      final range = filters.qtyRange!;
      if (range.start > 0) {
        filterParts.add('qtyOnHand >= ${range.start}');
      }
      if (range.end < double.maxFinite) {
        filterParts.add('qtyOnHand <= ${range.end}');
      }
    }

    // Low stock filter
    if (filters.hasLowStock == true) {
      filterParts.add('qtyOnHand < minQty');
    }

    // Base unit filter
    if (filters.baseUnits.isNotEmpty) {
      final baseUnitFilters = filters.baseUnits.map((unit) => 'baseUnit:"$unit"').join(' OR ');
      filterParts.add('($baseUnitFilters)');
    }

    // Has barcode filter
    if (filters.hasBarcode != null) {
      if (filters.hasBarcode!) {
        filterParts.add('barcode:[* TO *]'); // Has non-empty barcode
      } else {
        filterParts.add('NOT barcode:[* TO *]'); // Empty barcode
      }
    }

    // Has minimum quantity filter
    if (filters.hasMinQty != null) {
      if (filters.hasMinQty!) {
        filterParts.add('minQty > 0'); // Has minimum quantity set
      } else {
        filterParts.add('minQty <= 0'); // No minimum quantity set
      }
    }

    return filterParts.join(' AND ');
  }

  /// Get search statistics for debugging/performance monitoring
  Future<Map<String, dynamic>> getSearchStats() async {
    // This could track search performance, cache hit rates, etc.
    return {
      'strategy': _config.strategy.toString(),
      'maxClientSideItems': _config.maxClientSideItems,
      'algoliaEnabled': _config.enableAlgolia,
    };
  }

  /// Sync all items from Firestore to Algolia index
  Future<void> syncItemsToAlgolia() async {
    if (!_config.enableAlgolia ||
        _config.algoliaAppId == null ||
        _config.algoliaWriteApiKey == null ||
        _config.algoliaIndexName == null) {
      throw Exception('Algolia is not properly configured for indexing');
    }

    try {
      // Get all items from Firestore
      final snapshot = await _db.collection('items').get();

      if (snapshot.docs.isEmpty) {
        return; // Nothing to sync
      }

      // Transform Firestore documents to Algolia records
      final records = snapshot.docs.map((doc) {
        final data = doc.data();
        
        // Convert Timestamp objects to milliseconds since epoch for JSON serialization
        final Map<String, dynamic> serializableData = {};
        data.forEach((key, value) {
          if (value is Timestamp) {
            serializableData[key] = value.millisecondsSinceEpoch;
          } else {
            serializableData[key] = value;
          }
        });
        
        return {
          'objectID': doc.id,
          ...serializableData,
          // Ensure searchable fields are properly formatted
          'name': serializableData['name'] ?? '',
          'barcode': serializableData['barcode'] ?? '',
          'category': serializableData['category'] ?? '',
          'baseUnit': serializableData['baseUnit'] ?? '',
          'qtyOnHand': serializableData['qtyOnHand'] ?? 0,
          'minQty': serializableData['minQty'] ?? 0,
          'archived': serializableData['archived'] ?? false,
          'lots': serializableData['lots'] ?? [],
        };
      }).toList();

      // Use Algolia's batch API to update the index
      final url = 'https://${_config.algoliaAppId}.algolia.net/1/indexes/${_config.algoliaIndexName}/batch';

      final batchRequest = {
        'requests': records.map((record) => {
          'action': 'addObject',
          'body': record,
        }).toList(),
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'X-Algolia-API-Key': _config.algoliaWriteApiKey!,
          'X-Algolia-Application-Id': _config.algoliaAppId!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(batchRequest),
      );

      if (response.statusCode != 200) {
        throw Exception('Algolia API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to sync items to Algolia: $e');
    }
  }

  /// Configure Algolia index settings for facets and search
  Future<void> configureAlgoliaIndex() async {
    if (!_config.enableAlgolia ||
        _config.algoliaAppId == null ||
        _config.algoliaWriteApiKey == null ||
        _config.algoliaIndexName == null) {
      throw Exception('Algolia is not properly configured');
    }

    try {
      // Configure index settings for facets and searchable attributes
      final settingsUrl = 'https://${_config.algoliaAppId}.algolia.net/1/indexes/${_config.algoliaIndexName}/settings';

      final settings = {
        'attributesForFaceting': [
          'category',           // Enable category facets
          'baseUnit',           // Enable base unit facets
          'archived',           // Enable archived status facets
          'filterOnly(qtyOnHand)', // Allow filtering by quantity (not faceting)
          'filterOnly(minQty)',    // Allow filtering by min quantity (not faceting)
          'filterOnly(barcode)',   // Allow filtering by barcode presence (not faceting)
        ],
        'searchableAttributes': [
          'name',
          'barcode',
          'category',
          'description',        // If you have description field
          'notes',             // If you have notes field
        ],
        'customRanking': [
          'desc(qtyOnHand)',   // Higher quantity items rank higher
        ],
        'ranking': [
          'typo',
          'geo',
          'words',
          'filters',
          'proximity',
          'attribute',
          'exact',
          'custom',
        ],
      };

      final response = await http.put(
        Uri.parse(settingsUrl),
        headers: {
          'X-Algolia-API-Key': _config.algoliaWriteApiKey!,
          'X-Algolia-Application-Id': _config.algoliaAppId!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(settings),
      );

      if (response.statusCode != 200) {
        throw Exception('Algolia API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to configure Algolia index: $e');
    }
  }

  /// Sync a single item to Algolia
  Future<void> syncItemToAlgolia(String itemId) async {
    if (!_config.enableAlgolia ||
        _config.algoliaAppId == null ||
        _config.algoliaWriteApiKey == null ||
        _config.algoliaIndexName == null) {
      throw Exception('Algolia is not properly configured for indexing');
    }

    try {
      // Get the item from Firestore
      final doc = await _db.collection('items').doc(itemId).get();

      if (!doc.exists) {
        // Item was deleted, remove from Algolia
        final deleteUrl = 'https://${_config.algoliaAppId}.algolia.net/1/indexes/${_config.algoliaIndexName}/$itemId';

        final response = await http.delete(
          Uri.parse(deleteUrl),
          headers: {
            'X-Algolia-API-Key': _config.algoliaWriteApiKey!,
            'X-Algolia-Application-Id': _config.algoliaAppId!,
          },
        );

        if (response.statusCode != 200 && response.statusCode != 404) {
          throw Exception('Algolia API error: ${response.statusCode} - ${response.body}');
        }
        return;
      }

      // Transform document to Algolia record
      final data = doc.data()!;
      final record = {
        'objectID': doc.id,
        ...data,
        'name': data['name'] ?? '',
        'barcode': data['barcode'] ?? '',
        'category': data['category'] ?? '',
        'baseUnit': data['baseUnit'] ?? '',
        'qtyOnHand': data['qtyOnHand'] ?? 0,
        'minQty': data['minQty'] ?? 0,
        'archived': data['archived'] ?? false,
        'lots': data['lots'] ?? [],
      };

      // Save/update the record in Algolia
      final url = 'https://${_config.algoliaAppId}.algolia.net/1/indexes/${_config.algoliaIndexName}';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'X-Algolia-API-Key': _config.algoliaWriteApiKey!,
          'X-Algolia-Application-Id': _config.algoliaAppId!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(record),
      );

      if (response.statusCode != 200) {
        throw Exception('Algolia API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to sync item $itemId to Algolia: $e');
    }
  }
}
