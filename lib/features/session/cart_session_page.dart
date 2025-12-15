import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:scout/widgets/scanner_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../utils/operator_store.dart';
import '../../models/option_item.dart';
import '../../utils/sound_feedback.dart';
import '../../widgets/usb_wedge_scanner.dart';
import '../../widgets/weight_calculator_dialog.dart';
import 'cart_models.dart';
import '../../data/product_enrichment_service.dart';
import '../../data/lookups_service.dart';
import '../../services/time_tracking_service.dart';
import '../../services/cart_print_service.dart';





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
  final _locationC = TextEditingController();
  final _notesC = TextEditingController();
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
  String _status = 'open';
  String? _sessionId;
  bool _busy = false;
  bool _usbCaptureOn = false;
  final List<CartLine> _lines = [];
  final Map<String, bool> _overAllocatedLines = {};
  
  // Track line IDs that exist in Firestore (for deletion sync)
  final Set<String> _savedLineIds = {};
  
  // Mobile scanner session
  late final String _mobileScannerSessionId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _scannerSubscription;
  
  // Auto-save timer
  Timer? _autoSaveTimer;
  bool _autoSavePending = false;
  bool _isSaving = false;

  bool get _hasOverAllocatedLines => _overAllocatedLines.values.any((v) => v);
  bool get _isClosed => _status == 'closed';

  /// Get the current user's display name for audit logs.
  /// Prefers OperatorStore (user-set name), falls back to Firebase Auth displayName/email.
  String get _operatorName {
    // First check OperatorStore (user manually set their name)
    final storedName = OperatorStore.name.value;
    if (storedName != null && storedName.isNotEmpty) return storedName;
    
    // Fall back to Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'System';
    // Check displayName first (handle empty string as null)
    final name = user.displayName;
    if (name != null && name.isNotEmpty) return name;
    // Fall back to email
    final email = user.email;
    if (email != null && email.isNotEmpty) return email;
    return 'System';
  }

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _mobileScannerSessionId = const Uuid().v4();
    _listenForMobileScans();
    _syncFormControllers();
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
        _status = (data['status'] as String?)?.toLowerCase() ?? 'open';
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

      _syncFormControllers();

      // Load lines
      final linesQuery = await _db.collection('cart_sessions').doc(_sessionId).collection('lines').get();
      if (!mounted) return;

      setState(() {
        _lines.clear();
        _overAllocatedLines.clear();
        _savedLineIds.clear();
        for (final doc in linesQuery.docs) {
          final lineData = doc.data();
          final line = CartLine.fromMap(lineData);
          _lines.add(line);
          final lineId = _lineId(line);
          _overAllocatedLines[lineId] = false;
          _savedLineIds.add(lineId); // Track what's in Firestore
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

  void _syncFormControllers() {
    _locationC
      ..text = _locationText
      ..selection = TextSelection.collapsed(offset: _locationText.length);
    _notesC
      ..text = _notes
      ..selection = TextSelection.collapsed(offset: _notes.length);
  }

  String _formatQty(num value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    final formatted = value.toStringAsFixed(2);
    return formatted.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  void dispose() {
    _barcodeC.dispose();
    _barcodeFocus.dispose();
    _locationC.dispose();
    _notesC.dispose();
    _scannerSubscription?.cancel();
    _autoSaveTimer?.cancel();
    // Perform final save if there are pending changes
    if (_autoSavePending && _lines.isNotEmpty) {
      _saveDraft(); // Fire and forget on dispose
    }
    // Clean up scanner session
    _db.collection('scanner_sessions').doc(_mobileScannerSessionId).delete().catchError((_) {});
    super.dispose();
  }
  
  /// Triggers a debounced auto-save after changes to the cart
  void _triggerAutoSave() {
    if (_isClosed) return; // Don't auto-save closed sessions
    _autoSavePending = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || _isClosed) return;
      _autoSavePending = false;
      await _saveDraft(silent: true);
    });
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

      if (d != null) {
        final data = d.data();
        final isArchived = data['archived'] == true;
        
        // If item is archived, offer to reactivate it
        if (isArchived) {
          if (!ctx.mounted) return;
          final shouldReactivate = await showDialog<bool>(
            context: ctx,
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
            await _db.collection('items').doc(d.id).update({
              'archived': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            
            // Log the reactivation
            await _db.collection('audit_logs').add({
              'type': 'item.unarchive',
              'data': {
                'itemId': d.id,
                'name': data['name'],
                'reason': 'barcode_scan_reactivation',
              },
              'operatorName': _operatorName,
              'createdBy': FirebaseAuth.instance.currentUser?.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('Reactivated: ${data['name']}')),
            );
          } else {
            _refocusQuickAdd();
            return;
          }
        }
        
        final name = (data['name'] ?? 'Unnamed') as String;
        final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;

        // FEFO lot (prefer first with qtyRemaining > 0)
        final lotId = await _fefoLotIdForItem(d.id);

        _addOrBumpLine(itemId: d.id, itemName: name, baseUnit: baseUnit, lotId: lotId);
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Added: $name')));
        _refocusQuickAdd();
        return;
      }

      // d == null: unknown barcode -> try auto-create with enrichment
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

  void _listenForMobileScans() {
    _scannerSubscription = _db
        .collection('scanner_sessions')
        .doc(_mobileScannerSessionId)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final scan = snapshot.docs.first;
        final barcode = scan.data()['barcode'] as String?;
        final processed = scan.data()['processed'] as bool? ?? false;
        
        if (barcode != null && !processed && mounted) {
          _handleCode(barcode);
          // Mark as processed
          scan.reference.update({'processed': true});
        }
      }
    });
  }

  void _showMobileScannerQR() {
    final url = 'https://scout.littleempathy.com/mobile-scanner/$_mobileScannerSessionId';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan with Phone'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this QR code with your phone to use it as a barcode scanner:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session: ${_mobileScannerSessionId.substring(0, 8)}...',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scanned barcodes will appear and be added automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _openQuickSearch({String? initialQuery}) async {
    if (!mounted) return false;
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuickItemSearchSheet(initialQuery: initialQuery),
    );

    if (result == null) return false;

    final List<Map<String, dynamic>> entries;
    if (result is Map<String, dynamic>) {
      entries = [result];
    } else if (result is List) {
      entries = result.cast<Map<String, dynamic>>();
    } else {
      return false;
    }

    int addedCount = 0;
    final Set<String> itemNames = {};

    for (final entry in entries) {
      final itemId = entry['itemId'] as String;
      final itemName = entry['itemName'] as String;
      final baseUnit = entry['baseUnit'] as String;
      final autoAssignLot = entry['autoAssignLot'] == true;
      String? lotId = entry['lotId'] as String?;

      if (autoAssignLot) {
        lotId = await _fefoLotIdForItem(itemId);
        if (!mounted) return addedCount > 0;
      }

      _addOrBumpLine(itemId: itemId, itemName: itemName, baseUnit: baseUnit, lotId: lotId);
      addedCount++;
      itemNames.add(itemName);
    }

    if (!mounted || addedCount == 0) return addedCount > 0;

    final message = addedCount == 1
        ? 'Added: ${itemNames.first}'
        : 'Added $addedCount items';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _refocusQuickAdd();
    return true;
  }

  /// Quick add by typing/pasting a barcode (calls unified handler)
  Future<void> _addByBarcode() async {
    final raw = _barcodeC.text;
    final normalized = raw.replaceAll(RegExp(r'\s+'), '').trim(); // keep non-digits if present
    if (normalized.isEmpty) return;
    if (_looksLikeItemName(normalized)) {
      final added = await _openQuickSearch(initialQuery: raw.trim());
      if (!mounted) return;
      if (added) {
        _barcodeC.clear();
        return;
      }
    }
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
        _overAllocatedLines[id] = false;
      }
    });
    _triggerAutoSave();
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
                  
                  await d.reference.set(
                    {
                      'barcodes': FieldValue.arrayUnion([code]),
                      if (!hasSingle) 'barcode': code,
                      'operatorName': _operatorName,
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
                    'operatorName': _operatorName,
                    'createdBy': FirebaseAuth.instance.currentUser?.uid,
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
  Future<void> _saveDraft({bool silent = false}) async {
    setState(() {
      _busy = true;
      _isSaving = true;
    });
    try {
      _locationText = _locationC.text;
      _notes = _notesC.text;

      final sref = _sessionId == null
          ? _db.collection('cart_sessions').doc()
          : _db.collection('cart_sessions').doc(_sessionId);

      final isNew = _sessionId == null;
      final now = DateTime.now();
      final sessionDate = _customStartDate ?? DateTime(now.year, now.month, now.day);
      final basePayload = {
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
        'startedAt': Timestamp.fromDate(sessionDate),
      };
      
      final user = FirebaseAuth.instance.currentUser;
      
      // Manual audit fields to avoid FieldValue.serverTimestamp()
      final payload = isNew 
          ? {
              ...basePayload,
              'operatorName': _operatorName,
              'createdBy': user?.uid,
              'createdAt': Timestamp.fromDate(now),
              'updatedAt': Timestamp.fromDate(now),
            }
          : {
              ...basePayload,
              'operatorName': _operatorName,
              'updatedAt': Timestamp.fromDate(now),
            };

      await sref.set(payload, SetOptions(merge: true));
      _sessionId ??= sref.id;

      // Collect current line IDs
      final currentLineIds = <String>{};
      
      final batch = _db.batch();
      for (final line in _lines) {
        final lid = _lineId(line);
        currentLineIds.add(lid);
        final lref = sref.collection('lines').doc(lid);
        // Manual audit fields for line data
        final linePayload = {
          ...line.toMap(),
          'operatorName': _operatorName,
          'createdBy': user?.uid,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        };
        batch.set(lref, linePayload, SetOptions(merge: true));
      }
      
      // Delete lines that were removed (exist in _savedLineIds but not in currentLineIds)
      final deletedLineIds = _savedLineIds.difference(currentLineIds);
      for (final deletedId in deletedLineIds) {
        final lref = sref.collection('lines').doc(deletedId);
        batch.delete(lref);
      }
      
      await batch.commit();
      
      // Update saved line IDs to match current state
      _savedLineIds
        ..clear()
        ..addAll(currentLineIds);

      // Manual audit log to avoid FieldValue.serverTimestamp()
      await _db.collection('audit_logs').add({
        'type': 'session.save',
        'data': {
          'sessionId': _sessionId,
          'numLines': _lines.length,
          if (deletedLineIds.isNotEmpty) 'deletedLines': deletedLineIds.length,
        },
        'operatorName': _operatorName,
        'createdBy': user?.uid,
        'createdAt': Timestamp.fromDate(now),
      });

      if (mounted) {
        setState(() {
          _status = 'open';
        });
      }

      if (mounted && _customStartDate == null) {
        setState(() {
          _customStartDate = sessionDate;
        });
      }

      if (!silent) {
        final ctx = context;
        if (!ctx.mounted) return;
        SoundFeedback.ok();
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Draft saved')));
      }
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.error();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _isSaving = false;
      });
    }
  }

  /// Print a checklist for counting items before starting the session.
  /// Useful for interns or staff to verify quantities.
  void _printChecklist({ChecklistType type = ChecklistType.preparation}) {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add items to the cart before printing checklist')),
      );
      return;
    }

    // Convert cart lines to checklist items
    final checklistItems = _lines.map((line) {
      // Use initialQty for preparation, endQty for leftover
      final qty = type == ChecklistType.preparation ? line.initialQty : (line.endQty ?? 0);
      
      return CartChecklistItem(
        name: line.itemName,
        quantity: qty,
        unit: line.baseUnit,
        lotCode: line.lotCode,
        barcode: null, // Barcode not available in cart line
      );
    }).toList();

    // Print the checklist
    CartPrintService.printCartChecklist(
      items: checklistItems,
      interventionName: _interventionName,
      location: _locationText.trim().isEmpty ? null : _locationText.trim(),
      notes: _notes.trim().isEmpty ? null : _notes.trim(),
      type: type,
    );

    // Show confirmation
    final typeLabel = type == ChecklistType.preparation ? 'preparation' : 'leftover';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📄 Printing $typeLabel checklist... Check your browser\'s print dialog'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openTimeTrackingUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;

    Uri? uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.isEmpty) {
      uri = Uri.tryParse('https://$trimmed');
    }

    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open time tracking link. Please check the admin settings.')),
      );
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open time tracking link.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open time tracking link: $e')),
      );
    }
  }

  Future<bool> _showCloseSummaryDialog({
    required List<CartLine> usedLines,
    required num totalQty,
    required TimeTrackingConfig config,
  }) async {
    if (!mounted) return false;

    final totalItems = usedLines.length;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) {
            final theme = Theme.of(dialogCtx);
            final summaryText = totalItems > 0
                ? 'Review what was used before closing this cart.'
                : 'No usage has been recorded for this cart.';

            return AlertDialog(
              title: const Text('Close session?'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summaryText, style: theme.textTheme.bodyMedium),
                    if (totalItems > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Items used: $totalItems • Total quantity: ${_formatQty(totalQty)}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < usedLines.length; i++) ...[
                                if (i > 0) const Divider(height: 16),
                                Text(
                                  usedLines[i].itemName,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Builder(
                                  builder: (_) {
                                    final line = usedLines[i];
                                    final lotLabel = line.lotCode ?? line.lotId;
                                    final lotSuffix = lotLabel != null ? ' • Lot $lotLabel' : '';
                                    return Text(
                                      '${_formatQty(line.usedQty)} ${line.baseUnit}$lotSuffix',
                                      style: theme.textTheme.bodySmall,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (config.isValid) ...[
                      const SizedBox(height: 16),
                      Text('Need to log your time?', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open time tracking site'),
                          onPressed: () async {
                            await _openTimeTrackingUrl(config.url);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: const Text('Close session'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _closeSession() async {
    debugPrint('CartSessionPage: Starting session close for session $_sessionId');
    if (_hasOverAllocatedLines) {
      if (mounted) {
        SoundFeedback.error();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resolve over-allocated lots before closing the session.')),
        );
      }
      return;
    }
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

    final usedLines = _lines.where((line) => line.usedQty > 0).toList();
  final summaryTotalQty = usedLines.fold<num>(0, (acc, line) => acc + line.usedQty);
    final timeTrackingConfig = await TimeTrackingService.getConfig();
    if (!mounted) return;

    final confirmed = await _showCloseSummaryDialog(
      usedLines: usedLines,
      totalQty: summaryTotalQty,
      config: timeTrackingConfig,
    );
    if (!mounted) return;
    if (!confirmed) {
      debugPrint('CartSessionPage: Session close cancelled by user');
      return;
    }

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
      final List<Map<String, dynamic>> lotsToArchive = [];

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
            // Auto-archive lot when it hits 0 remaining
            if (newLotRem <= 0) {
              lotUpdateData['archived'] = true;
              lotsToArchive.add({
                'itemId': line.itemId,
                'lotId': line.lotId,
                'lotCode': lotData['lotCode'] ?? line.lotId,
              });
              debugPrint('CartSessionPage: Lot ${line.lotId} will be auto-archived (newLotRem=$newLotRem)');
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
              'operatorName': _operatorName,
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
              'operatorName': _operatorName,
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
          'operatorName': _operatorName,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() {
          _status = 'closed';
        });
      }

      // High-level audit for the close (simplified)
      try {
        await _db.collection('audit_logs').add({
          'type': 'session.close',
          'data': {
            'sessionId': _sessionId,
            'interventionId': _interventionId,
            'numLines': _lines.length,
            'totalQtyUsed': totalQtyUsed,
            'lotsArchived': lotsToArchive.length,
          },
          'operatorName': _operatorName,
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': now,
        });
        
        // Log individual lot archive events
        for (final lot in lotsToArchive) {
          await _db.collection('audit_logs').add({
            'type': 'lot.archive',
            'data': {
              'itemId': lot['itemId'],
              'lotId': lot['lotId'],
              'lotCode': lot['lotCode'],
              'reason': 'cart_session_depleted',
              'sessionId': _sessionId,
            },
            'operatorName': _operatorName,
            'createdBy': FirebaseAuth.instance.currentUser?.uid,
            'createdAt': now,
          });
        }
      } catch (auditError) {
        debugPrint('CartSessionPage: Warning - audit log failed: $auditError');
        // Continue even if audit fails
      }

      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.ok();
      
      // Show message with archived lots count if any
      final archivedCount = lotsToArchive.length;
      final message = archivedCount > 0 
          ? 'Session closed. $archivedCount lot${archivedCount == 1 ? '' : 's'} auto-archived (depleted).'
          : 'Session closed';
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _reopenSession() async {
    if (_sessionId == null || _status != 'closed') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reopen Session?'),
        content: const Text(
          'This will reverse all inventory deductions from this session and allow editing again. '
          'The items will be credited back as if the session was never closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      debugPrint('CartSessionPage: Reopening session $_sessionId');

      // Find all usage logs for this session
      final usageLogsQuery = await _db
          .collection('usage_logs')
          .where('sessionId', isEqualTo: _sessionId)
          .where('isReversal', isEqualTo: false)
          .get();

      debugPrint('CartSessionPage: Found ${usageLogsQuery.docs.length} usage logs to reverse');

      if (usageLogsQuery.docs.isEmpty) {
        debugPrint('CartSessionPage: No usage logs found, just updating session status');
        await _db.collection('cart_sessions').doc(_sessionId).update({
          'status': 'open',
          'reopenedAt': DateTime.now(),
          'reopenedBy': FirebaseAuth.instance.currentUser?.uid,
          'updatedAt': DateTime.now(),
        });

        if (mounted) {
          setState(() => _status = 'open');
          SoundFeedback.ok();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session reopened')),
          );
        }
        return;
      }

      // Build batch to recredit items and delete usage logs
      final batch = _db.batch();
      final now = DateTime.now();
      var operationCount = 0;

      for (final usageDoc in usageLogsQuery.docs) {
        final usage = usageDoc.data();
        final itemId = usage['itemId'] as String?;
        final lotId = usage['lotId'] as String?;
        final qtyUsed = (usage['qtyUsed'] as num?)?.toDouble() ?? 0.0;

        if (itemId == null || qtyUsed <= 0) continue;

        final itemRef = _db.collection('items').doc(itemId);

        if (lotId != null) {
          // Recredit lot-based item
          final lotRef = itemRef.collection('lots').doc(lotId);
          
          // Add back to lot
          batch.update(lotRef, {
            'qtyRemaining': FieldValue.increment(qtyUsed),
            'updatedAt': Timestamp.fromDate(now),
          });
          operationCount++;

          // Add back to item
          batch.update(itemRef, {
            'qtyOnHand': FieldValue.increment(qtyUsed),
            'updatedAt': Timestamp.fromDate(now),
          });
          operationCount++;
        } else {
          // Recredit non-lot item
          batch.update(itemRef, {
            'qtyOnHand': FieldValue.increment(qtyUsed),
            'updatedAt': Timestamp.fromDate(now),
          });
          operationCount++;
        }

        // Delete the usage log
        batch.delete(usageDoc.reference);
        operationCount++;

        debugPrint('CartSessionPage: Prepared recredit for item $itemId, qty: $qtyUsed');
      }

      // Update session status
      batch.update(_db.collection('cart_sessions').doc(_sessionId!), {
        'status': 'open',
        'reopenedAt': now,
        'reopenedBy': FirebaseAuth.instance.currentUser?.uid,
        'updatedAt': now,
      });
      operationCount++;

      // Commit all changes atomically
      debugPrint('CartSessionPage: Committing $operationCount operations');
      await batch.commit();
      debugPrint('CartSessionPage: Session reopened successfully');

      // Add audit log
      try {
        await _db.collection('audit_logs').add({
          'type': 'session.reopen',
          'data': {
            'sessionId': _sessionId,
            'numUsageLogsReversed': usageLogsQuery.docs.length,
          },
          'operatorName': _operatorName,
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': now,
        });
      } catch (auditError) {
        debugPrint('CartSessionPage: Warning - audit log failed: $auditError');
      }

      if (mounted) {
        setState(() => _status = 'open');
        SoundFeedback.ok();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session reopened - inventory has been recredited')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('CartSessionPage: Error reopening session: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        SoundFeedback.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reopening session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI helpers ----------
  String _lineId(CartLine l) => l.lotId == null ? l.itemId : '${l.itemId}__${l.lotId}';

  Future<String?> _fefoLotIdForItem(String itemId) async {
    final lotsSnap = await _db.collection('items').doc(itemId).collection('lots').get();
    if (lotsSnap.docs.isEmpty) return null;

    final lots = lotsSnap.docs.toList()
      ..sort((a, b) {
        DateTime? ea = (a.data()['expiresAt'] is Timestamp)
            ? (a.data()['expiresAt'] as Timestamp).toDate()
            : null;
        DateTime? eb = (b.data()['expiresAt'] is Timestamp)
            ? (b.data()['expiresAt'] as Timestamp).toDate()
            : null;
        if (ea == null && eb == null) return 0;
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.compareTo(eb);
      });

    QueryDocumentSnapshot<Map<String, dynamic>>? withQty;
    for (final lot in lots) {
      final q = lot.data()['qtyRemaining'];
      if (q is num && q > 0) {
        withQty = lot;
        break;
      }
    }

    return (withQty ?? lots.first).id;
  }

  bool _looksLikeItemName(String input) {
    final cleaned = input.trim();
    if (cleaned.length < 3) return false;
    if (cleaned.contains(' ')) return true;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(cleaned).length;
    if (letterCount < 2) return false;
    final digitCount = RegExp(r'\d').allMatches(cleaned).length;
    return letterCount > digitCount;
  }

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
        final itemId = itemData['itemId'] as String;
        final itemName = itemData['itemName'] as String;
        final baseUnit = itemData['baseUnit'] as String;
        final autoAssignLot = itemData['autoAssignLot'] == true;
        String? lotId = itemData['lotId'] as String?;

        if (autoAssignLot) {
          lotId = await _fefoLotIdForItem(itemId);
          if (!mounted) return;
        }

        final line = CartLine(
          itemId: itemId,
          itemName: itemName,
          baseUnit: baseUnit,
          lotId: lotId,
          initialQty: 1,
        );

        if (!mounted) return;
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
            _overAllocatedLines[id] = false;
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
        _overAllocatedLines.clear();
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
    _fefoLotIdForItem(itemId).then((lotId) {
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
        _overAllocatedLines[_lineId(line)] = false;
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
            onPressed: _isClosed ? null : () => setState(() => _usbCaptureOn = !_usbCaptureOn),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            icon: const Icon(Icons.phone_android),
            tooltip: 'Scan with Phone',
            onPressed: (_busy || _isClosed) ? null : _showMobileScannerQR,
          ),
          IconButton(
            tooltip: _isSaving ? 'Saving...' : (_autoSavePending ? 'Auto-saving soon...' : 'Save draft'),
            icon: _isSaving
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : Icon(
                    _autoSavePending ? Icons.sync : Icons.save,
                    color: _autoSavePending ? Theme.of(context).colorScheme.tertiary : null,
                  ),
            onPressed: (_busy || _isClosed) ? null : () => _saveDraft(silent: false),
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
                  onChanged: _isClosed ? null : (v) {
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
                  controller: _locationC,
                  decoration: const InputDecoration(labelText: 'Location/Unit (optional)'),
                  enabled: !_isClosed,
                  onChanged: (s) => _locationText = s,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesC,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                  enabled: !_isClosed,
                  onChanged: (s) => _notes = s,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _isClosed ? null : () async {
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
                        enabled: !_isClosed,
                        decoration: InputDecoration(
                          hintText: 'Scan or type a barcode',
                          prefixIcon: IconButton(
                            tooltip: 'Scan with camera',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: (_busy || _isClosed) ? null : () => _scanAndAdd(),
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Search by name',
                            icon: const Icon(Icons.search),
                            onPressed: (_busy || _isClosed)
                                ? null
                                : () async {
                                    final query = _barcodeC.text.trim();
                                    final added = await _openQuickSearch(
                                      initialQuery: query.isEmpty ? null : query,
                                    );
                                    if (!mounted) return;
                                    if (added) {
                                      _barcodeC.clear();
                                    }
                                  },
                          ),
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
                      onPressed: (_busy || _isClosed) ? null : () async {
                        await _addByBarcode();
                        _refocusQuickAdd();
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add items'),
                      onPressed: (_busy || _isClosed) ? null : _addItems,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history),
                      label: Text(_interventionName != null ? 'Use last for $_interventionName' : 'Copy from last'),
                      onPressed: (_busy || _isClosed) ? null : _copyFromLast,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan'),
                      onPressed: (_busy || _isClosed) ? null : _scanAndAdd,
                    ),
                    if (_lines.isNotEmpty) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('Print Prep Checklist'),
                        onPressed: _busy ? null : () => _printChecklist(type: ChecklistType.preparation),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.tertiary,
                          side: BorderSide(color: Theme.of(context).colorScheme.tertiary),
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.inventory_2),
                        label: const Text('Print Leftover Checklist'),
                        onPressed: _busy ? null : () => _printChecklist(type: ChecklistType.leftover),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.secondary,
                          side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                        ),
                      ),
                    ],
                  ],
                ),

                if (_hasOverAllocatedLines && !_isClosed) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                      title: Text(
                        'Adjust quantities or choose another lot before closing. Requested amounts exceed remaining stock in at least one lot.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                if (_lines.isEmpty) const ListTile(title: Text('No items in this session yet')),
                for (final line in _lines)
                                _LineRow(
                                  key: ValueKey(_lineId(line)),
                                  lineId: _lineId(line),
                                  line: line,
                    isClosed: _isClosed,
                    onChanged: (updated) {
                      setState(() {
                        final oldId = _lineId(line);
                        final newId = _lineId(updated);
                        
                        // Check if changing to a lot that already exists in another line
                        final existingIdx = _lines.indexWhere((x) => _lineId(x) == newId);
                        final oldIdx = _lines.indexWhere((x) => _lineId(x) == oldId);
                        
                        if (oldId != newId && existingIdx >= 0 && existingIdx != oldIdx) {
                          // Merge: add quantities to existing line, then remove the old line
                          final existing = _lines[existingIdx];
                          _lines[existingIdx] = CartLine(
                            itemId: existing.itemId,
                            itemName: existing.itemName,
                            baseUnit: existing.baseUnit,
                            lotId: existing.lotId,
                            lotCode: existing.lotCode,
                            initialQty: existing.initialQty + updated.initialQty,
                            endQty: existing.endQty,
                          );
                          // Remove the old line
                          _lines.removeAt(oldIdx > existingIdx ? oldIdx : oldIdx);
                          _overAllocatedLines.remove(oldId);
                        } else if (oldIdx >= 0) {
                          // Normal update
                          _lines[oldIdx] = updated;
                          if (oldId != newId) {
                            final previous = _overAllocatedLines.remove(oldId) ?? false;
                            _overAllocatedLines[newId] = previous;
                          } else {
                            _overAllocatedLines.putIfAbsent(newId, () => false);
                          }
                        }
                      });
                      _triggerAutoSave();
                    },
                    onRemove: () {
                      setState(() {
                                      final id = _lineId(line);
                                      _lines.removeWhere((x) => _lineId(x) == id);
                                      _overAllocatedLines.remove(id);
                      });
                      _triggerAutoSave();
                    },
                                  onOverAllocationChanged: (lineId, isOver) {
                                    final prev = _overAllocatedLines[lineId];
                                    if (prev == isOver) return;
                                    setState(() {
                                      _overAllocatedLines[lineId] = isOver;
                                    });
                                  },
                  ),

                const SizedBox(height: 24),
                if (!_isClosed) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save draft'),
                    onPressed: _busy ? null : _saveDraft,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Close session'),
                    onPressed: (_busy || _hasOverAllocatedLines) ? null : _closeSession,
                  ),
                ],
                if (_isClosed) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Reopen session'),
                    onPressed: _busy ? null : _reopenSession,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This session is closed. Reopen to edit and recredit inventory.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ],
            ),
        ),
    );
  }
}

class _LineRow extends StatefulWidget {
  final String lineId;
  final CartLine line;
  final bool isClosed;
  final void Function(CartLine) onChanged;
  final VoidCallback onRemove;
  final void Function(String lineId, bool isOverAllocated)? onOverAllocationChanged;
  const _LineRow({
    super.key,
    required this.lineId,
    required this.line,
    required this.isClosed,
    required this.onChanged,
    required this.onRemove,
    this.onOverAllocationChanged,
  });

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final TextEditingController _cInit;
  late final TextEditingController _cEnd;
  late final FocusNode _initFocus;
  late final FocusNode _endFocus;
  String? _lotCode;
  num? _lotRemaining;
  bool _overAllocated = false;
  bool? _lastReportedOverAllocation;

  void _notifyOverAllocation() {
    final cb = widget.onOverAllocationChanged;
    if (cb != null && _lastReportedOverAllocation != _overAllocated) {
      _lastReportedOverAllocation = _overAllocated;
      cb(widget.lineId, _overAllocated);
    }
  }

  @override
  void initState() {
    super.initState();
    _cInit = TextEditingController(text: widget.line.initialQty.toString());
    _cEnd = TextEditingController(text: widget.line.endQty?.toString() ?? '');
    _initFocus = FocusNode();
    _endFocus = FocusNode();
    _initFocus.addListener(() {
      if (!_initFocus.hasFocus) {
        _commitInitialQty();
      }
    });
    _endFocus.addListener(() {
      if (!_endFocus.hasFocus) {
        _commitEndQty();
      }
    });
    _loadLotCode();
    _lastReportedOverAllocation = _overAllocated;
  }

  Future<void> _loadLotCode() async {
    final lotId = widget.line.lotId;
    if (lotId == null) {
      if (_lotCode != null || _lotRemaining != null || _overAllocated) {
        setState(() {
          _lotCode = null;
          _lotRemaining = null;
          _overAllocated = false;
        });
      }
      _notifyOverAllocation();
      return;
    }

    try {
      final lotDoc = await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.line.itemId)
          .collection('lots')
          .doc(lotId)
          .get();
      if (!mounted) return;
      if (lotDoc.exists) {
        final data = lotDoc.data();
        final lotCode = data?['lotCode'] as String?;
        final qtyRemainingRaw = data?['qtyRemaining'];
        final qtyRemaining = qtyRemainingRaw is num ? qtyRemainingRaw : null;
        setState(() {
          _lotCode = lotCode ?? lotId.substring(0, 6);
          _lotRemaining = qtyRemaining;
          _overAllocated = qtyRemaining != null && widget.line.initialQty > qtyRemaining;
        });
      } else {
        setState(() {
          _lotCode = lotId.substring(0, 6);
          _lotRemaining = null;
          _overAllocated = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lotCode = lotId.substring(0, 6);
        _lotRemaining = null;
        _overAllocated = false;
      });
    }
    _notifyOverAllocation();
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
    if (widget.line.lotId != null && _lotRemaining != null) {
      final newValue = widget.line.initialQty > _lotRemaining!;
      if (_overAllocated != newValue) {
        setState(() {
          _overAllocated = newValue;
        });
      }
      _notifyOverAllocation();
    }
    if (widget.line.lotId == null && _overAllocated) {
      setState(() {
        _overAllocated = false;
      });
      _notifyOverAllocation();
    }
    if (widget.lineId != oldWidget.lineId) {
      _lastReportedOverAllocation = null;
      _notifyOverAllocation();
    }
  }

  @override
  void dispose() {
    _cInit.dispose();
    _cEnd.dispose();
    _initFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  String _formatQty(num value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    final str = value.toStringAsFixed(2);
    return str.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _commitInitialQty() {
    final raw = _cInit.text.trim();
    if (raw.isEmpty) {
      if (widget.line.initialQty != 0) {
        widget.onChanged(widget.line.copyWith(initialQty: 0));
      }
      if (_cInit.text != '0') {
        _cInit.text = '0';
        _cInit.selection = TextSelection.collapsed(offset: _cInit.text.length);
      }
      return;
    }

    final parsed = num.tryParse(raw);
    if (parsed == null) {
      _resetInitialField();
      return;
    }

    if (parsed != widget.line.initialQty) {
      widget.onChanged(widget.line.copyWith(initialQty: parsed));
    }
    final canonical = parsed.toString();
    if (_cInit.text != canonical) {
      _cInit.text = canonical;
      _cInit.selection = TextSelection.collapsed(offset: canonical.length);
    }
    if (_lotRemaining != null) {
      final newValue = parsed > _lotRemaining!;
      if (_overAllocated != newValue) {
        setState(() {
          _overAllocated = newValue;
        });
      }
    } else if (_overAllocated) {
      setState(() {
        _overAllocated = false;
      });
    }
    _notifyOverAllocation();
  }

  void _commitEndQty() {
    final raw = _cEnd.text.trim();
    if (raw.isEmpty) {
      if (widget.line.endQty != null) {
        widget.onChanged(widget.line.copyWith(endQty: null));
      }
      if (_cEnd.text.isNotEmpty) {
        _cEnd.clear();
      }
      return;
    }

    final parsed = num.tryParse(raw);
    if (parsed == null) {
      _resetEndField();
      return;
    }

    if (widget.line.endQty != parsed) {
      widget.onChanged(widget.line.copyWith(endQty: parsed));
    }
    final canonical = parsed.toString();
    if (_cEnd.text != canonical) {
      _cEnd.text = canonical;
      _cEnd.selection = TextSelection.collapsed(offset: canonical.length);
    }
  }

  void _resetInitialField() {
    _cInit.text = widget.line.initialQty.toString();
    _cInit.selection = TextSelection.collapsed(offset: _cInit.text.length);
  }

  void _resetEndField() {
    final text = widget.line.endQty?.toString() ?? '';
    _cEnd.text = text;
    _cEnd.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    final unitText = <String>['Unit: ${widget.line.baseUnit}'];
    if (widget.line.lotId != null) {
      final lotPieces = <String>[];
      lotPieces.add('lot ${_lotCode ?? 'Loading...'}');
      if (_lotRemaining != null) {
        lotPieces.add('${_formatQty(_lotRemaining!)} ${widget.line.baseUnit} available');
      }
      unitText.add(lotPieces.join(' • '));
    }

    return Card(
      child: ListTile(
        title: Text(widget.line.itemName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(unitText.join(' • ')),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cInit,
                    focusNode: _initFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Loaded',
                      suffixIcon: widget.isClosed ? null : IconButton(
                        icon: const Icon(Icons.calculate, size: 20),
                        tooltip: 'Calculate by weight',
                        onPressed: () async {
                          final result = await showWeightCalculator(
                            context: context,
                            itemName: widget.line.itemName,
                            initialQty: widget.line.initialQty,
                            unit: widget.line.baseUnit,
                          );
                          if (result != null) {
                            _cInit.text = result.toString();
                            _commitInitialQty();
                          }
                        },
                      ),
                    ),
                    enabled: !widget.isClosed,
                    onSubmitted: (_) => _commitInitialQty(),
                    onTapOutside: (_) => _commitInitialQty(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cEnd,
                    focusNode: _endFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Leftover (at close)',
                      suffixIcon: widget.isClosed ? null : IconButton(
                        icon: const Icon(Icons.calculate, size: 20),
                        tooltip: 'Calculate by weight',
                        onPressed: () async {
                          final result = await showWeightCalculator(
                            context: context,
                            itemName: widget.line.itemName,
                            initialQty: widget.line.endQty,
                            unit: widget.line.baseUnit,
                          );
                          if (result != null) {
                            _cEnd.text = result.toString();
                            _commitEndQty();
                          }
                        },
                      ),
                    ),
                    enabled: !widget.isClosed,
                    onSubmitted: (_) => _commitEndQty(),
                    onTapOutside: (_) => _commitEndQty(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Used this session: ${widget.line.usedQty} ${widget.line.baseUnit}'),
            if (_overAllocated && !widget.isClosed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Requested ${_formatQty(widget.line.initialQty)} ${widget.line.baseUnit}, ' 
                        'but only ${_formatQty(_lotRemaining ?? 0)} available in this lot.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: widget.isClosed ? null : IconButton(
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
  final Map<String, Set<String>> _selectedLotIds = {};
  final Map<String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>> _lotFutures = {};

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

            final lotsFuture = _lotFutures.putIfAbsent(item.id, () async {
              final snap = await FirebaseFirestore.instance
                  .collection('items')
                  .doc(item.id)
                  .collection('lots')
                  .get();
              final docs = snap.docs.toList()
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
              return docs;
            });

            return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: lotsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListTile(
                    title: Text(itemName),
                    subtitle: const Text('Loading lots...'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return ListTile(
                    title: Text(itemName),
                    subtitle: const Text('No lots available'),
                  );
                }

                final lots = snapshot.data!;

                final selectedLots = _selectedLotIds.putIfAbsent(item.id, () => <String>{});

                // Auto-select FEFO lot if none currently selected
                if (selectedLots.isEmpty && lots.isNotEmpty) {
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
                  selectedLots.add(withQty.id);
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
                      final isSelected = selectedLots.contains(lot.id);
                      return CheckboxListTile(
                        title: Text('$lotCode • $qtyRemaining $baseUnit'),
                        subtitle: expiresAt != null
                            ? Text('Expires: ${MaterialLocalizations.of(context).formatShortDate(expiresAt)}')
                            : null,
                        value: isSelected,
                        onChanged: qtyRemaining > 0
                            ? (checked) {
                                setState(() {
                                  if (checked == true) {
                                    selectedLots.add(lot.id);
                                  } else {
                                    selectedLots.remove(lot.id);
                                  }
                                });
                              }
                            : null,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
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
            final List<Map<String, dynamic>> itemDetails = [];

            for (final item in widget.selectedItems) {
              final data = item.data();
              final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;
              final selectedLots = _selectedLotIds[item.id] ?? <String>{};

              if (selectedLots.isEmpty) {
                itemDetails.add({
                  'itemId': item.id,
                  'itemName': (data['name'] ?? 'Unnamed') as String,
                  'baseUnit': baseUnit,
                  'lotId': null,
                  'autoAssignLot': false,
                });
                continue;
              }

              for (final lotId in selectedLots) {
                itemDetails.add({
                  'itemId': item.id,
                  'itemName': (data['name'] ?? 'Unnamed') as String,
                  'baseUnit': baseUnit,
                  'lotId': lotId,
                  'autoAssignLot': false,
                });
              }
            }

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

  Map<String, dynamic> _payloadForItem(
    QueryDocumentSnapshot<Map<String, dynamic>> item, {
    String? lotId,
    bool autoAssignLot = false,
  }) {
    final data = item.data();
    final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;

    return {
      'itemId': item.id,
      'itemName': (data['name'] ?? 'Unnamed') as String,
      'baseUnit': baseUnit,
      'lotId': lotId,
      'autoAssignLot': autoAssignLot,
    };
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

  void _autoAddSelectedItems() {
    if (_selectedItemIds.isEmpty || !mounted) return;
    final selectedItems = widget.items.where((item) => _selectedItemIds.contains(item.id)).toList();
    final payload = selectedItems.map((item) => _payloadForItem(item, autoAssignLot: true)).toList();
    Navigator.of(context).pop(payload);
  }

  void _autoAddSingleItem(QueryDocumentSnapshot<Map<String, dynamic>> item) {
    if (!mounted) return;
    Navigator.of(context).pop([_payloadForItem(item, autoAssignLot: true)]);
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
                trailing: IconButton(
                  tooltip: 'Quick add (auto lot)',
                  icon: const Icon(Icons.flash_auto),
                  onPressed: () => _autoAddSingleItem(d),
                ),
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
              OutlinedButton.icon(
                onPressed: _selectedItemIds.isNotEmpty ? _autoAddSelectedItems : null,
                icon: const Icon(Icons.flash_auto),
                label: const Text('Quick add'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _selectedItemIds.isNotEmpty ? _addSelectedItems : null,
                icon: const Icon(Icons.add),
                label: const Text('Add & pick lots'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickItemSearchSheet extends StatefulWidget {
  final String? initialQuery;

  const _QuickItemSearchSheet({this.initialQuery});

  @override
  State<_QuickItemSearchSheet> createState() => _QuickItemSearchSheetState();
}

class _QuickItemSearchSheetState extends State<_QuickItemSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _results = [];

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery ?? '';
    _controller.addListener(_onQueryChanged);
    _performSearch(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _performSearch(_controller.text);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _fetchResults(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchResults(String query) async {
    final coll = FirebaseFirestore.instance.collection('items');
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      final snap = await coll.orderBy('updatedAt', descending: true).limit(50).get();
      return snap.docs;
    }

    final normalized = trimmed.toLowerCase();

    try {
      final snap = await coll
          .orderBy('nameLower')
          .startAt([normalized])
          .endAt(['$normalized\uf8ff'])
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs;
      }
    } catch (_) {
      // Fallback to other strategies
    }

    try {
      final snap = await coll
          .orderBy('name')
          .startAt([trimmed])
          .endAt(['$trimmed\uf8ff'])
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs;
      }
    } catch (_) {
      // Continue to fallback
    }

    final fallback = await coll.orderBy('updatedAt', descending: true).limit(120).get();
    return fallback.docs.where((doc) {
      final data = doc.data();
      final name = (data['name'] ?? '') as String;
      final barcode = (data['barcode'] ?? '') as String;
      final altNames = (data['alternateNames'] as List?)?.map((e) => e.toString()) ?? const Iterable<String>.empty();
      final terms = <String>[name, barcode, ...altNames];
      return terms.any((term) => term.toLowerCase().contains(normalized));
    }).take(50).toList();
  }

  Map<String, dynamic> _payloadForItem(
    QueryDocumentSnapshot<Map<String, dynamic>> item, {
    String? lotId,
    bool autoAssignLot = false,
  }) {
    final data = item.data();
    final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;
    return {
      'itemId': item.id,
      'itemName': (data['name'] ?? 'Unnamed') as String,
      'baseUnit': baseUnit,
      'lotId': lotId,
      'autoAssignLot': autoAssignLot,
    };
  }

  void _quickAdd(QueryDocumentSnapshot<Map<String, dynamic>> item) {
    if (!mounted) return;
    Navigator.of(context).pop([
      _payloadForItem(item, autoAssignLot: true),
    ]);
  }

  Future<void> _pickLot(QueryDocumentSnapshot<Map<String, dynamic>> item) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => LotSelectionDialog(selectedItems: [item]),
    );
    if (!mounted || result == null || result.isEmpty) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search items by name or barcode',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: _performSearch,
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Search error: $_error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (_loading)
                const LinearProgressIndicator(minHeight: 2),
              if (!_loading)
                const SizedBox(height: 2),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _loading ? 'Searching…' : 'No items found',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final data = item.data();
                          final name = (data['name'] ?? 'Unnamed') as String;
                          final baseUnit = (data['baseUnit'] ?? data['unit'] ?? 'each') as String;
                          final qtyRaw = data['qtyOnHand'];
                          final barcode = (data['barcode'] ?? '') as String;
                          final onHand = () {
                            if (qtyRaw is num) {
                              return qtyRaw % 1 == 0 ? qtyRaw.toInt().toString() : qtyRaw.toString();
                            }
                            return '0';
                          }();
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(
                              barcode.isNotEmpty
                                  ? 'On hand: $onHand $baseUnit • Barcode: $barcode'
                                  : 'On hand: $onHand $baseUnit',
                            ),
                            onTap: () => _quickAdd(item),
                            trailing: Wrap(
                              spacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Quick add (auto lot)',
                                  icon: const Icon(Icons.flash_auto),
                                  onPressed: () => _quickAdd(item),
                                ),
                                IconButton(
                                  tooltip: 'Pick lot',
                                  icon: const Icon(Icons.tune),
                                  onPressed: () => _pickLot(item),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
