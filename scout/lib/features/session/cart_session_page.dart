import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:scout/widgets/scanner_sheet.dart';

import '../../data/lookups_service.dart';
import '../../models/option_item.dart';
import 'cart_models.dart';
import '../items/new_item_page.dart';

class CartSessionPage extends StatefulWidget {
  final String? sessionId; // null = new
  const CartSessionPage({super.key, this.sessionId});

  @override
  State<CartSessionPage> createState() => _CartSessionPageState();
}

class _CartSessionPageState extends State<CartSessionPage> {
  final _db = FirebaseFirestore.instance;
  final _lookups = LookupsService();

  bool _busy = false;
  String? _sessionId;
  String? _interventionId;
  String? _interventionName;
  String? _defaultGrantId; // derived
  String _locationText = '';
  String _notes = '';
  String _status = 'open'; // open | closed

  List<OptionItem>? _interventions;
  OptionItem? _selectedIntervention; // selected object for dropdown

  final Map<String, String?> _intToGrant = {};
  final Map<String, String> _grantNames = {};

  final List<CartLine> _lines = []; // in-memory working set

  // Barcode controller for quick add
  final _barcodeC = TextEditingController();

  // ---------- helpers ----------
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? get _grantName =>
      _defaultGrantId == null ? null : _grantNames[_defaultGrantId!] ?? _defaultGrantId;

  String _lineId(CartLine l) => l.lotId == null ? l.itemId : '${l.itemId}__${l.lotId}';

