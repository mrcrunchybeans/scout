import * as admin from "firebase-admin";
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

// ---------- Tunables ----------
const STALE_DAYS = 45; // no use for ≥ N days
const EXCESS_FACTOR = 3; // qtyOnHand ≥ N * minQty
const EXPIRING_SOON_DAYS = 14; // earliest lot expiration within N days

// ---------- Helpers ----------
type Lot = {
  qtyRemaining?: number;
  expiresAt?: admin.firestore.Timestamp | null;
  openAt?: admin.firestore.Timestamp | null;
  expiresAfterOpenDays?: number | null;
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
  const itemRef = db.collection("items").doc(itemId);
  const [itemSnap, lotsSnap] = await Promise.all([
    itemRef.get(),
    itemRef.collection("lots").get(),
  ]);

  if (!itemSnap.exists) return;

  const item = itemSnap.data() || {};
  const minQty = Number(item.minQty || 0);
  const lastUsedAt = item.lastUsedAt as
    admin.firestore.Timestamp | null | undefined;

  // Sum remaining from lots & compute earliest expiry
  let qtyOnHand = 0;
  let earliest: Date | null = null;

  lotsSnap.forEach((doc) => {
    const lot = doc.data() as Lot;
    const rem = Number(lot.qtyRemaining || 0);
    qtyOnHand += rem;

    const eff = effectiveLotExpiry(lot);
    if (eff) {
      if (!earliest || eff < earliest) earliest = eff;
    }
  });

  // Flags
  const now = new Date();
  const flagLow = minQty > 0 && qtyOnHand <= minQty;
  const flagExcess = minQty > 0 && qtyOnHand >= EXCESS_FACTOR * minQty;
  const flagStale = daysSince(lastUsedAt, now) >= STALE_DAYS;
  const flagExpiringSoon = isExpiringSoon(earliest, now);
  const flagExpired = earliest ? (earliest as Date).getTime() < now.getTime() : false;

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
import {onCall} from "firebase-functions/v2/https";

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
    // event.data not needed, we recompute from scratch
    await recomputeItemAggregates(itemId);
    // Also sync item to Algolia (best-effort)
    try {
      await syncItemToAlgolia(itemId);
    } catch (e) {
      console.error("Algolia sync failed for item", itemId, e);
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
    const indexName = process.env.ALGOLIA_INDEX_NAME;
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
  const indexName = process.env.ALGOLIA_INDEX_NAME;
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
  const indexName = process.env.ALGOLIA_INDEX_NAME;
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
