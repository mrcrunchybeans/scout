// lib/dev/seed_lookups.dart
import 'package:cloud_firestore/cloud_firestore.dart';

final _db = FirebaseFirestore.instance;

// ---- Data ----
const _departments = [
  {'name': 'Spiritual Care',              'code': 'SC',    'active': true},
  {'name': 'Cancer Center',               'code': 'CC',    'active': true},
  {'name': 'ICU',                         'code': 'ICU',   'active': true},
  {'name': 'Inpatient Behavioral Health', 'code': 'IBH',   'active': true},
  {'name': 'General Medicine',            'code': 'GM',    'active': true},
  {'name': 'Pediatrics',                  'code': 'PEDS',  'active': true},
  {'name': 'OB / Postpartum',             'code': 'OB',    'active': true},
];

const _grants = [
  {'name': 'Cancer Center',                         'code': 'CC',    'active': true},
  {'name': 'Bounce Back',                           'code': 'BB',    'active': true},
  {'name': 'Grief Group Supplies/Refreshments',     'code': 'GGS',   'active': true},
  {'name': 'Tea for the Soul',                      'code': 'TFS',   'active': true},
  {'name': 'Code Lavender',                         'code': 'CL',    'active': true},
  {'name': 'General Spiritual Care',                'code': 'GSC',   'active': true},
  {'name': 'Other',                                 'code': 'OTHER', 'active': true},
];

const _locations = [
  {'name': 'Storage Closet - HC1303C',      'code': 'HC1303C', 'kind': 'storage', 'active': true},
  {'name': 'Sacristy - HC1330A',            'code': 'HC1330A', 'kind': 'storage', 'active': true},
  {'name': 'Sleep Room - HC2346',           'code': 'HC2346',  'kind': 'storage', 'active': true},
  {'name': 'CEC Office - HC1303A',          'code': 'HC1303A', 'kind': 'storage', 'active': true},
  {'name': 'Spiritual Care Office - HC1304', 'code': 'HC1304', 'kind': 'storage', 'active': true},
  {'name': 'Pediatrics Unit',               'code': 'PEDS-U',  'kind': 'unit',    'active': true},
  {'name': 'Tea for the Soul Cart',         'code': 'TFS-CART','kind': 'mobile',  'active': true},
];

// NOTE: defaultGrantId maps to the grant *code* above.
const _interventions = [
  {'name': 'Tea for the Soul',        'code': 'TFS',   'defaultGrantId': 'TFS',  'active': true},
  {'name': 'Bounce Back',             'code': 'BB',    'defaultGrantId': 'BB',   'active': true},
  {'name': 'Grief Group (supplies)',  'code': 'GGS',   'defaultGrantId': 'GGS',  'active': true},
  {'name': 'Bereavement Care',        'code': 'BC',    'defaultGrantId': 'GSC',  'active': true}, // best-fit
  {'name': 'Code Lavender',           'code': 'CL',    'defaultGrantId': 'CL',   'active': true},
  {'name': 'Other',                   'code': 'OTHER', 'defaultGrantId': 'OTHER','active': true},
];

// ---- Public helpers ----

/// Original behavior: only inserts when a collection is empty.
Future<void> seedLookups() async {
  Future<void> addIfEmpty(String col, List<Map<String, dynamic>> docs) async {
    final snap = await _db.collection(col).limit(1).get();
    if (snap.docs.isEmpty) {
      final batch = _db.batch();
      for (final d in docs) {
        final ref = _db.collection(col).doc(); // auto-id (one-time seed)
        batch.set(ref, {
          ...d,
          'createdAt': FieldValue.serverTimestamp(),
          'active': d['active'] ?? true,
        });
      }
      await batch.commit();
    }
  }

  await addIfEmpty('departments', _departments);
  await addIfEmpty('grants', _grants);
  await addIfEmpty('locations', _locations);
  await addIfEmpty('interventions', _interventions);
}

/// Reseed by *upserting* with deterministic IDs = `code`.
Future<void> reseedLookupsMerge() async {
  Future<void> upsert(String col, List<Map<String, dynamic>> docs) async {
    final batch = _db.batch();
    for (final d in docs) {
      final code = d['code'] as String;
      final ref = _db.collection(col).doc(code); // deterministic ID
      batch.set(
        ref,
        {
          ...d,
          'updatedAt': FieldValue.serverTimestamp(),
          'active': d['active'] ?? true,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  await upsert('departments', _departments);
  await upsert('grants', _grants);
  await upsert('locations', _locations);
  await upsert('interventions', _interventions); // includes defaultGrantId
}

/// Destructive reset then reseed (deterministic IDs).
Future<void> resetAndSeedLookups() async {
  Future<void> wipe(String col) async {
    while (true) {
      final snap = await _db.collection(col).limit(300).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  await wipe('departments');
  await wipe('grants');
  await wipe('locations');
  await wipe('interventions'); // <--- was missing

  await reseedLookupsMerge();
}
