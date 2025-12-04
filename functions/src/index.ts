import * as admin from "firebase-admin";
// Load environment variables from .env when present (for local/dev)
import "dotenv/config";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as functions from "firebase-functions";
import algoliasearch from "algoliasearch";

admin.initializeApp();
const db = admin.firestore();
// Algolia client will be created lazily from environment variables
let algoliaClient: ReturnType<typeof algoliasearch> | null = null;
function getAlgoliaClient(): ReturnType<typeof algoliasearch> {
  if (algoliaClient) return algoliaClient;
  // Prefer environment variables, fall back to firebase functions config
  // (set with `firebase functions:config:set algolia.app_id="..."`)
  // algolia.admin_key="..." algolia.index_name="..."`)
  const appId = process.env.ALGOLIA_APP_ID || (functions && (functions.config as any)?.algolia?.app_id);
  const apiKey = process.env.ALGOLIA_ADMIN_API_KEY || (functions && (functions.config as any)?.algolia?.admin_key); // server-side admin key
  if (!appId || !apiKey) throw new Error("Algolia credentials not configured (process.env or functions.config)");
  algoliaClient = algoliasearch(appId, apiKey);
  return algoliaClient;
}

function getDeveloperPassword(): string | null {
  const env = process.env.DEV_PASSWORD;
  if (env && env.length > 0) return env;
  const fallback = (functions && (functions.config as any)?.admin?.dev_password) as string | undefined;
  if (fallback && fallback.length > 0) return fallback;
  return null;
}

function assertDeveloperPassword(password: string | undefined) {
  const expected = getDeveloperPassword();
  if (!expected) {
    throw new HttpsError("failed-precondition", "Developer password is not configured on the server.");
  }
  if (!password || password !== expected) {
    throw new HttpsError("permission-denied", "Invalid developer password.");
  }
}

// ---------- Tunables ----------
const STALE_DAYS = 45; // no use for ≥ N days
const EXCESS_FACTOR = 3; // qtyOnHand ≥ N * minQty
const EXPIRING_SOON_DAYS = 14; // earliest lot expiration within N days
const WIPE_BATCH_SIZE = 400;

const COLLECTIONS_TO_WIPE: Array<{collection: string; subcollections?: string[]}> = [
  {collection: "items", subcollections: ["lots"]},
  {collection: "sessions"},
  {collection: "cartSessions"},
  {collection: "usage_logs"},
];

// ---------- Helpers ----------
type Lot = {
  qtyRemaining?: number;
  expiresAt?: admin.firestore.Timestamp | null;
  openAt?: admin.firestore.Timestamp | null;
  expiresAfterOpenDays?: number | null;
  archived?: boolean;
};

/**
 * Convert Firestore types to plain JavaScript objects for safe serialization
 * @param {any} obj - The object to convert
 * @return {any} The converted object
 */
function convertFirestoreTypes(obj: any): any {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj !== "object") {
    // Convert numbers to ensure they're regular JavaScript numbers, not int64
    if (typeof obj === "number") {
      return Number(obj);
    }
    // Handle Firestore int64 values that have toNumber() method
    if (obj && typeof obj.toNumber === "function") {
      return obj.toNumber();
    }
    return obj;
  }

  if (obj instanceof admin.firestore.Timestamp) {
    return {_type: "timestamp", _value: obj.toDate().toISOString()};
  }

  if (obj instanceof admin.firestore.GeoPoint) {
    return {
      _type: "geopoint",
      _value: {latitude: obj.latitude, longitude: obj.longitude},
    };
  }

  if (obj instanceof admin.firestore.DocumentReference) {
    return {_type: "documentReference", _value: obj.path};
  }

  if (Array.isArray(obj)) {
    return obj.map(convertFirestoreTypes);
  }

  const result: any = {};
  for (const [key, value] of Object.entries(obj)) {
    result[key] = convertFirestoreTypes(value);
  }
  return result;
}

