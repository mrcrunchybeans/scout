import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

admin.initializeApp();
const db = admin.firestore();

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

  // Write back (merge)
  const patch: Record<string, any> = {
    qtyOnHand,
    flagLow,
    flagExcess,
    flagStale,
    flagExpiringSoon,
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
  }
);

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
