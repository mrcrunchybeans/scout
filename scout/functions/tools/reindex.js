/* One-shot reindex script.
   Usage: node tools/reindex.js
   It reads ALGOLIA_* env vars or falls back to firebase functions:config values.
   This script must be run from the `functions` folder. It uses Application Default Credentials
   to read Firestore and uses the Algolia admin key to write to the index.
*/

const admin = require('firebase-admin');
const algoliasearch = require('algoliasearch');
const {execSync} = require('child_process');

async function main() {
  admin.initializeApp();
  const db = admin.firestore();

  // Try env first
  const appId = process.env.ALGOLIA_APP_ID || process.env.ALGOLIA_APP_ID_ALT || null;
  const adminKey = process.env.ALGOLIA_ADMIN_API_KEY || process.env.ALGOLIA_ADMIN_KEY || null;
  const indexName = process.env.ALGOLIA_INDEX_NAME || process.env.ALGOLIA_INDEX || null;

  // If not present, read firebase functions config
  if (!appId || !adminKey || !indexName) {
    try {
      const out = execSync('firebase functions:config:get --format=json', {encoding:'utf8'});
      const cfg = JSON.parse(out);
      const a = cfg?.algolia?.app_id;
      const k = cfg?.algolia?.admin_key || cfg?.algolia?.write_key;
      const i = cfg?.algolia?.index_name;
      if (!appId) appId = a;
      if (!adminKey) adminKey = k;
      if (!indexName) indexName = i;
    } catch (e) {
      console.error('Failed to read functions config:', e.message || e);
    }
  }

  if (!appId || !adminKey || !indexName) {
    console.error('Missing Algolia config. Set ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY, and ALGOLIA_INDEX_NAME in env or firebase functions config.');
    process.exit(2);
  }

  console.log('Using Algolia', appId, indexName.substring(0,6)+'...');
  const client = algoliasearch(appId, adminKey);
  const index = client.initIndex(indexName);

  const BATCH = 1000;
  let last = null;
  let total = 0;

  while (true) {
    let q = db.collection('items').orderBy('__name__').limit(BATCH);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    const objects = snap.docs.map(d => {
      const data = d.data() || {};
      const serializable = {};
      for (const [k, v] of Object.entries(data)) {
        if (v && typeof v.toDate === 'function') {
          serializable[k] = v.toDate().toISOString();
        } else {
          serializable[k] = v;
        }
      }
      return {
        objectID: d.id,
        ...serializable,
        name: serializable['name'] || '',
        barcode: serializable['barcode'] || '',
        category: serializable['category'] || '',
        baseUnit: serializable['baseUnit'] || '',
        qtyOnHand: serializable['qtyOnHand'] || 0,
        minQty: serializable['minQty'] || 0,
        archived: serializable['archived'] || false,
        lots: serializable['lots'] || [],
      };
    });

    console.log('Saving', objects.length, 'objects to Algolia');
    await index.saveObjects(objects);
    total += objects.length;
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < BATCH) break;
  }

  // write status
  await db.collection('status').doc('algolia').set({
    lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    lastIndexedCount: total,
    lastError: null,
  }, {merge: true});

  console.log('Reindex complete. Total:', total);
}

main().catch(e => { console.error('Reindex failed:', e); process.exit(1); });