async function deleteSubcollectionDocs(
  collectionRef: admin.firestore.CollectionReference,
  batchSize = WIPE_BATCH_SIZE
) {
  while (true) {
    const snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.empty) break;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function deleteCollectionDocs(
  collectionPath: string,
  subcollections: string[] = [],
  batchSize = WIPE_BATCH_SIZE
) {
  const collectionRef = db.collection(collectionPath);
  while (true) {
    const snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.empty) break;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      for (const sub of subcollections) {
        await deleteSubcollectionDocs(doc.ref.collection(sub), batchSize);
      }
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/**
 * Calculate effective expiration date for a lot.
 * @param {Lot} lot - The lot data to calculate expiry for
 * @return {Date | null} The effective expiration date or null
 */
function effectiveLotExpiry(lot: Lot): Date | null {
  const expiresAt = lot.expiresAt?.toDate() ?? null;
  const openAt = lot.openAt?.toDate() ?? null;
  const afterDays = lot.expiresAfterOpenDays ?? null;

  // If after-open rule applies, effective = min(expiresAt, openAt + afterDays)
  if (openAt && afterDays && afterDays > 0) {
    const afterOpen = new Date(openAt.getTime());
    afterOpen.setDate(afterOpen.getDate() + afterDays);
    if (expiresAt) return afterOpen < expiresAt ? afterOpen : expiresAt;
    return afterOpen;
  }
  return expiresAt; // if only unopened expiry, use that; else null
}

/**
 * Check if a date is expiring soon within the configured window.
 * @param {Date | null} d - The date to check
 * @param {Date} now - The current date (defaults to now)
 * @return {boolean} True if expiring soon
 */
function isExpiringSoon(d: Date | null, now = new Date()) {
  if (!d) return false;
  const days = Math.floor((d.getTime() - now.getTime()) / (24 * 3600 * 1000));
  return days >= 0 && days <= EXPIRING_SOON_DAYS;
}

/**
 * Calculate the number of days since a timestamp.
 * @param {admin.firestore.Timestamp | null | undefined} d - The timestamp
 * @param {Date} now - The current date (defaults to now)
 * @return {number} Number of days since the timestamp
 */
function daysSince(d?: admin.firestore.Timestamp | null, now = new Date()) {
  if (!d) return Infinity;
  const dd = d.toDate();
  return Math.floor((now.getTime() - dd.getTime()) / (24 * 3600 * 1000));
}

/**
 * Recompute aggregate data for an item based on its lots.
 * @param {string} itemId - The item ID to recompute aggregates for
 */
/**
 * Recompute aggregate data for an item based on its lots.
 *
 * @param {string} itemId The item ID to recompute aggregates for.
 * @return {Promise<void>} Resolves when the item aggregates have been written.
 */
async function recomputeItemAggregates(itemId: string) {
  try {
    console.error(`Recomputing aggregates for item ${itemId}`);
    const itemRef = db.collection("items").doc(itemId);
    const [itemSnap, lotsSnap] = await Promise.all([
      itemRef.get(),
      itemRef.collection("lots").get(),
    ]);

    if (!itemSnap.exists) {
      console.error(`Item ${itemId} does not exist`);
      return;
    }

    const item = itemSnap.data() || {};
    const minQty = Number(item.minQty || 0);
    const lastUsedAt = item.lastUsedAt as
      admin.firestore.Timestamp | null | undefined;

    // Sum remaining from lots & compute earliest expiry
    let qtyOnHand = Number(item.qtyOnHand || 0); // Preserve current qtyOnHand
    let earliest: Date | null = null;

    console.error(`Item ${itemId}: has ${lotsSnap.size} lots, current qtyOnHand: ${qtyOnHand}, minQty: ${minQty}`);

    // Only recalculate qtyOnHand from lots if the item actually has lots
    if (!lotsSnap.empty) {
      qtyOnHand = 0; // Reset to recalculate from lots
      lotsSnap.forEach((doc) => {
        const lot = doc.data() as Lot;

        // Skip archived lots - they shouldn't count toward qty or expiration
        if (lot.archived === true) {
          return;
        }

        const rem = Number(lot.qtyRemaining || 0);
        qtyOnHand += rem;

        // Only consider expiry from lots with remaining quantity > 0
        if (rem > 0) {
          const eff = effectiveLotExpiry(lot);
          if (eff) {
            if (!earliest || eff < earliest) earliest = eff;
          }
        }
      });
      console.error(`Item ${itemId}: recalculated qtyOnHand from lots: ${qtyOnHand}`);
    } else {
      console.error(`Item ${itemId}: preserving qtyOnHand: ${qtyOnHand}`);
    }

    // Flags
    const now = new Date();
    const flagLow = minQty > 0 && qtyOnHand <= minQty;
    const flagExcess = minQty > 0 && qtyOnHand >= EXCESS_FACTOR * minQty;
    const flagStale = daysSince(lastUsedAt, now) >= STALE_DAYS;
    const flagExpiringSoon = isExpiringSoon(earliest, now);
    const flagExpired = earliest ? (earliest as Date).getTime() < now.getTime() : false;

    console.error(`Item ${itemId}: flags - low: ${flagLow}, stale: ${flagStale}, expiringSoon: ${flagExpiringSoon}, expired: ${flagExpired}`);

    // Write back (merge)
    const patch: Record<string, any> = {
      qtyOnHand,
      flagLow,
      flagExcess,
      flagStale,
      flagExpiringSoon,
      flagExpired,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      earliestExpiresAt: earliest ?
        admin.firestore.Timestamp.fromDate(earliest) :
        null,
    };

    await itemRef.set(patch, {merge: true});
    console.error(`Item ${itemId}: updated successfully`);
  } catch (error) {
    console.error(`Error recomputing aggregates for item ${itemId}:`, error);
  }
}

// ---------- Backup Configuration ----------
const BACKUP_COLLECTIONS = ["items", "lookups", "config"];

// ---------- Backup Functions ----------

// Automated daily backup
export const dailyBackup = onSchedule("every day 03:00", async () => {
  console.log("Starting automated daily backup...");

  try {
    const backupData: Record<string, Record<string, any>> = {};
    let totalDocuments = 0;

    // Export each collection
    for (const collectionName of BACKUP_COLLECTIONS) {
      console.log(`Backing up collection: ${collectionName}`);
      const snapshot = await db.collection(collectionName).get();
      const documents: Record<string, any> = {};

      snapshot.forEach((doc) => {
        // Convert Firestore types to plain JavaScript objects
        const docData = doc.data();
        documents[doc.id] = convertFirestoreTypes(docData);
      });

      backupData[collectionName] = documents;
      totalDocuments += snapshot.size;
      console.log(`Backed up ${snapshot.size} docs from ${collectionName}`);
    }

    // Create backup document
    const backupDoc = {
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      collections: backupData,
      totalDocuments,
      createdBy: "automated-backup",
      description: `Daily backup - ${new Date().toISOString().split("T")[0]}`,
      type: "automated",
    };

    const backupRef = await db.collection("backups").add(backupDoc);
    console.log(`Backup done. ID: ${backupRef.id}, Docs: ${totalDocuments}`);

    // Clean up old backups
    await cleanupOldBackups();
  } catch (error) {
    console.error("Automated backup failed:", error);
    throw error; // Re-throw to mark function as failed
  }
});

// Clean up backups older than retention period
/**
 * Clean up backups older than the configured retention period.
 */
async function cleanupOldBackups() {
  // Get retention settings from config
  const configDoc = await db.collection("config").doc("backup").get();
  const retentionDays = configDoc.exists ?
    configDoc.data()?.retentionDays ?? 30 :
    30;

  console.log(`Cleaning up backups older than ${retentionDays} days...`);

  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - retentionDays);

  const oldBackupsQuery = db.collection("backups")
    .where("timestamp", "<", admin.firestore.Timestamp.fromDate(cutoffDate))
    .where("type", "==", "automated"); // Only clean up automated backups

  const oldBackups = await oldBackupsQuery.get();

  if (oldBackups.empty) {
    console.log("No old backups to clean up");
    return;
  }

  console.log(`Found ${oldBackups.size} old backups to delete`);

  // Delete old backups in batches
  const batch = db.batch();
  let deleteCount = 0;

  oldBackups.forEach((doc) => {
    batch.delete(doc.ref);
    deleteCount++;
  });

  await batch.commit();
  console.log(`Deleted ${deleteCount} old backups`);
}

// Manual backup trigger (callable function)
import {onCall, HttpsError} from "firebase-functions/v2/https";

export const createManualBackup = onCall(async (request) => {
  // Note: Authentication check removed - protected by admin PIN in client
  console.log("Manual backup requested");

  try {
    const backupData: Record<string, Record<string, any>> = {};
    let totalDocuments = 0;

    // Export each collection
    for (const collectionName of BACKUP_COLLECTIONS) {
      const snapshot = await db.collection(collectionName).get();
      const documents: Record<string, any> = {};

      snapshot.forEach((doc) => {
        // Convert Firestore types to plain JavaScript objects
        const docData = doc.data();
        documents[doc.id] = convertFirestoreTypes(docData);
      });

      backupData[collectionName] = documents;
      totalDocuments += snapshot.size;
    }

    // Create backup document
    const backupDoc = {
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      collections: backupData,
      totalDocuments,
      createdBy: request.auth?.uid ?? "admin",
      description: "Manual backup from admin panel",
      type: "manual",
    };

    const backupRef = await db.collection("backups").add(backupDoc);

    return {
      success: true,
      backupId: backupRef.id,
      totalDocuments: Number(totalDocuments), // Ensure it's a regular number
      message: `Backup created with ${totalDocuments} documents`,
    };
  } catch (error) {
    console.error("Manual backup failed:", error);
    throw new Error(`Backup failed: ${error}`);
  }
});

export const wipeInventoryData = onCall({
  region: "us-central1",
  timeoutSeconds: 540,
}, async (request) => {
  const password = (request.data?.password as string | undefined)?.trim();
  assertDeveloperPassword(password);

  const cleared: string[] = [];
  for (const entry of COLLECTIONS_TO_WIPE) {
    await deleteCollectionDocs(entry.collection, entry.subcollections ?? []);
    cleared.push(entry.collection);
  }

  // Reset aggregated dashboard stats to zero so UI reflects wiped state
  try {
    await db.collection("meta").doc("dashboard_stats").set({
      low: 0,
      expiring: 0,
      stale: 0,
      expired: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    console.error("Failed to reset dashboard stats after wipe:", error);
  }

  // Clear Algolia index if configured
  try {
    const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && (functions.config as any)?.algolia?.index_name);
    if (indexName) {
      await getAlgoliaClient().initIndex(indexName).clearObjects();
    } else {
      console.warn("ALGOLIA_INDEX_NAME not configured; skipping Algolia clear during wipe.");
    }
  } catch (error) {
    console.error("Failed to clear Algolia index during wipe:", error);
  }

  return {
    success: true,
    cleared,
  };
});
// NOTE: Client adjusts lots, server recomputes totals.
export const onUsageLogCreate = onDocumentCreated(
  "usage_logs/{logId}",
  async (event) => {
    const snap = event.data; // QueryDocumentSnapshot | undefined
    if (!snap) return; // safety
    const data = snap.data();

    const itemId: string | undefined = data.itemId;
    const usedAt = data.usedAt as admin.firestore.Timestamp | null | undefined;
    if (!itemId) return;

    const itemRef = db.collection("items").doc(itemId);
    await db.runTransaction(async (tx) => {
      const itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists) return;

      const current = itemSnap.get("lastUsedAt") as
        admin.firestore.Timestamp | null | undefined;
      if (usedAt && (!current || usedAt.toMillis() > current.toMillis())) {
        tx.set(itemRef, {lastUsedAt: usedAt}, {merge: true});
      }
    });

    await recomputeItemAggregates(itemId);
  }
);

// 2) lots onWrite: recompute aggregates when lots change.
export const onLotWrite = onDocumentWritten(
  "items/{itemId}/lots/{lotId}",
  async (event) => {
    const itemId = event.params.itemId as string;
    console.error(`onLotWrite triggered for item ${itemId}`);
    try {
      // event.data not needed, we recompute from scratch
      await recomputeItemAggregates(itemId);
      // Also sync item to Algolia (best-effort)
      try {
        await syncItemToAlgolia(itemId);
      } catch (e) {
        console.error("Algolia sync failed for item", itemId, e);
      }
    } catch (error) {
      console.error(`Error in onLotWrite for item ${itemId}:`, error);
    }
  }
);

/**
 * Sync a single item document to Algolia index. Uses ALGOLIA_APP_ID and ALGOLIA_ADMIN_API_KEY
 * and ALGOLIA_INDEX_NAME environment variables. This keeps the write key on server-side only.
 */
/**
 * Sync a single item document to the configured Algolia index.
 *
 * @param {string} itemId The ID of the item to index.
 * @return {Promise<void>} Resolves when the operation completes (or rejects on error).
 */
async function syncItemToAlgolia(itemId: string) {
  try {
    const client = getAlgoliaClient();
    const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && (functions.config as any)?.algolia?.index_name);
    if (!indexName) throw new Error("ALGOLIA_INDEX_NAME not configured");

    const doc = await db.collection("items").doc(itemId).get();
    const index = client.initIndex(indexName);
    if (!doc.exists) {
      await index.deleteObject(itemId).catch((err) => {
        // ignore 404-like errors
        console.warn("Delete from Algolia failed (ignored):", err.message || err);
      });
      return;
    }

    const data = doc.data() || {};
    // Convert Firestore Timestamps to ISO strings for Algolia
    const serializable: Record<string, any> = {};
    for (const [k, v] of Object.entries(data)) {
      if ((v as any)?.toDate && typeof (v as any).toDate === "function") {
        serializable[k] = (v as any).toDate().toISOString();
      } else {
        serializable[k] = v;
      }
    }

    const record = {
      objectID: doc.id,
      ...serializable,
      name: serializable["name"] ?? "",
      barcode: serializable["barcode"] ?? "",
      category: serializable["category"] ?? "",
      baseUnit: serializable["baseUnit"] ?? "",
      qtyOnHand: serializable["qtyOnHand"] ?? 0,
      minQty: serializable["minQty"] ?? 0,
      archived: serializable["archived"] ?? false,
      lots: serializable["lots"] ?? [],
    };

    await index.saveObject(record);
    // update status
    await db.collection("status").doc("algolia").set({
      lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSuccessItem: itemId,
      lastError: null,
    }, {merge: true});
  } catch (e) {
    console.error("syncItemToAlgolia error", e);
    // write status with error
    await db.collection("status").doc("algolia").set({
      lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
      lastError: String(e),
      lastSuccessItem: null,
    }, {merge: true});
    throw e;
  }
}

