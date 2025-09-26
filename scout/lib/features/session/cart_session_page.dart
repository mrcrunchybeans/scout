import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:scout/utils/audit.dart';
import 'package:scout/widgets/scanner_sheet.dart';


import '../../models/option_item.dart';
import '../../utils/sound_feedback.dart';
import '../../widgets/usb_wedge_scanner.dart';
import 'cart_models.dart';
import '../../utils/operator_store.dart';
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
        final withQty = list.firstWhere(
          (x) {
            final q = x.data()['qtyRemaining'];
            return (q is num) && q > 0;
          },
          orElse: () => list.first,
        );
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
                  await d.reference.set(
                    Audit.updateOnly({
                      'barcodes': FieldValue.arrayUnion([code]),
                      if (!hasSingle) 'barcode': code,
                    }),
                    SetOptions(merge: true),
                  );
                  await Audit.log('item.barcode.attach', {
                    'itemId': d.id,
                    'barcode': code,
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
      final payload = isNew ? Audit.attach({
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
        'startedAt': FieldValue.serverTimestamp(),
      }) : Audit.updateOnly({
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
      });

      await sref.set(payload, SetOptions(merge: true));
      _sessionId ??= sref.id;

      final batch = _db.batch();
      for (final line in _lines) {
        final lid = _lineId(line);
        final lref = sref.collection('lines').doc(lid);
        batch.set(lref, Audit.attach(line.toMap()), SetOptions(merge: true));
      }
      await batch.commit();

      await Audit.log('session.save', {
        'sessionId': _sessionId,
        'numLines': _lines.length,
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
    if (_sessionId == null) {
      await _saveDraft();
      if (!mounted) return;
      if (_sessionId == null) return;
    }
    if (_interventionId == null) {
      if (mounted) {
        SoundFeedback.error();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pick an intervention first')));
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final sref = _db.collection('cart_sessions').doc(_sessionId);

      num totalQtyUsed = 0;
      for (final line in _lines) {
        final used = line.usedQty;
        if (used <= 0) continue;
        totalQtyUsed += used;

        final itemRef = _db.collection('items').doc(line.itemId);
        final usedAtTs = FieldValue.serverTimestamp();

        if (line.lotId != null) {
          final lotRef = itemRef.collection('lots').doc(line.lotId);
          await _db.runTransaction((tx) async {
            final lotSnap = await tx.get(lotRef);
            if (!lotSnap.exists) {
              throw Exception('Lot ${line.lotId} no longer exists');
            }
            final m = lotSnap.data() as Map<String, dynamic>;
            final rem = (m['qtyRemaining'] ?? 0) as num;

            // Assert sufficient stock before decrement
            if (rem < used) {
              throw Exception('Stock changed, please refresh. Lot ${line.lotId} has insufficient stock.');
            }

            final newRem = (rem - used).clamp(0, double.infinity).toInt();

            final patch = <String, dynamic>{
              'qtyRemaining': newRem,
            };
            if (m['openAt'] == null) patch['openAt'] = FieldValue.serverTimestamp();
            tx.set(lotRef, Audit.updateOnly(patch), SetOptions(merge: true));

            // Also update item qtyOnHand
            final itemSnap = await tx.get(itemRef);
            if (itemSnap.exists) {
              final itemData = itemSnap.data() as Map<String, dynamic>;
              final currentItemQty = (itemData['qtyOnHand'] ?? 0) as num;
              final newItemQty = (currentItemQty - used).clamp(0, double.infinity).toInt();

              tx.set(
                itemRef,
                Audit.updateOnly({
                  'qtyOnHand': newItemQty,
                  'lastUsedAt': usedAtTs,
                }),
                SetOptions(merge: true),
              );
            }

            final usageRef = _db.collection('usage_logs').doc();
            tx.set(usageRef, Audit.attach({
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'lotId': line.lotId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': usedAtTs,
              'interventionId': _interventionId,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
            }));

            await Audit.log('usage.create', {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'lotId': line.lotId,
              'qtyUsed': used,
              'unit': line.baseUnit,
            });
          });
        } else {
          await _db.runTransaction((tx) async {
            final itemSnap = await tx.get(itemRef);
            if (!itemSnap.exists) {
              throw Exception('Item ${line.itemName} no longer exists');
            }
            final data = itemSnap.data() as Map<String, dynamic>;
            final currentQty = (data['qtyOnHand'] ?? 0) as num;

            // Assert sufficient stock before decrement
            if (currentQty < used) {
              throw Exception('Stock changed, please refresh. Insufficient stock for ${line.itemName}.');
            }

            final newQty = (currentQty - used).clamp(0, double.infinity).toInt();

            tx.set(itemRef, Audit.updateOnly({
              'qtyOnHand': newQty,
              'lastUsedAt': usedAtTs,
            }), SetOptions(merge: true));

            final usageRef = _db.collection('usage_logs').doc();
            tx.set(usageRef, Audit.attach({
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': usedAtTs,
              'interventionId': _interventionId,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
            }));

            await Audit.log('usage.create', {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'qtyUsed': used,
              'unit': line.baseUnit,
            });
          });
        }
      }

      await sref.set(
        Audit.updateOnly({
          'status': 'closed',
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': FirebaseAuth.instance.currentUser?.uid,
          'operatorName': OperatorStore.name.value,
        }),
        SetOptions(merge: true),
      );

      // High-level audit for the close
      await Audit.log('session.close', {
        'sessionId': _sessionId,
        'interventionId': _interventionId,
        'numLines': _lines.length,
        'totalQtyUsed': totalQtyUsed,
      });

      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.ok();
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Session closed')));
      Navigator.of(ctx).pop(true);
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      SoundFeedback.error();

      // Handle stock-related errors with user-friendly messages
      String errorMessage = 'Error: $e';
      if (e.toString().contains('Stock changed, please refresh')) {
        errorMessage = 'Stock changed, please refresh and try again.';
      } else if (e.toString().contains('no longer exists')) {
        errorMessage = 'Some items are no longer available. Please refresh and try again.';
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Add items to cart', style: Theme.of(sheetCtx).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final d in itemsSnap.docs)
              ListTile(
                title: Text((d.data()['name'] ?? 'Unnamed') as String),
                subtitle: Text('On hand: ${(d.data()['qtyOnHand'] ?? 0)}'),
                onTap: () async {
                  final lots = await _db.collection('items').doc(d.id).collection('lots').get();
                  final baseUnit = (d.data()['baseUnit'] ?? d.data()['unit'] ?? 'each') as String;

                  String? lotId;
                  if (lots.docs.isNotEmpty) {
                    final list = lots.docs.toList()
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
                    final withQty = list.firstWhere(
                      (x) {
                        final q = x.data()['qtyRemaining'];
                        return (q is num) && q > 0;
                      },
                      orElse: () => list.first,
                    );
                    lotId = withQty.id;
                  }

                  final line = CartLine(
                    itemId: d.id,
                    itemName: (d.data()['name'] ?? 'Unnamed') as String,
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
                    }
                  });

                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                },
              ),
          ],
        );
      },
    );
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
            if (ea == null) return 1;
            if (eb == null) return -1;
            return ea.compareTo(eb);
          });
        final withQty = list.firstWhere(
          (x) {
            final q = x.data()['qtyRemaining'];
            return (q is num) && q > 0;
          },
          orElse: () => list.first,
        );
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

    return Scaffold(
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

  @override
  void initState() {
    super.initState();
    _cInit = TextEditingController(text: widget.line.initialQty.toString());
    _cEnd = TextEditingController(text: widget.line.endQty?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_LineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the line data actually changed, not on every rebuild
    if (oldWidget.line.initialQty != widget.line.initialQty) {
      _cInit.text = widget.line.initialQty.toString();
    }
    if (oldWidget.line.endQty != widget.line.endQty) {
      _cEnd.text = widget.line.endQty?.toString() ?? '';
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
                '${widget.line.lotId != null ? ' • lot ${widget.line.lotId!.substring(0, 6)}…' : ''}'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cInit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Loaded'),
                    onChanged: (s) => widget.onChanged(CartLine(
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
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Leftover (at close)'),
                    onChanged: (s) => widget.onChanged(CartLine(
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
