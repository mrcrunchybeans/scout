import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:scout/widgets/scanner_sheet.dart';


import '../../models/option_item.dart';
import '../../utils/sound_feedback.dart';
import '../../widgets/usb_wedge_scanner.dart';
import 'cart_models.dart';
import '../../data/product_enrichment_service.dart';
import '../../data/lookups_service.dart';





class CartSessionPage extends StatefulWidget {
  final String? sessionId;
  const CartSessionPage({super.key, this.sessionId});

  @override
  State<CartSessionPage> createState() => _CartSessionPageState();
}


class _CartSessionPageState extends State<CartSessionPage> {
  final _db = FirebaseFirestore.instance;
  final _lookups = LookupsService();
  final _barcodeC = TextEditingController();
  final _barcodeFocus = FocusNode();
  final Map<String, String> _grantNames = {};
  final Map<String, String> _intToGrant = {};
  List<OptionItem>? _interventions;
  OptionItem? _selectedIntervention;
  String? _interventionId;
  String? _interventionName;
  String? _defaultGrantId;
  String _locationText = '';
  String _notes = '';
  DateTime? _customStartDate;
  final String _status = 'open';
  String? _sessionId;
  bool _busy = false;
  bool _usbCaptureOn = false;
  final List<CartLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _loadInterventions();
    if (_sessionId != null) {
      _loadSessionData();
    }
  }

  Future<void> _loadSessionData() async {
    if (_sessionId == null) return;

    try {
      final sessionDoc = await _db.collection('cart_sessions').doc(_sessionId).get();
      if (!sessionDoc.exists) return;

      final data = sessionDoc.data()!;
      if (!mounted) return;

      setState(() {
        _interventionId = data['interventionId'] as String?;
        _interventionName = data['interventionName'] as String?;
        _defaultGrantId = data['grantId'] as String?;
        _locationText = data['locationText'] as String? ?? '';
        _notes = data['notes'] as String? ?? '';
        // Load custom start date if it exists
        final startedAt = data['startedAt'];
        if (startedAt is Timestamp) {
          _customStartDate = startedAt.toDate();
        }
        // Set selected intervention if interventions are already loaded
        if (_interventionId != null && _interventions != null) {
          _selectedIntervention = _interventions!.where((i) => i.id == _interventionId).firstOrNull;
        }
      });

      // Load lines
      final linesQuery = await _db.collection('cart_sessions').doc(_sessionId).collection('lines').get();
      if (!mounted) return;

      setState(() {
        _lines.clear();
        for (final doc in linesQuery.docs) {
          final lineData = doc.data();
          _lines.add(CartLine.fromMap(lineData));
        }
      });
    } catch (e) {
      // Handle error silently or show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading session: $e')),
        );
      }
    }
  }

  Future<void> _loadInterventions() async {
    try {
      final interventions = await _lookups.interventions();
      final interventionsSnap = await _db.collection('interventions').where('active', isEqualTo: true).get();
      
      final intToGrant = <String, String>{};
      for (final doc in interventionsSnap.docs) {
        final data = doc.data();
        final defaultGrantId = data['defaultGrantId'] as String?;
        if (defaultGrantId != null) {
          intToGrant[doc.id] = defaultGrantId;
        }
      }

      if (mounted) {
        setState(() {
          _interventions = interventions;
          _intToGrant.addAll(intToGrant);
          // Set selected intervention if we have an interventionId from session data
          if (_interventionId != null) {
            _selectedIntervention = interventions.where((i) => i.id == _interventionId).firstOrNull;
          }
        });
      }
    } catch (e) {
      // Handle error silently
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading interventions: $e')),
        );
      }
    }
  }

  String? get _grantName =>
      _defaultGrantId == null ? null : _grantNames[_defaultGrantId!] ?? _defaultGrantId;

  // ---------- Unified code handler (USB / camera / manual) ----------
  void _refocusQuickAdd() {
    if (!mounted) return;
    // Ensure the quick-add input keeps focus and place the caret at the end
    // without selecting the whole text. Selecting the whole text on every
    // refocus caused the typing/caret to behave oddly for some users.
    FocusScope.of(context).requestFocus(_barcodeFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final len = _barcodeC.text.length;
      _barcodeC.selection = TextSelection.collapsed(offset: len);
    });
  }

  @override
  void dispose() {
    _barcodeC.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String rawCode) async {
    final ctx = context;
    final code = rawCode.trim();
    if (code.isEmpty || _busy) return;

    // soft beep to acknowledge capture
    SoundFeedback.ok();

    try {
      // 1) SCOUT lot QR: SCOUT:LOT:item={ITEM_ID};lot={LOT_ID}
      if (code.startsWith('SCOUT:LOT:')) {
        String? itemId, lotId;
        for (final p in code.substring('SCOUT:LOT:'.length).split(';')) {
          final kv = p.split('=');
          if (kv.length == 2) {
            if (kv[0] == 'item') itemId = kv[1];
            if (kv[0] == 'lot') lotId = kv[1];
          }
        }
        if (itemId != null) {
          final itemSnap = await _db.collection('items').doc(itemId).get();
          if (!ctx.mounted) return;
          if (!itemSnap.exists) throw Exception('Item not found');
          final m = itemSnap.data()!;
          final name = (m['name'] ?? 'Unnamed') as String;
          final baseUnit = (m['baseUnit'] ?? m['unit'] ?? 'each') as String;

          _addOrBumpLine(
            itemId: itemId,
            itemName: name,
            baseUnit: baseUnit,
            lotId: lotId,
          );
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Added: $name')));
          _refocusQuickAdd();
          return;
        }
      }

      // 2) Item barcode search (support 'barcode' and 'barcodes' array)
      QueryDocumentSnapshot<Map<String, dynamic>>? d;
      var q = await _db.collection('items').where('barcode', isEqualTo: code).limit(1).get();
      if (q.docs.isNotEmpty) {
        d = q.docs.first;
      } else {
        q = await _db.collection('items').where('barcodes', arrayContains: code).limit(1).get();
        if (q.docs.isNotEmpty) d = q.docs.first;
      }

      if (d == null) {
        // unknown barcode -> try auto-create with enrichment
        final itemId = await ProductEnrichmentService.createItemWithEnrichment(code, _db);
        if (itemId != null) {
          final itemSnap = await _db.collection('items').doc(itemId).get();
          if (!ctx.mounted) return;
          final data = itemSnap.data()!;
          final name = (data['name'] ?? 'Unnamed') as String;
          final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;
          _addOrBumpLine(
            itemId: itemId,
            itemName: name,
            baseUnit: baseUnit,
          );
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Created and added: $name')));
          _refocusQuickAdd();
          return;
        } else {
          // fallback to offer attach
          SoundFeedback.error();
          if (!ctx.mounted) return;
          await _offerAttachBarcode(code);
          _refocusQuickAdd();
          return;
        }
      }

      final data = d.data();
      final name = (data['name'] ?? 'Unnamed') as String;
      final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;

      // FEFO lot (prefer first with qtyRemaining > 0)
      String? lotId;
      final lots = await _db.collection('items').doc(d.id).collection('lots').get();
      if (lots.docs.isNotEmpty) {
        final list = lots.docs.toList()
          ..sort((a, b) {
            final ta = a.data()['expiresAt'];
            final tb = b.data()['expiresAt'];
            final ea = (ta is Timestamp) ? ta.toDate() : null;
            final eb = (tb is Timestamp) ? tb.toDate() : null;
            if (ea == null && eb == null) return 0;
            if (ea == null) return 1;
            if (eb == null) return -1;
            return ea.compareTo(eb);
          });
        
        // Find first lot with qtyRemaining > 0, or use first lot if none found
        QueryDocumentSnapshot<Map<String, dynamic>>? withQty;
        for (final lot in list) {
          final q = lot.data()['qtyRemaining'];
          if ((q is num) && q > 0) {
            withQty = lot;
            break;
          }
        }
        // If no lot with qty > 0 found, use the first lot
        withQty ??= list.first;
        lotId = withQty.id;
      }

      _addOrBumpLine(itemId: d.id, itemName: name, baseUnit: baseUnit, lotId: lotId);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Added: $name')));
      _refocusQuickAdd();
    } catch (e) {
      if (!ctx.mounted) return;
      SoundFeedback.error();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      _refocusQuickAdd();
    }
  }

  // Camera sheet -> just capture code and hand to unified handler
  Future<void> _scanAndAdd() async {
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ScannerSheet(title: 'Scan item barcode or lot QR'),
    );
    if (code == null || !mounted) return;
    await _handleCode(code);
  }

  /// Quick add by typing/pasting a barcode (calls unified handler)
  Future<void> _addByBarcode() async {
    final raw = _barcodeC.text;
    final normalized = raw.replaceAll(RegExp(r'\s+'), '').trim(); // keep non-digits if present
    if (normalized.isEmpty) return;
    await _handleCode(normalized);
    if (!mounted) return;
    _barcodeC.clear();
  }

  /// Merge-or-add a line
  void _addOrBumpLine({
    required String itemId,
    required String itemName,
    required String baseUnit,
    String? lotId,
  }) {
    setState(() {
      final candidate = CartLine(
        itemId: itemId,
        itemName: itemName,
        baseUnit: baseUnit,
        lotId: lotId,
        initialQty: 1,
      );
      final id = _lineId(candidate);
      final idx = _lines.indexWhere((x) => _lineId(x) == id);
      if (idx >= 0) {
        final old = _lines[idx];
        _lines[idx] = CartLine(
          itemId: old.itemId,
          itemName: old.itemName,
          baseUnit: old.baseUnit,
          lotId: old.lotId,
          initialQty: old.initialQty + 1,
          endQty: old.endQty,
        );
      } else {
        _lines.add(candidate);
      }
    });
  }

  Future<void> _offerAttachBarcode(String code) async {
    final ctx = context;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Unknown barcode'),
        content: Text('No item found with code: $code\nAttach this barcode to an item or create a new one?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Create new item…'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Attach to existing…')),
        ],
      ),
    );

    if (!ctx.mounted) return;

    // "Create new item" chosen
    if (ok == false) {
      Navigator.of(ctx).pushNamed(
        '/new-item',
        arguments: {'initialBarcode': code},
      );
      return;
    }

    // Attach to existing
    if (ok == true) {
      final items = await _db
          .collection('items')
          .orderBy('updatedAt', descending: true)
          .limit(50)
          .get();
      if (!ctx.mounted) return;

      await showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        builder: (sheetCtx) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Attach to item', style: Theme.of(sheetCtx).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final d in items.docs)
              ListTile(
                title: Text((d.data()['name'] ?? 'Unnamed') as String),
                subtitle: Text('On hand: ${(d.data()['qtyOnHand'] ?? 0)}'),
                onTap: () async {
                  final data = d.data();
                  final hasSingle = (data['barcode'] as String?)?.isNotEmpty == true;
              final now = DateTime.now();
                  final user = FirebaseAuth.instance.currentUser;
                  
                  await d.reference.set(
                    {
                      'barcodes': FieldValue.arrayUnion([code]),
                      if (!hasSingle) 'barcode': code,
                      'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
                      'updatedAt': now,
                    },
                    SetOptions(merge: true),
                  );
                  
                  await _db.collection('audit_logs').add({
                    'type': 'item.barcode.attach',
                    'data': {
                      'itemId': d.id,
                      'barcode': code,
                    },
                    'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
                    'createdBy': user?.uid,
                    'createdAt': now,
                  });
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (sheetCtx.mounted) {
                    SoundFeedback.ok();
                    ScaffoldMessenger.of(sheetCtx)
                        .showSnackBar(const SnackBar(content: Text('Barcode attached')));
                  }
                },
              ),
          ],
        ),
      );
    }
  }

  // ---------- Save / close ----------
  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    try {
      final sref = _sessionId == null
          ? _db.collection('cart_sessions').doc()
          : _db.collection('cart_sessions').doc(_sessionId);

      final isNew = _sessionId == null;
      final basePayload = {
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
        if (_customStartDate != null) 'startedAt': Timestamp.fromDate(_customStartDate!),
      };
      
  final now = DateTime.now();
  final user = FirebaseAuth.instance.currentUser;
      
      // Manual audit fields to avoid FieldValue.serverTimestamp()
      final payload = isNew 
          ? {
              ...basePayload,
              'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
              'createdBy': user?.uid,
              'createdAt': Timestamp.fromDate(now),
              'updatedAt': Timestamp.fromDate(now),
            }
          : {
              ...basePayload,
              'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
              'updatedAt': Timestamp.fromDate(now),
            };

      await sref.set(payload, SetOptions(merge: true));
      _sessionId ??= sref.id;

      final batch = _db.batch();
      for (final line in _lines) {
        final lid = _lineId(line);
        final lref = sref.collection('lines').doc(lid);
        // Manual audit fields for line data
        final linePayload = {
          ...line.toMap(),
          'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
          'createdBy': user?.uid,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        };
        batch.set(lref, linePayload, SetOptions(merge: true));
      }
      await batch.commit();

      // Manual audit log to avoid FieldValue.serverTimestamp()
      await _db.collection('audit_logs').add({
        'type': 'session.save',
        'data': {
          'sessionId': _sessionId,
          'numLines': _lines.length,
        },
        'operatorName': user?.displayName ?? user?.email ?? 'Unknown',
        'createdBy': user?.uid,
        'createdAt': Timestamp.fromDate(now),
      });

  final ctx = context;
  if (!ctx.mounted) return;
  SoundFeedback.ok();
  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Draft saved')));
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.error();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    debugPrint('CartSessionPage: Starting session close for session $_sessionId');
    if (_sessionId == null) {
      await _saveDraft();
      if (!mounted) return;
      if (_sessionId == null) return;
    }
    debugPrint('CartSessionPage: Session ID is $_sessionId');
    
    if (_interventionId == null) {
      if (mounted) {
        SoundFeedback.error();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pick an intervention first')));
      }
      return;
    }
    debugPrint('CartSessionPage: Intervention ID is $_interventionId');

    setState(() => _busy = true);
    try {
      final sref = _db.collection('cart_sessions').doc(_sessionId);
      debugPrint('CartSessionPage: Processing ${_lines.length} lines');

  num totalQtyUsed = 0;
  final auditLogs = <Map<String, dynamic>>[]; // Collect audit data
  final now = DateTime.now();

      // Collect all document references for parallel reads
  final itemRefs = <DocumentReference<Map<String, dynamic>>>[];
  final lotRefs = <DocumentReference<Map<String, dynamic>>>[];
      final lineInfoMap = <String, CartLine>{}; // Track which line corresponds to each ref
      
      for (final line in _lines) {
        if (line.usedQty <= 0) continue;
        
        final itemRef = _db.collection('items').doc(line.itemId);
        itemRefs.add(itemRef);
        lineInfoMap[itemRef.path] = line;
        
        if (line.lotId != null) {
          final lotRef = itemRef.collection('lots').doc(line.lotId);
          lotRefs.add(lotRef);
          lineInfoMap[lotRef.path] = line;
        }
      }

      // Read all documents in parallel
      debugPrint('CartSessionPage: Reading ${itemRefs.length} items and ${lotRefs.length} lots in parallel');
  final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
      futures.addAll(itemRefs.map((ref) => ref.get()));
      futures.addAll(lotRefs.map((ref) => ref.get()));
      
      final snapshots = await Future.wait(futures);
      
      // Build lookup maps for fast access
  final itemSnapMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  final lotSnapMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      
      for (int i = 0; i < itemRefs.length; i++) {
        itemSnapMap[itemRefs[i].path] = snapshots[i];
      }
      for (int i = 0; i < lotRefs.length; i++) {
        lotSnapMap[lotRefs[i].path] = snapshots[itemRefs.length + i];
      }

      // Build single large batch with all operations
      final batch = _db.batch();
      var operationCount = 0;

      // Process each line with pre-loaded data
      for (final line in _lines) {
        final used = line.usedQty;
        if (used <= 0) continue;
        totalQtyUsed += used;

        final itemRef = _db.collection('items').doc(line.itemId);
        final itemSnap = itemSnapMap[itemRef.path]!;

        try {
          if (line.lotId != null) {
            // Process lot-based item
            final lotRef = itemRef.collection('lots').doc(line.lotId);
            final lotSnap = lotSnapMap[lotRef.path]!;
            
            if (!lotSnap.exists) {
              throw Exception('Lot ${line.lotId} no longer exists');
            }
            if (!itemSnap.exists) {
              throw Exception('Item ${line.itemName} no longer exists');
            }

            final lotData = lotSnap.data() as Map<String, dynamic>;
            final itemData = itemSnap.data() as Map<String, dynamic>;
            
            final lotRem = (lotData['qtyRemaining'] ?? 0) as num;
            final itemQty = (itemData['qtyOnHand'] ?? 0) as num;

            if (lotRem < used) {
              throw Exception('Insufficient stock in lot ${line.lotId} for ${line.itemName}');
            }

            final newLotRem = (lotRem - used).clamp(0, double.infinity);
            final newItemQty = (itemQty - used).clamp(0, double.infinity);

            // Add lot update to batch
            final lotUpdateData = <String, dynamic>{
              'qtyRemaining': newLotRem,
              'updatedAt': Timestamp.fromDate(now),
            };
            if (lotData['openAt'] == null) {
              lotUpdateData['openAt'] = Timestamp.fromDate(now);
            }
            batch.update(lotRef, lotUpdateData);
            operationCount++;

            // Add item update to batch
            batch.update(itemRef, {
              'qtyOnHand': newItemQty,
              'lastUsedAt': Timestamp.fromDate(now),
              'updatedAt': Timestamp.fromDate(now),
            });
            operationCount++;

            // Add usage log to batch
            final usageRef = _db.collection('usage_logs').doc();
            batch.set(usageRef, {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'lotId': line.lotId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': Timestamp.fromDate(now),
              'interventionId': _interventionId,
              'interventionName': _interventionName,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
              'isReversal': false,
              'createdBy': FirebaseAuth.instance.currentUser?.uid,
              'createdAt': Timestamp.fromDate(now),
            });
            operationCount++;
          } else {
            // Process non-lot item
            if (!itemSnap.exists) {
              throw Exception('Item ${line.itemName} no longer exists');
            }

            final itemData = itemSnap.data() as Map<String, dynamic>;
            final itemQty = (itemData['qtyOnHand'] ?? 0) as num;

            if (itemQty < used) {
              throw Exception('Insufficient stock for ${line.itemName}');
            }

            final newItemQty = (itemQty - used).clamp(0, double.infinity);

            // Add item update to batch
            batch.update(itemRef, {
              'qtyOnHand': newItemQty,
              'lastUsedAt': Timestamp.fromDate(now),
              'updatedAt': Timestamp.fromDate(now),
            });
            operationCount++;

            // Add usage log to batch
            final usageRef = _db.collection('usage_logs').doc();
            batch.set(usageRef, {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': Timestamp.fromDate(now),
              'interventionId': _interventionId,
              'interventionName': _interventionName,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
              'isReversal': false,
              'createdBy': FirebaseAuth.instance.currentUser?.uid,
              'createdAt': Timestamp.fromDate(now),
            });
            operationCount++;
          }

          // Collect audit data
          auditLogs.add({
            'sessionId': _sessionId,
            'itemId': line.itemId,
            'lotId': line.lotId,
            'qtyUsed': used,
            'unit': line.baseUnit,
          });

          debugPrint('CartSessionPage: Prepared operations for ${line.itemName}');
        } catch (e) {
          debugPrint('CartSessionPage: Validation failed for ${line.itemName}: $e');
          throw Exception('Validation failed for ${line.itemName}: $e');
        }
      }

      // Single atomic commit
      debugPrint('CartSessionPage: Committing $operationCount operations in single batch');
      await batch.commit();
      debugPrint('CartSessionPage: All operations committed successfully');

      debugPrint('CartSessionPage: All lines processed successfully');

      // Log all audit entries after transactions complete (move outside transaction)
      // Note: Audit.log calls are moved outside transactions to avoid potential issues

      await sref.set(
        {
          'status': 'closed',
          'closedAt': now,
          'closedBy': FirebaseAuth.instance.currentUser?.uid,
          'operatorName': FirebaseAuth.instance.currentUser?.displayName ?? 
                        FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // High-level audit for the close (simplified)
      try {
        await _db.collection('audit_logs').add({
          'type': 'session.close',
          'data': {
            'sessionId': _sessionId,
            'interventionId': _interventionId,
            'numLines': _lines.length,
            'totalQtyUsed': totalQtyUsed,
          },
          'operatorName': FirebaseAuth.instance.currentUser?.displayName ?? 
                        FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': now,
        });
      } catch (auditError) {
        debugPrint('CartSessionPage: Warning - audit log failed: $auditError');
        // Continue even if audit fails
      }

      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.ok();
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Session closed')));
      Navigator.of(ctx).pop(true);
    } catch (e, stackTrace) {
      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.error();

      // Log the full error for debugging
      debugPrint('CartSessionPage: Error closing session: $e');
      debugPrint('Stack trace: $stackTrace');

      // Handle stock-related errors with user-friendly messages
      String errorMessage = 'Error closing session: $e';
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('stock changed, please refresh')) {
        errorMessage = 'Stock changed, please refresh and try again.';
      } else if (errorString.contains('no longer exists')) {
        errorMessage = 'Some items are no longer available. Please refresh and try again.';
      } else if (errorString.contains('insufficient stock')) {
        errorMessage = 'Insufficient stock for one or more items. Please check quantities and try again.';
      } else if (errorString.contains('permission')) {
        errorMessage = 'Permission denied. Please check your access rights.';
      } else if (errorString.contains('network') || errorString.contains('unavailable')) {
        errorMessage = 'Network error. Please check your connection and try again.';
      }

      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI helpers ----------
  String _lineId(CartLine l) => l.lotId == null ? l.itemId : '${l.itemId}__${l.lotId}';

  Future<void> _addItems() async {
    final itemsSnap =
        await _db.collection('items').orderBy('updatedAt', descending: true).limit(50).get();
    if (!mounted) return;

    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: _AddItemsSheet(items: itemsSnap.docs),
        );
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      for (final itemData in result) {
        final line = CartLine(
          itemId: itemData['itemId'] as String,
          itemName: itemData['itemName'] as String,
          baseUnit: itemData['baseUnit'] as String,
          lotId: itemData['lotId'] as String?,
          initialQty: 1,
        );

        setState(() {
          final id = _lineId(line);
          final idx = _lines.indexWhere((x) => _lineId(x) == id);
          if (idx >= 0) {
            final old = _lines[idx];
            _lines[idx] = CartLine(
              itemId: old.itemId,
              itemName: old.itemName,
              baseUnit: old.baseUnit,
              lotId: old.lotId,
              initialQty: old.initialQty + 1,
              endQty: old.endQty,
            );
          } else {
            _lines.add(line);
          }
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.length} item${result.length == 1 ? '' : 's'} to cart')),
      );
    }
  }

  Future<void> _copyFromLast() async {
    if (_interventionId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick an intervention first')));
      return;
    }
    setState(() => _busy = true);
    try {
      final last = await _db
          .collection('cart_sessions')
          .where('interventionId', isEqualTo: _interventionId)
          .where('status', isEqualTo: 'closed')
          .orderBy('closedAt', descending: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (last.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous session found for this intervention')),
        );
        return;
      }
      final lastId = last.docs.first.id;
      final lines = await _db.collection('cart_sessions').doc(lastId).collection('lines').get();

      if (!mounted) return;
      setState(() {
        _lines.clear();
        for (final d in lines.docs) {
          final m = d.data();
          final prev = CartLine.fromMap(m);
          final leftover = (prev.endQty ?? 0);
          if (leftover <= 0) continue; // Skip items that weren't used

          // Re-resolve FEFO lot for this item instead of copying stale lot ID
          _resolveAndAddLine(prev.itemId, prev.itemName, prev.baseUnit, leftover.toInt());
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Resolve FEFO lot and add line (used by copy from last)
  void _resolveAndAddLine(String itemId, String itemName, String baseUnit, int qty) {
    // Get lots for this item, sorted by expiration (FEFO)
    _db.collection('items').doc(itemId).collection('lots').get().then((lotsSnap) {
      if (!mounted) return;

      String? lotId;
      if (lotsSnap.docs.isNotEmpty) {
        final list = lotsSnap.docs.toList()
          ..sort((a, b) {
            DateTime? ea = (a.data()['expiresAt'] is Timestamp)
                ? (a.data()['expiresAt'] as Timestamp).toDate()
                : null;
            DateTime? eb = (b.data()['expiresAt'] is Timestamp)
                ? (b.data()['expiresAt'] as Timestamp).toDate()
                : null;
            if (ea == null && eb == null) return 0;
            if (ea == null) return 1; // nulls last
            if (eb == null) return -1;
            return ea.compareTo(eb);
          });
        
        // Find first lot with qtyRemaining > 0, or use first lot if none found
        QueryDocumentSnapshot<Map<String, dynamic>>? withQty;
        for (final lot in list) {
          final q = lot.data()['qtyRemaining'];
          if ((q is num) && q > 0) {
            withQty = lot;
            break;
          }
        }
        // If no lot with qty > 0 found, use the first lot
        withQty ??= list.first;
        lotId = withQty.id;
      }

      if (!mounted) return;
      setState(() {
        final line = CartLine(
          itemId: itemId,
          itemName: itemName,
          baseUnit: baseUnit,
          lotId: lotId,
          initialQty: qty,
        );
        _lines.add(line);
      });
    });
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final grantBadge =
        (_defaultGrantId == null) ? null : 'Grant: ${_grantName ?? _defaultGrantId}';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        // Handle browser back button navigation - auto-save draft before leaving
        if (didPop && _status == 'open' && _lines.isNotEmpty && !_busy) {
          debugPrint('CartSessionPage: Browser back navigation - auto-saving draft');
          try {
            await _saveDraft();
          } catch (e) {
            debugPrint('CartSessionPage: Failed to auto-save draft on navigation: $e');
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Cart Session'),
        actions: [
          IconButton(
            tooltip: _usbCaptureOn ? 'USB scanner: on' : 'USB scanner: off',
            icon: Icon(Icons.usb,
                color: _usbCaptureOn
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () => setState(() => _usbCaptureOn = !_usbCaptureOn),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: 'Save draft',
            icon: const Icon(Icons.save),
            onPressed: _busy ? null : _saveDraft,
          ),
        ],
      ),
      body: _busy && _interventions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Invisible USB wedge listener (no clutter)
                UsbWedgeScanner(
                  enabled: _usbCaptureOn,
                  allow: (code) {
                    const okLens = {8, 12, 13, 14};
                    return code.length >= 4 && (okLens.contains(code.length) || code.length > 4);
                  },
                  onCode: (code) => _handleCode(code),
                ),

                // Intervention
                DropdownButtonFormField<OptionItem>(
                  key: ValueKey(_selectedIntervention?.id ?? 'none'),
                  initialValue: _selectedIntervention,
                  items: (_interventions ?? [])
                      .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedIntervention = v;
                      _interventionId = v?.id;
                      _interventionName = v?.name;
                      _defaultGrantId = v == null ? null : _intToGrant[v.id];
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Intervention *'),
                ),
                const SizedBox(height: 8),

                if (grantBadge != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      child: Text(grantBadge, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),

                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: 'Location/Unit (optional)'),
                  onChanged: (s) => _locationText = s,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                  onChanged: (s) => _notes = s,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _customStartDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Session Date (optional)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _customStartDate != null
                          ? '${_customStartDate!.month}/${_customStartDate!.day}/${_customStartDate!.year}'
                          : 'Use current date',
                      style: TextStyle(
                        color: _customStartDate != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),

                // Quick add by barcode (USB or typing)
                const SizedBox(height: 16),
                Text('Quick add by barcode', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barcodeC,
                        focusNode: _barcodeFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'Scan or type a barcode',
                          prefixIcon: Icon(Icons.qr_code_scanner),
                        ),
                        onSubmitted: (_) async {
                          if (_busy) return;
                          await _addByBarcode();
                          _refocusQuickAdd();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : () async {
                        await _addByBarcode();
                        _refocusQuickAdd();
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add items'),
                      onPressed: _busy ? null : _addItems,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history),
                      label: Text(_interventionName != null ? 'Use last for $_interventionName' : 'Copy from last'),
                      onPressed: _busy ? null : _copyFromLast,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan'),
                      onPressed: _busy ? null : _scanAndAdd,
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                if (_lines.isEmpty) const ListTile(title: Text('No items in this session yet')),
                for (final line in _lines)
                  _LineRow(
                    line: line,
                    onChanged: (updated) {
                      setState(() {
                        final id = _lineId(line);
                        final idx = _lines.indexWhere((x) => _lineId(x) == id);
                        if (idx >= 0) _lines[idx] = updated;
                      });
                    },
                    onRemove: () {
                      setState(() {
                        _lines.removeWhere((x) => _lineId(x) == _lineId(line));
                      });
                    },
                  ),

                const SizedBox(height: 24),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save draft'),
                  onPressed: _busy ? null : _saveDraft,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Close session'),
                  onPressed: _busy ? null : _closeSession,
                ),
                if (_status == 'closed')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('This session is closed.', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
        ),
    );
  }
}

class _LineRow extends StatefulWidget {
  final CartLine line;
  final void Function(CartLine) onChanged;
  final VoidCallback onRemove;
  const _LineRow({required this.line, required this.onChanged, required this.onRemove});

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final TextEditingController _cInit;
  late final TextEditingController _cEnd;
  String? _lotCode;

  @override
  void initState() {
    super.initState();
    _cInit = TextEditingController(text: widget.line.initialQty.toString());
    _cEnd = TextEditingController(text: widget.line.endQty?.toString() ?? '');
    _loadLotCode();
  }

  Future<void> _loadLotCode() async {
    if (widget.line.lotId != null) {
      try {
        final lotDoc = await FirebaseFirestore.instance
            .collection('items')
            .doc(widget.line.itemId)
            .collection('lots')
            .doc(widget.line.lotId)
            .get();
        if (lotDoc.exists && mounted) {
          setState(() {
            _lotCode = lotDoc.data()?['lotCode'] ?? widget.line.lotId!.substring(0, 6);
          });
        }
      } catch (e) {
        // If we can't load the lot code, fall back to truncated ID
        if (mounted) {
          setState(() {
            _lotCode = widget.line.lotId!.substring(0, 6);
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(_LineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the line data actually changed from external source (not from our own onChanged)
    // We check if the parsed value differs from current controller value to avoid interfering with user input
    final currentInitValue = num.tryParse(_cInit.text) ?? 0;
    final currentEndValue = num.tryParse(_cEnd.text) ?? 0;

    if (oldWidget.line.initialQty != widget.line.initialQty && currentInitValue != widget.line.initialQty) {
      _cInit.text = widget.line.initialQty.toString();
      _cInit.selection = TextSelection.collapsed(offset: _cInit.text.length);
    }
    if ((oldWidget.line.endQty ?? 0) != (widget.line.endQty ?? 0) && currentEndValue != (widget.line.endQty ?? 0)) {
      _cEnd.text = widget.line.endQty?.toString() ?? '';
      _cEnd.selection = TextSelection.collapsed(offset: _cEnd.text.length);
    }
    // Reload lot code if the lot ID changed
    if (oldWidget.line.lotId != widget.line.lotId) {
      _loadLotCode();
    }
  }

  @override
  void dispose() {
    _cInit.dispose();
    _cEnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(widget.line.itemName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unit: ${widget.line.baseUnit}'
                '${widget.line.lotId != null ? ' • lot ${_lotCode ?? 'Loading...'}' : ''}'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cInit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Loaded'),
                    onSubmitted: (s) => widget.onChanged(CartLine(
                      itemId: widget.line.itemId,
                      itemName: widget.line.itemName,
                      baseUnit: widget.line.baseUnit,
                      lotId: widget.line.lotId,
                      initialQty: num.tryParse(s) ?? widget.line.initialQty,
                      endQty: widget.line.endQty,
                    )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cEnd,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Leftover (at close)'),
                    onSubmitted: (s) => widget.onChanged(CartLine(
                      itemId: widget.line.itemId,
                      itemName: widget.line.itemName,
                      baseUnit: widget.line.baseUnit,
                      lotId: widget.line.lotId,
                      initialQty: widget.line.initialQty,
                      endQty: s.trim().isEmpty ? null : num.tryParse(s),
                    )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Used this session: ${widget.line.usedQty} ${widget.line.baseUnit}'),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: widget.onRemove,
        ),
      ),
    );
  }
}

class LotSelectionDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedItems;

  const LotSelectionDialog({super.key, required this.selectedItems});

  @override
  State<LotSelectionDialog> createState() => _LotSelectionDialogState();
}

class _LotSelectionDialogState extends State<LotSelectionDialog> {
  final Map<String, String?> _selectedLotIds = {};

  @override
  void initState() {
    super.initState();
    // Initialize with null selections - lots will be loaded via FutureBuilder
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Lots'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.selectedItems.length,
          itemBuilder: (context, index) {
            final item = widget.selectedItems[index];
            final itemName = (item.data()['name'] ?? 'Unnamed') as String;
            final baseUnit = (item.data()['baseUnit'] ?? item.data()['unit'] ?? 'each') as String;

            return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('items').doc(item.id).collection('lots').get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListTile(
                    title: Text(itemName),
                    subtitle: const Text('Loading lots...'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return ListTile(
                    title: Text(itemName),
                    subtitle: const Text('No lots available'),
                  );
                }

                final lots = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    DateTime? ea = (a.data()['expiresAt'] is Timestamp)
                        ? (a.data()['expiresAt'] as Timestamp).toDate()
                        : null;
                    DateTime? eb = (b.data()['expiresAt'] is Timestamp)
                        ? (b.data()['expiresAt'] as Timestamp).toDate()
                        : null;
                    if (ea == null && eb == null) return 0;
                    if (ea == null) return 1; // nulls last
                    if (eb == null) return -1;
                    return ea.compareTo(eb);
                  });

                // Auto-select FEFO lot if not already selected
                if (_selectedLotIds[item.id] == null && lots.isNotEmpty) {
                  // Find first lot with qtyRemaining > 0, or use first lot if none found
                  QueryDocumentSnapshot<Map<String, dynamic>>? withQty;
                  for (final lot in lots) {
                    final q = lot.data()['qtyRemaining'];
                    if ((q is num) && q > 0) {
                      withQty = lot;
                      break;
                    }
                  }
                  withQty ??= lots.first;
                  _selectedLotIds[item.id] = withQty.id;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        itemName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...lots.map((lot) {
                      final lotData = lot.data();
                      final qtyRemaining = lotData['qtyRemaining'] ?? 0;
                      final expiresAt = lotData['expiresAt'] is Timestamp
                          ? (lotData['expiresAt'] as Timestamp).toDate()
                          : null;
                      final lotCode = lotData['lotCode'] ?? lot.id;

                      // ignore: deprecated_member_use
                      return RadioListTile<String>(
                        title: Text('$lotCode • $qtyRemaining $baseUnit'),
                        subtitle: expiresAt != null
                            ? Text('Expires: ${MaterialLocalizations.of(context).formatShortDate(expiresAt)}')
                            : null,
                        value: lot.id,
                        // ignore: deprecated_member_use
                        groupValue: _selectedLotIds[item.id],
                        // ignore: deprecated_member_use
                        onChanged: qtyRemaining > 0 ? (value) {
                          setState(() {
                            _selectedLotIds[item.id] = value;
                          });
                        } : null,
                        dense: true,
                      );
                    }),
                    const Divider(),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final itemDetails = widget.selectedItems.map((item) {
              final baseUnit = (item.data()['baseUnit'] ?? item.data()['unit'] ?? 'each') as String;
              return {
                'itemId': item.id,
                'itemName': (item.data()['name'] ?? 'Unnamed') as String,
                'baseUnit': baseUnit,
                'lotId': _selectedLotIds[item.id],
              };
            }).toList();

            Navigator.of(context).pop(itemDetails);
          },
          child: const Text('Add to Cart'),
        ),
      ],
    );
  }
}

class _AddItemsSheet extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;

  const _AddItemsSheet({required this.items});

  @override
  State<_AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSheetState extends State<_AddItemsSheet> {
  final _searchController = TextEditingController();
  String _searchText = '';
  final Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filteredItems {
    if (_searchText.isEmpty) return widget.items;
    return widget.items.where((item) {
      final name = (item.data()['name'] ?? 'Unnamed') as String;
      return name.toLowerCase().contains(_searchText);
    }).toList();
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _addSingleItem(QueryDocumentSnapshot<Map<String, dynamic>> item) async {
    // Show lot selection dialog for single item
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => LotSelectionDialog(selectedItems: [item]),
    );

    if (result != null) {
      // Use a post-frame callback to ensure we're on the right context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pop(result);
        }
      });
    }
  }

  Future<void> _addSelectedItems() async {
    if (_selectedItemIds.isEmpty) return;

    final selectedItems = widget.items.where((item) => _selectedItemIds.contains(item.id)).toList();

    // Show lot selection dialog
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => LotSelectionDialog(selectedItems: selectedItems),
    );

    if (result != null) {
      // Use a post-frame callback to ensure we're on the right context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pop(result);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with title and search
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Add items to cart', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (_selectedItemIds.isNotEmpty)
                    Text(
                      '${_selectedItemIds.length} selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        
        // Items list
        Expanded(
          child: ListView.builder(
            itemCount: _filteredItems.length,
            itemBuilder: (context, index) {
              final d = _filteredItems[index];
              final isSelected = _selectedItemIds.contains(d.id);
              
              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) => _toggleSelection(d.id),
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
                title: Text((d.data()['name'] ?? 'Unnamed') as String),
                subtitle: Text('On hand: ${(d.data()['qtyOnHand'] ?? 0)} • Tap to add individually'),
                onTap: () => _addSingleItem(d),
              );
            },
          ),
        ),
        
        // Bottom action bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedItemIds.isEmpty
                      ? 'Select items to add'
                      : '${_selectedItemIds.length} item${_selectedItemIds.length == 1 ? '' : 's'} selected',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _selectedItemIds.isNotEmpty ? _addSelectedItems : null,
                icon: const Icon(Icons.add),
                label: const Text('Add Selected'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