// Callable admin function to trigger a full reindex (restricted by IAM/roles in deployment)
export const triggerFullReindex = onCall(async (req) => {
  // minimal auth check: require auth and a claim `admin` = true
  if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
    throw new Error("unauthenticated or unauthorized");
  }

  const client = getAlgoliaClient();
  const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && (functions.config as any)?.algolia?.index_name);
  if (!indexName) throw new Error("ALGOLIA_INDEX_NAME not configured");

  const index = client.initIndex(indexName);

  // Paginate through all items and push in batches
  const BATCH = 1000;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let total = 0;
  while (true) {
    let q = db.collection("items").orderBy("__name__").limit(BATCH);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    const objects = snap.docs.map((d) => {
      const data = d.data();
      const serializable: Record<string, any> = {};
      for (const [k, v] of Object.entries(data)) {
        if ((v as any)?.toDate && typeof (v as any).toDate === "function") {
          serializable[k] = (v as any).toDate().toISOString();
        } else {
          serializable[k] = v;
        }
      }
      return {
        objectID: d.id,
        ...serializable,
        name: serializable["name"] ?? "",
        barcode: serializable["barcode"] ?? "",
        category: serializable["category"] ?? "",
        baseUnit: serializable["baseUnit"] ?? "",
        qtyOnHand: serializable["qtyOnHand"] ?? 0,
        minQty: serializable["minQty"] ?? 0,
        archived: serializable["archived"] ?? false,
        lots: serializable["lots"] ?? [],
      };
    });

    // Push to Algolia in batches
    await index.saveObjects(objects);
    total += objects.length;
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < BATCH) break;
  }

  // write status
  await db.collection("status").doc("algolia").set({
    lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    lastIndexedCount: total,
    lastError: null,
  }, {merge: true});

  return {success: true, totalIndexed: total};
});

