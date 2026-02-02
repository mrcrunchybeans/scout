// lib/services/barcode_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../utils/deep_link_parser.dart';
import '../data/product_enrichment_service.dart';

/// Callback types for barcode service events.
typedef BarcodeProcessedCallback = void Function(String barcode);
typedef ItemFoundCallback = Future<void> Function({
  required String barcode,
  required String itemId,
  required Map<String, dynamic> itemData,
  String? lotId,
});
typedef DeepLinkCallback = Future<void> Function({
  required String itemId,
  String? lotId,
  required Map<String, dynamic> itemData,
});
typedef UnknownBarcodeCallback = Future<void> Function(String barcode);
typedef ErrorCallback = void Function(dynamic error);

/// Service that handles barcode scanning and mobile scanner subscriptions.
///
/// This service provides reusable methods for:
/// - Listening to mobile scanner sessions
/// - Processing scanned codes (barcodes and QR deep links)
/// - Looking up items by barcode
/// - Handling archived items
///
/// Usage:
/// ```dart
/// // In State class
/// final _barcodeService = BarcodeService();
///
/// @override
/// void initState() {
///   super.initState();
///   _barcodeService.init(
///     onItemFound: _handleItemFound,
///     onDeepLink: _handleDeepLink,
///     onUnknownBarcode: _handleUnknownBarcode,
///     onError: _handleError,
///   );
///   _barcodeService.startListening(
///     sessionId: _sessionId,
///     db: _db,
///   );
/// }
///
/// @override
/// void dispose() {
///   _barcodeService.dispose();
///   super.dispose();
/// }
///
/// Future<void> _handleItemFound({
///   required String barcode,
///   required String itemId,
///   required Map<String, dynamic> itemData,
/// }) async {
///   // Handle found item
/// }
///
/// // To process a code from USB scanner or manual input:
/// await _barcodeService.processCode(code, context: context);
/// ```
class BarcodeService {
  String? _sessionId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _scannerSubscription;

  // Callbacks
  ItemFoundCallback? _onItemFound;
  DeepLinkCallback? _onDeepLink;
  UnknownBarcodeCallback? _onUnknownBarcode;
  ErrorCallback? _onError;
  VoidCallback? _onRefocus;
  BarcodeProcessedCallback? _onProcessed;

  FirebaseFirestore? _db;

  /// Initialize the barcode service with required callbacks.
  void init({
    required ItemFoundCallback onItemFound,
    required DeepLinkCallback onDeepLink,
    required UnknownBarcodeCallback onUnknownBarcode,
    required ErrorCallback onError,
    VoidCallback? onRefocus,
    BarcodeProcessedCallback? onProcessed,
  }) {
    _onItemFound = onItemFound;
    _onDeepLink = onDeepLink;
    _onUnknownBarcode = onUnknownBarcode;
    _onError = onError;
    _onRefocus = onRefocus;
    _onProcessed = onProcessed;
  }

  /// Generate a new session ID for mobile scanning.
  String generateSessionId() {
    _sessionId = const Uuid().v4();
    return _sessionId!;
  }

