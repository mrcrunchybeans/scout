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





class CartSessionPage extends StatefulWidget {
  final String? sessionId;
  const CartSessionPage({super.key, this.sessionId});

  @override
  State<CartSessionPage> createState() => _CartSessionPageState();
}


class _CartSessionPageState extends State<CartSessionPage> {
  final _db = FirebaseFirestore.instance;
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
  }

  String? get _grantName =>
      _defaultGrantId == null ? null : _grantNames[_defaultGrantId!] ?? _defaultGrantId;

  // ---------- Unified code handler (USB / camera / manual) ----------
  void _refocusQuickAdd() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_barcodeFocus);
    _barcodeC.selection = TextSelection(baseOffset: 0, extentOffset: _barcodeC.text.length);
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
        // unknown barcode -> offer attach
        SoundFeedback.error();
        if (!ctx.mounted) return;
        await _offerAttachBarcode(code);
        _refocusQuickAdd();
        return;
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
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
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

    if (!mounted) return;

    // “Create new item” chosen
    if (ok == false) {
      // push NewItemPage with initial barcode (assumes you have it imported in your routes)
      // If you keep NewItemPage elsewhere, adjust import.
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushNamed(
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
      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
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

      final payload = Audit.updateOnly({
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
        'startedAt': FieldValue.serverTimestamp(),
      });

      await sref.set(payload, SetOptions(merge: true));
      _sessionId ??= sref.id;

      final batch = _db.batch();
      for (final line in _lines) {
        final lid = _lineId(line);
        final lref = sref.collection('lines').doc(lid);
        batch.set(lref, line.toMap(), SetOptions(merge: true));
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

      for (final line in _lines) {
        final used = line.usedQty;
        if (used <= 0) continue;

        final itemRef = _db.collection('items').doc(line.itemId);
        final usedAtTs = FieldValue.serverTimestamp();

        if (line.lotId != null) {
          final lotRef = itemRef.collection('lots').doc(line.lotId);
          await _db.runTransaction((tx) async {
            final lotSnap = await tx.get(lotRef);
            if (!lotSnap.exists) return;
            final m = lotSnap.data() as Map<String, dynamic>;
            final rem = (m['qtyRemaining'] ?? 0) as num;
            final newRem = rem - used;
            if (newRem < 0) {
              throw Exception('Lot ${line.lotId} has only $rem remaining');
            }

            final patch = <String, dynamic>{
              'qtyRemaining': newRem,
            };
            if (m['openAt'] == null) patch['openAt'] = FieldValue.serverTimestamp();
            tx.set(lotRef, Audit.updateOnly(patch), SetOptions(merge: true));

            tx.set(
              itemRef,
              Audit.updateOnly({
                'lastUsedAt': usedAtTs,
              }),
              SetOptions(merge: true),
            );

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
            if (!itemSnap.exists) return;
            final data = itemSnap.data() as Map<String, dynamic>;
            final currentQty = (data['qtyOnHand'] ?? 0) as num;
            final newQty = currentQty - used;
            if (newQty < 0) throw Exception('Insufficient stock for ${line.itemName}');

            tx.update(itemRef, Audit.updateOnly({
              'qtyOnHand': newQty,
              'lastUsedAt': usedAtTs,
            }));

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
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
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
          _lines.add(CartLine(
            itemId: prev.itemId,
            itemName: prev.itemName,
            baseUnit: prev.baseUnit,
            lotId: prev.lotId,
            initialQty: leftover,
          ));
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      label: const Text('Copy from last'),
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

class _LineRow extends StatelessWidget {
  final CartLine line;
  final void Function(CartLine) onChanged;
  final VoidCallback onRemove;
  const _LineRow({required this.line, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cInit = TextEditingController(text: line.initialQty.toString());
    final cEnd = TextEditingController(text: line.endQty?.toString() ?? '');

    return Card(
      child: ListTile(
        title: Text(line.itemName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unit: ${line.baseUnit}'
                '${line.lotId != null ? ' • lot ${line.lotId!.substring(0, 6)}…' : ''}'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cInit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Loaded'),
                    onChanged: (s) => onChanged(CartLine(
                      itemId: line.itemId,
                      itemName: line.itemName,
                      baseUnit: line.baseUnit,
                      lotId: line.lotId,
                      initialQty: num.tryParse(s) ?? line.initialQty,
                      endQty: line.endQty,
                    )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: cEnd,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Leftover (at close)'),
                    onChanged: (s) => onChanged(CartLine(
                      itemId: line.itemId,
                      itemName: line.itemName,
                      baseUnit: line.baseUnit,
                      lotId: line.lotId,
                      initialQty: line.initialQty,
                      endQty: s.trim().isEmpty ? null : num.tryParse(s),
                    )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Used this session: ${line.usedQty} ${line.baseUnit}'),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
      ),
    );
  }
}