// Callable function to recalculate all item aggregates/flags
export const recalculateAllItemAggregates = onCall(async (req) => {
  // minimal auth check: require auth
  if (!req.auth) {
    throw new Error("unauthenticated");
  }

  const PAGE = 100;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let processed = 0;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db.collection("items").orderBy("updatedAt", "desc").limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      await recomputeItemAggregates(doc.id);
      processed++;
    }
    last = snap.docs[snap.docs.length - 1];
  }

  return {
    success: true,
    message: `Recalculated aggregates for ${processed} items`,
    processed,
  };
});

export const configureAlgoliaIndex = onCall(async (req) => {
  if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
    throw new Error("unauthenticated or unauthorized");
  }

  const client = getAlgoliaClient();
  const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && (functions.config as any)?.algolia?.index_name);
  if (!indexName) throw new Error("ALGOLIA_INDEX_NAME not configured");
  const index = client.initIndex(indexName);

  const settings = {
    attributesForFaceting: [
      "category",
      "baseUnit",
      "archived",
      "filterOnly(qtyOnHand)",
      "filterOnly(minQty)",
      "filterOnly(barcode)",
    ],
    searchableAttributes: [
      "name",
      "barcode",
      "category",
      "description",
      "notes",
    ],
    customRanking: ["desc(qtyOnHand)"],
    ranking: ["typo", "geo", "words", "filters", "proximity", "attribute", "exact", "custom"],
  };

  await index.setSettings(settings);
  return {success: true};
});