  /// Start listening for mobile scanner scans.
  ///
  /// [db] - The Firestore instance
  /// [sessionId] - Optional session ID, generates one if not provided
  /// [onScan] - Optional custom handler for each scan
  void startListening({
    required FirebaseFirestore db,
    String? sessionId,
    Future<void> Function(String barcode)? onScan,
  }) {
    _db = db;
    _sessionId = sessionId ?? generateSessionId();

    _scannerSubscription = db
        .collection('scanner_sessions')
        .doc(_sessionId)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isNotEmpty) {
        final scan = snapshot.docs.first;
        final barcode = scan.data()['barcode'] as String?;
        final processed = scan.data()['processed'] as bool? ?? false;

        if (barcode != null && !processed) {
          if (onScan != null) {
            await onScan(barcode);
          } else {
            // Use default processCode if no custom handler
            // Note: This requires a BuildContext which we can't easily have here
            // So we just call the processed callback
          }
          // Mark as processed
          scan.reference.update({'processed': true});
          _onProcessed?.call(barcode);
        }
      }
    });
  }

  /// Stop listening for mobile scanner scans.
  void stopListening() {
    _scannerSubscription?.cancel();
    _scannerSubscription = null;
  }

  /// Clean up the scanner session.
  Future<void> cleanup({FirebaseFirestore? db, String? sessionId}) async {
    stopListening();
    final firestore = db ?? _db;
    final id = sessionId ?? _sessionId;
    if (firestore != null && id != null) {
      await firestore.collection('scanner_sessions').doc(id).delete().catchError((_) {});
    }
    _sessionId = null;
  }

  /// Dispose the service and clean up resources.
  void dispose() {
    stopListening();
    _sessionId = null;
    _onItemFound = null;
    _onDeepLink = null;
    _onUnknownBarcode = null;
    _onError = null;
    _onRefocus = null;
    _onProcessed = null;
  }

  /// Process a scanned code (barcode or QR code).
  ///
  /// This method handles:
  /// - Lot deep links (new URL format and legacy SCOUT:LOT format)
  /// - Item barcode lookups
  /// - Archived item reactivation
  /// - Unknown barcode handling via product enrichment
  ///
  /// [code] - The scanned code
  /// [db] - Firestore instance
  /// [context] - BuildContext for showing dialogs
  /// [fefoLotIdForItem] - Optional function to get FEFO lot ID for an item
  /// [offerAttachBarcode] - Optional function to offer attaching barcode to existing item
  Future<void> processCode(
    String code, {
    required FirebaseFirestore db,
    required BuildContext context,
    Future<String?> Function(String itemId)? fefoLotIdForItem,
    Future<void> Function(String barcode)? offerAttachBarcode,
  }) async {
    final trimmedCode = code.trim();
    if (trimmedCode.isEmpty) return;

    try {
      // 1) Try parsing as a lot deep link (new URL format)
      final lotDeepLink = DeepLinkParser.parseLotDeepLink(trimmedCode);
      if (lotDeepLink != null) {
        if (kDebugMode) {
          debugPrint('BarcodeService: Detected lot deep link');
        }
        final itemId = lotDeepLink['itemId']!;
        final lotId = lotDeepLink['lotId'];

        final itemSnap = await db.collection('items').doc(itemId).get();
        if (!context.mounted) return;
        if (!itemSnap.exists) throw Exception('Item not found');

        final itemData = Map<String, dynamic>.from(itemSnap.data()!);
        itemData['id'] = itemSnap.id;

        await _onDeepLink?.call(
          itemId: itemId,
          lotId: lotId,
          itemData: itemData,
        );

        _onRefocus?.call();
        return;
      }

      // 2) Legacy SCOUT lot QR: SCOUT:LOT:item={ITEM_ID};lot={LOT_ID}
      if (trimmedCode.startsWith('SCOUT:LOT:')) {
        if (kDebugMode) {
          debugPrint('BarcodeService: Detected legacy SCOUT:LOT QR');
        }
        String? itemId, lotId;
        for (final p in trimmedCode.substring('SCOUT:LOT:'.length).split(';')) {
          final kv = p.split('=');
          if (kv.length == 2) {
            if (kv[0] == 'item') itemId = kv[1];
            if (kv[0] == 'lot') lotId = kv[1];
          }
        }
        if (itemId != null) {
          final itemSnap = await db.collection('items').doc(itemId).get();
          if (!context.mounted) return;
          if (!itemSnap.exists) throw Exception('Item not found');

          final itemData = Map<String, dynamic>.from(itemSnap.data()!);
          itemData['id'] = itemSnap.id;

          await _onDeepLink?.call(
            itemId: itemId,
            lotId: lotId,
            itemData: itemData,
          );

          _onRefocus?.call();
          return;
        }
      }

      // 3) Item barcode search (support 'barcode' and 'barcodes' array)
      QueryDocumentSnapshot<Map<String, dynamic>>? itemDoc;
      var query = await db.collection('items').where('barcode', isEqualTo: trimmedCode).limit(1).get();
      if (query.docs.isNotEmpty) {
        itemDoc = query.docs.first;
      } else {
        query = await db.collection('items').where('barcodes', arrayContains: trimmedCode).limit(1).get();
        if (query.docs.isNotEmpty) itemDoc = query.docs.first;
      }

      if (itemDoc != null) {
        final data = itemDoc.data();
        final isArchived = data['archived'] == true;

        // If item is archived, offer to reactivate it
        if (isArchived) {
          if (!context.mounted) return;
          final shouldReactivate = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('Reactivate Item?'),
              content: Text(
                'The item "${data['name'] ?? 'Unnamed'}" was previously archived. '
                'Would you like to reactivate it to preserve its usage history?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('Reactivate'),
                ),
              ],
            ),
          );

          if (shouldReactivate == true) {
            // Unarchive the item
            await db.collection('items').doc(itemDoc.id).update({
              'archived': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            // Log the reactivation
            await db.collection('audit_logs').add({
              'type': 'item.unarchive',
              'data': {
                'itemId': itemDoc.id,
                'name': data['name'],
                'reason': 'barcode_scan_reactivation',
              },
              'createdAt': FieldValue.serverTimestamp(),
            });

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Reactivated: ${data['name']}')),
            );
          } else {
            _onRefocus?.call();
            return;
          }
        }

        final itemData = Map<String, dynamic>.from(data);
        itemData['id'] = itemDoc.id;

        // Get FEFO lot ID if requested
        String? lotId;
        if (fefoLotIdForItem != null) {
          lotId = await fefoLotIdForItem(itemDoc.id);
        }

        await _onItemFound?.call(
          barcode: trimmedCode,
          itemId: itemDoc.id,
          itemData: itemData,
          lotId: lotId,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added: ${data['name']}')),
          );
        }
        _onRefocus?.call();
        return;
      }

      // 4) Unknown barcode -> try auto-create with enrichment
      final itemId = await ProductEnrichmentService.createItemWithEnrichment(trimmedCode, db);
      if (itemId != null) {
        final itemSnap = await db.collection('items').doc(itemId).get();
        if (!context.mounted) return;
        if (!itemSnap.exists) return;
        final data = itemSnap.data();
        if (data == null) return;

        final itemData = Map<String, dynamic>.from(data);
        itemData['id'] = itemId;

        await _onItemFound?.call(
          barcode: trimmedCode,
          itemId: itemId,
          itemData: itemData,
          lotId: null,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Created and added: ${data['name']}')),
          );
        }
        _onRefocus?.call();
        return;
      }

      // 5) Fallback - offer to attach barcode to existing item
      if (offerAttachBarcode != null) {
        await offerAttachBarcode(trimmedCode);
      } else {
        await _onUnknownBarcode?.call(trimmedCode);
      }
      _onRefocus?.call();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan error: $e')),
      );
      _onError?.call(e);
      _onRefocus?.call();
    }
  }

  /// Validate a barcode - returns true if it appears to be a valid barcode.
  ///
  /// A valid barcode is not empty and does not contain URL-like characters.
  static bool isValidBarcode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;
    // If it contains slashes, hash, or starts with http, it's likely a URL
    if (trimmed.contains('/') || trimmed.contains('#') || trimmed.startsWith('http')) {
      return false;
    }
    return true;
  }

  /// Check if a code looks like a barcode (digits and hyphens).
  static bool looksLikeBarcode(String code) {
    return RegExp(r'^[\d\-]+$').hasMatch(code.trim());
  }
}