  OptionItem? _findInterventionById(String? id) {
    if (id == null || _interventions == null) return null;
    for (final o in _interventions!) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<String?> _pickFefoLotId(String itemId) async {
    final lots = await _db.collection('items').doc(itemId).collection('lots').get();
    if (lots.docs.isEmpty) return null;
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

    // prefer a lot with qtyRemaining > 0, else first
    final withQty = list.firstWhere(
      (x) => (x.data()['qtyRemaining'] ?? 0) is num
          ? ((x.data()['qtyRemaining'] as num) > 0)
          : false,
      orElse: () => list.first,
    );
    return withQty.id;
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _barcodeC.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() => _busy = true);
    try {
      // load interventions + default grants
      final interventions = await _lookups.interventions();
      final intSnap =
          await _db.collection('interventions').where('active', isEqualTo: true).get();
      final grantSnap = await _db.collection('grants').where('active', isEqualTo: true).get();

      for (final d in intSnap.docs) {
        _intToGrant[d.id] = d.data()['defaultGrantId'] as String?;
      }
      for (final d in grantSnap.docs) {
        _grantNames[d.id] = (d.data()['name'] ?? '') as String;
      }

      _interventions = interventions;

      // existing session?
      if (widget.sessionId != null) {
        _sessionId = widget.sessionId!;
        final sref = _db.collection('cart_sessions').doc(_sessionId);
        final ss = await sref.get();
        if (ss.exists) {
          final m = ss.data()!;
          _interventionId = m['interventionId'] as String?;
          _interventionName = m['interventionName'] as String?;
          _defaultGrantId = m['grantId'] as String?;
          _locationText = (m['locationText'] ?? '') as String;
          _notes = (m['notes'] ?? '') as String;
          _status = (m['status'] ?? 'open') as String;

          final linesSnap = await sref.collection('lines').orderBy('itemName').get();
          for (final d in linesSnap.docs) {
            _lines.add(CartLine.fromMap(d.data()));
          }
        }
      }

      // reflect the selected intervention in the dropdown
      _selectedIntervention = _findInterventionById(_interventionId);
      _defaultGrantId ??= _interventionId == null ? null : _intToGrant[_interventionId!];
    } catch (e) {
      _showSnack('Error loading: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Scan / add ----------
  Future<void> _scanAndAdd() async {
    final pageCtx = context;
    final code = await showModalBottomSheet<String>(
      context: pageCtx,
      isScrollControlled: true,
      builder: (_) => const ScannerSheet(title: 'Scan item barcode or lot QR'),
    );
    if (code == null || !pageCtx.mounted) return;

    try {
      // SCOUT lot QR: SCOUT:LOT:item={ITEM_ID};lot={LOT_ID}
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
          if (!itemSnap.exists) {
            _showSnack('Item not found');
            return;
          }
          final m = itemSnap.data()!;
          final name = (m['name'] ?? 'Unnamed') as String;
          final baseUnit = (m['baseUnit'] ?? 'each') as String;

          _addOrBumpLine(
            itemId: itemId,
            itemName: name,
            baseUnit: baseUnit,
            lotId: lotId,
          );
          if (!pageCtx.mounted) return;
          _showSnack('Added: $name');
          return;
        }
      }

      // Otherwise: barcode lookup (single or array)
      QueryDocumentSnapshot<Map<String, dynamic>>? d;
      var bySingle =
          await _db.collection('items').where('barcode', isEqualTo: code).limit(1).get();
      if (bySingle.docs.isNotEmpty) {
        d = bySingle.docs.first;
      } else {
        final byArray = await _db
            .collection('items')
            .where('barcodes', arrayContains: code)
            .limit(1)
            .get();
        if (byArray.docs.isNotEmpty) d = byArray.docs.first;
      }

      if (d == null) {
        if (!pageCtx.mounted) return;
        await _offerAttachBarcode(code);
        return;
      }

      final name = (d.data()['name'] ?? 'Unnamed') as String;
      final baseUnit = (d.data()['baseUnit'] ?? 'each') as String;

      final lotId = await _pickFefoLotId(d.id);

      _addOrBumpLine(itemId: d.id, itemName: name, baseUnit: baseUnit, lotId: lotId);
      if (!pageCtx.mounted) return;
      _showSnack('Added: $name');
    } catch (e) {
      if (!pageCtx.mounted) return;
      _showSnack('Scan error: $e');
    }
  }

  Future<void> _addByBarcode() async {
    final pageCtx = context;
    final raw = _barcodeC.text;
    final code = raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();
    if (code.isEmpty) return;

    setState(() => _busy = true);
    try {
      QueryDocumentSnapshot<Map<String, dynamic>>? d;
      var q = await _db.collection('items').where('barcode', isEqualTo: code).limit(1).get();
      if (q.docs.isNotEmpty) {
        d = q.docs.first;
      } else {
        q = await _db.collection('items').where('barcodes', arrayContains: code).limit(1).get();
        if (q.docs.isNotEmpty) d = q.docs.first;
      }

      if (d == null) {
        if (!pageCtx.mounted) return;
        _showSnack('No item found for barcode $code');
        return;
      }

      final baseUnit = (d.data()['baseUnit'] ?? 'each') as String;
      final name = (d.data()['name'] ?? 'Unnamed') as String;
      final lotId = await _pickFefoLotId(d.id);

      _addOrBumpLine(itemId: d.id, itemName: name, baseUnit: baseUnit, lotId: lotId);

      if (!pageCtx.mounted) return;
      _barcodeC.clear();
      _showSnack('Added: $name');
    } catch (e) {
      if (pageCtx.mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text('Unknown barcode', style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('No item found with code: $code. Attach it to an existing item or create a new one.'),
              const SizedBox(height: 16),

              // Create new item
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Create new item'),
                subtitle: const Text('Start a new item with this barcode'),
                onTap: () => Navigator.pop(sheetCtx, 'create'),
              ),
              const Divider(height: 16),

              // Existing items (recent)
              FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _db.collection('items')
                    .orderBy('updatedAt', descending: true)
                    .limit(50)
                    .get(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const ListTile(
                      title: Text('No items yet'),
                      subtitle: Text('Use “Create new item” above'),
                    );
                  }
                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Or attach to an existing item:'),
                        ),
                      ),
                      for (final d in docs)
                        ListTile(
                          title: Text((d.data()['name'] ?? 'Unnamed') as String),
                          subtitle: Text('On hand: ${(d.data()['qtyOnHand'] ?? 0)}'),
                          onTap: () => Navigator.pop(sheetCtx, d.id),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    // User chose “Create new item…”
    if (choice == 'create') {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => NewItemPage(initialBarcode: code),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      if (created == true) {
        // Look up the newly-created item by this barcode, then add to session
        final snapSingle = await _db.collection('items').where('barcode', isEqualTo: code).limit(1).get();
        QueryDocumentSnapshot<Map<String, dynamic>>? d;
        if (snapSingle.docs.isNotEmpty) {
          d = snapSingle.docs.first;
        } else {
          final snapArray = await _db.collection('items').where('barcodes', arrayContains: code).limit(1).get();
          if (snapArray.docs.isNotEmpty) d = snapArray.docs.first;
        }

        if (d != null) {
          final name = (d.data()['name'] ?? 'Unnamed') as String;
          final baseUnit = (d.data()['baseUnit'] ?? 'each') as String;

          // FEFO lot if present
          String? lotId;
          final lots = await _db.collection('items').doc(d.id).collection('lots').get();
          if (lots.docs.isNotEmpty) {
            final list = lots.docs.toList()..sort((a,b){
              final ta = a.data()['expiresAt']; final tb = b.data()['expiresAt'];
              final ea = (ta is Timestamp) ? ta.toDate() : null;
              final eb = (tb is Timestamp) ? tb.toDate() : null;
              if (ea == null && eb == null) return 0;
              if (ea == null) return 1;
              if (eb == null) return -1;
              return ea.compareTo(eb);
            });
            final withQty = list.firstWhere(
              (x) => (x.data()['qtyRemaining'] ?? 0) is num
                  ? ((x.data()['qtyRemaining'] as num) > 0) : false,
              orElse: () => list.first,
            );
            lotId = withQty.id;
          }

          _addOrBumpLine(itemId: d.id, itemName: name, baseUnit: baseUnit, lotId: lotId);
          _showSnack('Created & added: $name');        }
      }
      return;
    }

    // Otherwise: choice is an existing itemId — attach barcode to it
    final itemRef = _db.collection('items').doc(choice);
    await itemRef.set({
      'barcode': code, // keep single string for quick filters
      'barcodes': FieldValue.arrayUnion([code]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barcode attached')));
  }


  // ---------- Save / close ----------
  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    try {
      final sref = _sessionId == null
          ? _db.collection('cart_sessions').doc()
          : _db.collection('cart_sessions').doc(_sessionId);

      final payload = {
        'interventionId': _interventionId,
        'interventionName': _interventionName,
        'grantId': _defaultGrantId,
        'locationText': _locationText.trim().isEmpty ? null : _locationText.trim(),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'status': 'open',
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await sref.set(payload, SetOptions(merge: true));
      _sessionId ??= sref.id;

      // upsert lines (deterministic id)
      final batch = _db.batch();
      for (final line in _lines) {
        final lid = _lineId(line);
        final lref = sref.collection('lines').doc(lid);
        batch.set(lref, line.toMap(), SetOptions(merge: true));
      }
      await batch.commit();

      _showSnack('Draft saved');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    if (_sessionId == null) {
      await _saveDraft();
      if (!mounted || _sessionId == null) return;
    }
    if (_interventionId == null) {
      _showSnack('Pick an intervention first');
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
          String? txError;
          await _db.runTransaction((tx) async {
            final lotSnap = await tx.get(lotRef);
            if (!lotSnap.exists) {
              txError = 'Lot not found';
              return;
            }
            final m = lotSnap.data() as Map<String, dynamic>;
            final rem = (m['qtyRemaining'] ?? 0) as num;
            final newRem = rem - used;
            if (newRem < 0) {
              txError = 'Lot ${line.lotId} has only $rem remaining';
              return; // do not throw inside transaction on web
            }

            final patch = <String, dynamic>{
              'qtyRemaining': newRem,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            if (m['openAt'] == null) patch['openAt'] = FieldValue.serverTimestamp();
            tx.set(lotRef, patch, SetOptions(merge: true));

            tx.set(
              itemRef,
              {
                'lastUsedAt': usedAtTs,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );

            final usageRef = _db.collection('usage_logs').doc();
            tx.set(usageRef, {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'lotId': line.lotId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': usedAtTs,
              'interventionId': _interventionId,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
              'createdAt': FieldValue.serverTimestamp(),
            });
          });

          if (txError != null) {
            _showSnack(txError!);
            continue; // skip this line
          }
        } else {
          // legacy path (no lots)
          String? txError;
          await _db.runTransaction((tx) async {
            final itemSnap = await tx.get(itemRef);
            if (!itemSnap.exists) {
              txError = 'Item not found';
              return;
            }
            final data = itemSnap.data() as Map<String, dynamic>;
            final currentQty = (data['qtyOnHand'] ?? 0) as num;
            final newQty = currentQty - used;
            if (newQty < 0) {
              txError = 'Insufficient stock for ${line.itemName}';
              return; // do not throw inside transaction on web
            }

            tx.update(itemRef, {
              'qtyOnHand': newQty,
              'lastUsedAt': usedAtTs,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            final usageRef = _db.collection('usage_logs').doc();
            tx.set(usageRef, {
              'sessionId': _sessionId,
              'itemId': line.itemId,
              'qtyUsed': used,
              'unit': line.baseUnit,
              'usedAt': usedAtTs,
              'interventionId': _interventionId,
              'grantId': _defaultGrantId,
              'notes': _notes.trim().isEmpty ? null : _notes.trim(),
              'createdAt': FieldValue.serverTimestamp(),
            });
          });

          if (txError != null) {
            _showSnack(txError!);
            continue;
          }
        }
      }

      await sref.set({
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showSnack('Session closed');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI helpers ----------
  Future<void> _addItems() async {
    final pageCtx = context;
    final itemsSnap =
        await _db.collection('items').orderBy('updatedAt', descending: true).limit(50).get();
    if (!pageCtx.mounted) return;

    await showModalBottomSheet(
      context: pageCtx,
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
                  final baseUnit = (d.data()['baseUnit'] ?? 'each') as String;
                  final lotId = await _pickFefoLotId(d.id);

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
    final pageCtx = context;
    if (_interventionId == null) {
      _showSnack('Pick an intervention first');
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

      if (!pageCtx.mounted) return;

      if (last.docs.isEmpty) {
        _showSnack('No previous session found for this intervention');
        return;
      }
      final lastId = last.docs.first.id;
      final lines = await _db.collection('cart_sessions').doc(lastId).collection('lines').get();

      if (!mounted) return;
      setState(() {
        _lines.clear();
        for (final d in lines.docs) {
          final prev = CartLine.fromMap(d.data());
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
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child:
                  SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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

                // quick add by barcode
                const SizedBox(height: 16),
                Text('Quick add by barcode', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barcodeC,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'Type or paste a barcode',
                          prefixIcon: Icon(Icons.qr_code_scanner),
                        ),
                        onSubmitted: (_) {
                          if (!_busy) _addByBarcode();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _addByBarcode,
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
                    key: ValueKey('${line.itemId}_${line.lotId ?? ''}'),
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

/// Fixed: stateful row that manages controllers correctly and stays in sync.
class _LineRow extends StatefulWidget {
  final CartLine line;
  final void Function(CartLine) onChanged;
  final VoidCallback onRemove;

  const _LineRow({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

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
  void didUpdateWidget(covariant _LineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final line = widget.line;

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
                    controller: _cInit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Loaded'),
                    onChanged: (s) => widget.onChanged(CartLine(
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
                    controller: _cEnd,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Leftover (at close)'),
                    onChanged: (s) => widget.onChanged(CartLine(
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
          onPressed: widget.onRemove,
        ),
      ),
    );
  }
}