export const syncItemToAlgoliaCallable = onCall(async (req) => {
  if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
    throw new Error("unauthenticated or unauthorized");
  }
  const itemId = req.data?.itemId as string | undefined;
  if (!itemId) throw new Error("itemId is required");
  await syncItemToAlgolia(itemId);
  return {success: true};
});

// 3) Daily job: refresh flagExpiringSoon (and sanity recompute aggregates).
export const nightlyExpirySweep = onSchedule("every day 02:15", async () => {
  const PAGE = 300;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db.collection("items").orderBy("updatedAt", "desc").limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      await recomputeItemAggregates(doc.id);
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) break;
  }
});

// --- Dashboard counts aggregation ---

/**
 * Incrementally maintain meta/dashboard_stats counts when an item changes.
 * Counts tracked (archived = false only): low, expiring, stale, expired.
 */
export const onItemWriteUpdateDashboard = onDocumentWritten(
  "items/{itemId}",
  async (event) => {
    const before = event.data?.before?.data() as Record<string, any> | undefined;
    const after = event.data?.after?.data() as Record<string, any> | undefined;

    // Helper to check eligibility (flag true and not archived)
    const eligible = (d: Record<string, any> | undefined, flag: string) => {
      if (!d) return false;
      const f = Boolean(d[flag]);
      const archived = Boolean(d["archived"]);
      return f && !archived;
    };

    const flags = [
      {key: "flagLow", field: "low"},
      {key: "flagExpiringSoon", field: "expiring"},
      {key: "flagStale", field: "stale"},
      {key: "flagExpired", field: "expired"},
    ] as const;

    // Compute deltas per flag
    const deltas: Record<string, number> = {};
    for (const f of flags) {
      const was = eligible(before, f.key);
      const now = eligible(after, f.key);
      if (was === now) continue;
      deltas[f.field] = (deltas[f.field] || 0) + (now ? 1 : -1);
    }

    if (Object.keys(deltas).length === 0) {
      return; // nothing to update
    }

    const statsRef = db.collection("meta").doc("dashboard_stats");
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(statsRef);
      // ensure fields exist
      const base = snap.exists ? snap.data() || {} : {};
      const update: Record<string, any> = {};
      for (const [k, v] of Object.entries(deltas)) {
        // use increment to avoid races
        update[k] = admin.firestore.FieldValue.increment(v as number);
      }
      update["updatedAt"] = admin.firestore.FieldValue.serverTimestamp();

      if (!snap.exists) {
        // seed missing fields to zero
        const seed: Record<string, any> = {low: 0, expiring: 0, stale: 0, expired: 0, ...base};
        tx.set(statsRef, {...seed, ...update}, {merge: true});
      } else {
        tx.set(statsRef, update, {merge: true});
      }
    });
  }
);

/**
 * Nightly reconciliation job to fully recompute dashboard counts from items.
 * Ensures counters remain accurate if any incremental updates were missed.
 */
async function recomputeDashboardStats() {
  const PAGE = 1000;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;

  const totals = {low: 0, expiring: 0, stale: 0, expired: 0};
  let processedCount = 0;

  console.log("Starting dashboard stats recomputation...");

  // eslint-disable-next-line no-constant-condition
  while (true) {
    // Get all items without archived filter, then filter in code
    // This avoids issues with missing/null archived fields
    let q = db.collection("items").limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    console.log(`Fetched ${snap.size} items`);
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const d = doc.data();

      // Skip if archived is explicitly true
      if (d.archived === true) {
        console.log(`Skipping archived item ${doc.id}`);
        continue;
      }

      processedCount++;
      if (d.flagLow) {
        totals.low++;
        console.log(`Item ${doc.id} has flagLow`);
      }
      if (d.flagExpiringSoon) {
        totals.expiring++;
        console.log(`Item ${doc.id} has flagExpiringSoon`);
      }
      if (d.flagStale) {
        totals.stale++;
        console.log(`Item ${doc.id} has flagStale`);
      }
      if (d.flagExpired) {
        totals.expired++;
        console.log(`Item ${doc.id} has flagExpired`);
      }
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) break;
  }

  console.log(`Processed ${processedCount} items. Totals:`, totals);

  await db.collection("meta").doc("dashboard_stats").set({
    ...totals,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastRecalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  console.log("Dashboard stats updated successfully");
}

export const nightlyRecalcDashboardStats = onSchedule("every day 02:45", async () => {
  await recomputeDashboardStats();
});

import {onCall as onCallHttps} from "firebase-functions/v2/https";

// Callable to force a full dashboard stats recompute (guard with basic auth)
export const recalcDashboardStatsManual = onCallHttps(async (req) => {
  if (!req.auth) {
    throw new Error("unauthenticated");
  }
  await recomputeDashboardStats();
  return {success: true};
});

// Budget proxy handler for same-origin embedding of Actual Budget
import {onRequest} from "firebase-functions/v2/https";
import * as https from "https";
import * as http from "http";
import {URL} from "url";

const BUDGET_API_URL = "https://scout-budget.littleempathy.com";

export const budgetProxy = onRequest((req, res) => {
  try {
    // Remove /budget prefix from path
    let path = req.path.replace(/^\/budget\/?/, "");
    // Ensure path starts with / for URL construction
    if (!path.startsWith("/")) {
      path = "/" + path;
    }
    const targetUrl = new URL(path, BUDGET_API_URL).toString();

    console.log(`Proxying ${req.method} ${path} -> ${targetUrl}`);

    // Forward request with preserved headers
    const forwardedHeaders: any = {};
    const headersToForward = [
      "cookie",
      "user-agent",
      "referer",
      "accept",
      "accept-encoding",
      "content-type",
      "content-length",
      "authorization",
    ];

    headersToForward.forEach((header) => {
      const value = req.headers[header];
      if (value) {
        forwardedHeaders[header] = value;
      }
    });

    // Add forwarded headers
    forwardedHeaders["x-forwarded-for"] = req.ip;
    forwardedHeaders["x-forwarded-proto"] = req.protocol;

    // Parse target URL
    const targetUrlObj = new URL(targetUrl);
    const protocol = targetUrlObj.protocol === "https:" ? https : http;

    // Make request to budget API
    const proxyReq = protocol.request(
      {
        hostname: targetUrlObj.hostname,
        port: targetUrlObj.port,
        path: targetUrlObj.pathname + targetUrlObj.search,
        method: req.method,
        headers: forwardedHeaders,
        rejectUnauthorized: false,
      },
      (proxyRes) => {
        // Set response status
        res.status(proxyRes.statusCode || 200);

        // Copy response headers
        const headersToCopy = [
          "content-type",
          "cache-control",
          "set-cookie",
          "content-encoding",
          "content-disposition",
          "access-control-allow-origin",
          "content-language",
        ];

        headersToCopy.forEach((header) => {
          const value = proxyRes.headers[header];
          if (value) {
            res.setHeader(header, value);
          }
        });

        // Override headers for iframe safety
        res.setHeader("X-Frame-Options", "ALLOWALL");
        res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
        res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
        res.setHeader("Content-Security-Policy", "frame-ancestors 'self'");

        // For HTML responses on GET requests, inject base tag
        const contentType = proxyRes.headers["content-type"] as string || "";
        if (contentType.includes("text/html") && req.method === "GET") {
          let body = "";
          proxyRes.setEncoding("utf8");

          proxyRes.on("data", (chunk: string) => {
            body += chunk;
          });

          proxyRes.on("end", () => {
            try {
              // Inject <base href="/budget/"> right after <head> tag
              const modifiedBody = body.replace(
                /(<head[^>]*>)/i,
                "$1\n    <base href=\"/budget/\">"
              );

              res.removeHeader("Content-Length");
              res.write(modifiedBody);
              res.end();
            } catch (err) {
              console.error("Error modifying HTML:", err);
              res.write(body);
              res.end();
            }
          });

          proxyRes.on("error", (error) => {
            console.error("Proxy response error:", error);
            res.status(502).end("Bad Gateway");
          });
        } else {
          // Pipe response body directly for non-HTML
          proxyRes.pipe(res);
        }
      }
    );

    proxyReq.on("error", (error) => {
      console.error("Proxy request error:", error);
      res.status(502).end("Bad Gateway");
    });

    // Handle request body for POST/PUT/PATCH
    if (req.method !== "GET" && req.method !== "HEAD") {
      if (req.body) {
        if (typeof req.body === "string") {
          proxyReq.write(req.body);
        } else {
          proxyReq.write(JSON.stringify(req.body));
        }
      }
    }

    proxyReq.end();
  } catch (error) {
    console.error("Budget proxy error:", error);
    res.status(502).end("Bad Gateway");
  }
});

// ---------- Feedback RSS Feed ----------
/**
 * Generates an RSS feed of feedback items (bugs, features, questions)
 * Access at: https://us-central1-scout-litteempathy.cloudfunctions.net/feedbackRss
 */
export const feedbackRss = onRequest(async (req, res) => {
  try {
    // Set CORS headers
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Content-Type", "application/rss+xml; charset=utf-8");
    res.set("Cache-Control", "public, max-age=300"); // Cache for 5 minutes

    // Fetch recent feedback items
    const feedbackSnapshot = await db
      .collection("feedback")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();

    const items: string[] = [];
    const siteUrl = "https://scout.littleempathy.com";

    for (const doc of feedbackSnapshot.docs) {
      const data = doc.data();
      const title = escapeXml(data.title || "Untitled");
      const description = escapeXml(data.description || "");
      const type = data.type || "bug"; // bug, feature, question
      const status = data.status || "open";
      const submittedBy = escapeXml(data.submittedBy || "Anonymous");
      const voteCount = data.voteCount || 0;
      const createdAt = data.createdAt?.toDate() || new Date();

      // Format type label
      let typeLabel = type;
      if (type === "bug") {
        typeLabel = "Bug";
      } else if (type === "feature") {
        typeLabel = "Feature Request";
      } else if (type === "question") {
        typeLabel = "Question";
      }

      const itemContent = `
        <p><strong>Type:</strong> ${typeLabel}</p>
        <p><strong>Status:</strong> ${status}</p>
        <p><strong>Submitted by:</strong> ${submittedBy}</p>
        <p><strong>Votes:</strong> ${voteCount}</p>
        ${description ? `<p>${escapeXml(description)}</p>` : ""}
      `.trim();

      items.push(`
    <item>
      <title>[${typeLabel}] ${title}</title>
      <link>${siteUrl}/feedback</link>
      <guid isPermaLink="false">feedback-${doc.id}</guid>
      <pubDate>${createdAt.toUTCString()}</pubDate>
      <author>${submittedBy}</author>
      <category>${type}</category>
      <description><![CDATA[${itemContent}]]></description>
    </item>`);
    }

    const rss = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>SCOUT Feedback</title>
    <link>${siteUrl}/feedback</link>
    <description>Bug reports, feature requests, and questions for SCOUT inventory management</description>
    <language>en-us</language>
    <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
    <atom:link href="https://us-central1-scout-litteempathy.cloudfunctions.net/feedbackRss" rel="self" type="application/rss+xml"/>
    <image>
      <url>${siteUrl}/icons/Icon-192.png</url>
      <title>SCOUT Feedback</title>
      <link>${siteUrl}/feedback</link>
    </image>
${items.join("\n")}
  </channel>
</rss>`;

    res.status(200).send(rss);
  } catch (error) {
    console.error("RSS feed error:", error);
    res.status(500).send("Error generating RSS feed");
  }
});

/**
 * Escape special XML characters
 * @param {string} str - The string to escape
 * @return {string} The escaped string
 */
function escapeXml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
