"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.budgetProxy = exports.recalcDashboardStatsManual = exports.nightlyRecalcDashboardStats = exports.onItemWriteUpdateDashboard = exports.nightlyExpirySweep = exports.syncItemToAlgoliaCallable = exports.configureAlgoliaIndex = exports.recalculateAllItemAggregates = exports.triggerFullReindex = exports.onLotWrite = exports.onUsageLogCreate = exports.wipeInventoryData = exports.createManualBackup = exports.dailyBackup = void 0;
const admin = __importStar(require("firebase-admin"));
// Load environment variables from .env when present (for local/dev)
require("dotenv/config");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const functions = __importStar(require("firebase-functions"));
const algoliasearch_1 = __importDefault(require("algoliasearch"));
admin.initializeApp();
const db = admin.firestore();
// Algolia client will be created lazily from environment variables
let algoliaClient = null;
function getAlgoliaClient() {
    var _a, _b, _c, _d;
    if (algoliaClient)
        return algoliaClient;
    // Prefer environment variables, fall back to firebase functions config
    // (set with `firebase functions:config:set algolia.app_id="..."`)
    // algolia.admin_key="..." algolia.index_name="..."`)
    const appId = process.env.ALGOLIA_APP_ID || (functions && ((_b = (_a = functions.config) === null || _a === void 0 ? void 0 : _a.algolia) === null || _b === void 0 ? void 0 : _b.app_id));
    const apiKey = process.env.ALGOLIA_ADMIN_API_KEY || (functions && ((_d = (_c = functions.config) === null || _c === void 0 ? void 0 : _c.algolia) === null || _d === void 0 ? void 0 : _d.admin_key)); // server-side admin key
    if (!appId || !apiKey)
        throw new Error("Algolia credentials not configured (process.env or functions.config)");
    algoliaClient = (0, algoliasearch_1.default)(appId, apiKey);
    return algoliaClient;
}
function getDeveloperPassword() {
    var _a, _b;
    const env = process.env.DEV_PASSWORD;
    if (env && env.length > 0)
        return env;
    const fallback = (functions && ((_b = (_a = functions.config) === null || _a === void 0 ? void 0 : _a.admin) === null || _b === void 0 ? void 0 : _b.dev_password));
    if (fallback && fallback.length > 0)
        return fallback;
    return null;
}
function assertDeveloperPassword(password) {
    const expected = getDeveloperPassword();
    if (!expected) {
        throw new https_1.HttpsError("failed-precondition", "Developer password is not configured on the server.");
    }
    if (!password || password !== expected) {
        throw new https_1.HttpsError("permission-denied", "Invalid developer password.");
    }
}
// ---------- Tunables ----------
const STALE_DAYS = 45; // no use for ≥ N days
const EXCESS_FACTOR = 3; // qtyOnHand ≥ N * minQty
const EXPIRING_SOON_DAYS = 14; // earliest lot expiration within N days
const WIPE_BATCH_SIZE = 400;
const COLLECTIONS_TO_WIPE = [
    { collection: "items", subcollections: ["lots"] },
    { collection: "sessions" },
    { collection: "cartSessions" },
    { collection: "usage_logs" },
];
/**
 * Convert Firestore types to plain JavaScript objects for safe serialization
 * @param {any} obj - The object to convert
 * @return {any} The converted object
 */
function convertFirestoreTypes(obj) {
    if (obj === null || obj === undefined)
        return obj;
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
        return { _type: "timestamp", _value: obj.toDate().toISOString() };
    }
    if (obj instanceof admin.firestore.GeoPoint) {
        return {
            _type: "geopoint",
            _value: { latitude: obj.latitude, longitude: obj.longitude },
        };
    }
    if (obj instanceof admin.firestore.DocumentReference) {
        return { _type: "documentReference", _value: obj.path };
    }
    if (Array.isArray(obj)) {
        return obj.map(convertFirestoreTypes);
    }
    const result = {};
    for (const [key, value] of Object.entries(obj)) {
        result[key] = convertFirestoreTypes(value);
    }
    return result;
}
async function deleteSubcollectionDocs(collectionRef, batchSize = WIPE_BATCH_SIZE) {
    while (true) {
        const snapshot = await collectionRef.limit(batchSize).get();
        if (snapshot.empty)
            break;
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
    }
}
async function deleteCollectionDocs(collectionPath, subcollections = [], batchSize = WIPE_BATCH_SIZE) {
    const collectionRef = db.collection(collectionPath);
    while (true) {
        const snapshot = await collectionRef.limit(batchSize).get();
        if (snapshot.empty)
            break;
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
function effectiveLotExpiry(lot) {
    var _a, _b, _c, _d, _e;
    const expiresAt = (_b = (_a = lot.expiresAt) === null || _a === void 0 ? void 0 : _a.toDate()) !== null && _b !== void 0 ? _b : null;
    const openAt = (_d = (_c = lot.openAt) === null || _c === void 0 ? void 0 : _c.toDate()) !== null && _d !== void 0 ? _d : null;
    const afterDays = (_e = lot.expiresAfterOpenDays) !== null && _e !== void 0 ? _e : null;
    // If after-open rule applies, effective = min(expiresAt, openAt + afterDays)
    if (openAt && afterDays && afterDays > 0) {
        const afterOpen = new Date(openAt.getTime());
        afterOpen.setDate(afterOpen.getDate() + afterDays);
        if (expiresAt)
            return afterOpen < expiresAt ? afterOpen : expiresAt;
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
function isExpiringSoon(d, now = new Date()) {
    if (!d)
        return false;
    const days = Math.floor((d.getTime() - now.getTime()) / (24 * 3600 * 1000));
    return days >= 0 && days <= EXPIRING_SOON_DAYS;
}
/**
 * Calculate the number of days since a timestamp.
 * @param {admin.firestore.Timestamp | null | undefined} d - The timestamp
 * @param {Date} now - The current date (defaults to now)
 * @return {number} Number of days since the timestamp
 */
function daysSince(d, now = new Date()) {
    if (!d)
        return Infinity;
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
async function recomputeItemAggregates(itemId) {
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
        const lastUsedAt = item.lastUsedAt;
        // Sum remaining from lots & compute earliest expiry
        let qtyOnHand = Number(item.qtyOnHand || 0); // Preserve current qtyOnHand
        let earliest = null;
        console.error(`Item ${itemId}: has ${lotsSnap.size} lots, current qtyOnHand: ${qtyOnHand}, minQty: ${minQty}`);
        // Only recalculate qtyOnHand from lots if the item actually has lots
        if (!lotsSnap.empty) {
            qtyOnHand = 0; // Reset to recalculate from lots
            lotsSnap.forEach((doc) => {
                const lot = doc.data();
                const rem = Number(lot.qtyRemaining || 0);
                qtyOnHand += rem;
                const eff = effectiveLotExpiry(lot);
                if (eff) {
                    if (!earliest || eff < earliest)
                        earliest = eff;
                }
            });
            console.error(`Item ${itemId}: recalculated qtyOnHand from lots: ${qtyOnHand}`);
        }
        else {
            console.error(`Item ${itemId}: preserving qtyOnHand: ${qtyOnHand}`);
        }
        // Flags
        const now = new Date();
        const flagLow = minQty > 0 && qtyOnHand <= minQty;
        const flagExcess = minQty > 0 && qtyOnHand >= EXCESS_FACTOR * minQty;
        const flagStale = daysSince(lastUsedAt, now) >= STALE_DAYS;
        const flagExpiringSoon = isExpiringSoon(earliest, now);
        const flagExpired = earliest ? earliest.getTime() < now.getTime() : false;
        console.error(`Item ${itemId}: flags - low: ${flagLow}, stale: ${flagStale}, expiringSoon: ${flagExpiringSoon}, expired: ${flagExpired}`);
        // Write back (merge)
        const patch = {
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
        await itemRef.set(patch, { merge: true });
        console.error(`Item ${itemId}: updated successfully`);
    }
    catch (error) {
        console.error(`Error recomputing aggregates for item ${itemId}:`, error);
    }
}
// ---------- Backup Configuration ----------
const BACKUP_COLLECTIONS = ["items", "lookups", "config"];
// ---------- Backup Functions ----------
// Automated daily backup
exports.dailyBackup = (0, scheduler_1.onSchedule)("every day 03:00", async () => {
    console.log("Starting automated daily backup...");
    try {
        const backupData = {};
        let totalDocuments = 0;
        // Export each collection
        for (const collectionName of BACKUP_COLLECTIONS) {
            console.log(`Backing up collection: ${collectionName}`);
            const snapshot = await db.collection(collectionName).get();
            const documents = {};
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
    }
    catch (error) {
        console.error("Automated backup failed:", error);
        throw error; // Re-throw to mark function as failed
    }
});
// Clean up backups older than retention period
/**
 * Clean up backups older than the configured retention period.
 */
async function cleanupOldBackups() {
    var _a, _b;
    // Get retention settings from config
    const configDoc = await db.collection("config").doc("backup").get();
    const retentionDays = configDoc.exists ?
        (_b = (_a = configDoc.data()) === null || _a === void 0 ? void 0 : _a.retentionDays) !== null && _b !== void 0 ? _b : 30 :
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
const https_1 = require("firebase-functions/v2/https");
exports.createManualBackup = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    // Note: Authentication check removed - protected by admin PIN in client
    console.log("Manual backup requested");
    try {
        const backupData = {};
        let totalDocuments = 0;
        // Export each collection
        for (const collectionName of BACKUP_COLLECTIONS) {
            const snapshot = await db.collection(collectionName).get();
            const documents = {};
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
            createdBy: (_b = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid) !== null && _b !== void 0 ? _b : "admin",
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
    }
    catch (error) {
        console.error("Manual backup failed:", error);
        throw new Error(`Backup failed: ${error}`);
    }
});
exports.wipeInventoryData = (0, https_1.onCall)({
    region: "us-central1",
    timeoutSeconds: 540,
}, async (request) => {
    var _a, _b, _c, _d, _e;
    const password = (_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.password) === null || _b === void 0 ? void 0 : _b.trim();
    assertDeveloperPassword(password);
    const cleared = [];
    for (const entry of COLLECTIONS_TO_WIPE) {
        await deleteCollectionDocs(entry.collection, (_c = entry.subcollections) !== null && _c !== void 0 ? _c : []);
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
        }, { merge: true });
    }
    catch (error) {
        console.error("Failed to reset dashboard stats after wipe:", error);
    }
    // Clear Algolia index if configured
    try {
        const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && ((_e = (_d = functions.config) === null || _d === void 0 ? void 0 : _d.algolia) === null || _e === void 0 ? void 0 : _e.index_name));
        if (indexName) {
            await getAlgoliaClient().initIndex(indexName).clearObjects();
        }
        else {
            console.warn("ALGOLIA_INDEX_NAME not configured; skipping Algolia clear during wipe.");
        }
    }
    catch (error) {
        console.error("Failed to clear Algolia index during wipe:", error);
    }
    return {
        success: true,
        cleared,
    };
});
// NOTE: Client adjusts lots, server recomputes totals.
exports.onUsageLogCreate = (0, firestore_1.onDocumentCreated)("usage_logs/{logId}", async (event) => {
    const snap = event.data; // QueryDocumentSnapshot | undefined
    if (!snap)
        return; // safety
    const data = snap.data();
    const itemId = data.itemId;
    const usedAt = data.usedAt;
    if (!itemId)
        return;
    const itemRef = db.collection("items").doc(itemId);
    await db.runTransaction(async (tx) => {
        const itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists)
            return;
        const current = itemSnap.get("lastUsedAt");
        if (usedAt && (!current || usedAt.toMillis() > current.toMillis())) {
            tx.set(itemRef, { lastUsedAt: usedAt }, { merge: true });
        }
    });
    await recomputeItemAggregates(itemId);
});
// 2) lots onWrite: recompute aggregates when lots change.
exports.onLotWrite = (0, firestore_1.onDocumentWritten)("items/{itemId}/lots/{lotId}", async (event) => {
    const itemId = event.params.itemId;
    console.error(`onLotWrite triggered for item ${itemId}`);
    try {
        // event.data not needed, we recompute from scratch
        await recomputeItemAggregates(itemId);
        // Also sync item to Algolia (best-effort)
        try {
            await syncItemToAlgolia(itemId);
        }
        catch (e) {
            console.error("Algolia sync failed for item", itemId, e);
        }
    }
    catch (error) {
        console.error(`Error in onLotWrite for item ${itemId}:`, error);
    }
});
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
async function syncItemToAlgolia(itemId) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    try {
        const client = getAlgoliaClient();
        const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && ((_b = (_a = functions.config) === null || _a === void 0 ? void 0 : _a.algolia) === null || _b === void 0 ? void 0 : _b.index_name));
        if (!indexName)
            throw new Error("ALGOLIA_INDEX_NAME not configured");
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
        const serializable = {};
        for (const [k, v] of Object.entries(data)) {
            if ((v === null || v === void 0 ? void 0 : v.toDate) && typeof v.toDate === "function") {
                serializable[k] = v.toDate().toISOString();
            }
            else {
                serializable[k] = v;
            }
        }
        const record = Object.assign(Object.assign({ objectID: doc.id }, serializable), { name: (_c = serializable["name"]) !== null && _c !== void 0 ? _c : "", barcode: (_d = serializable["barcode"]) !== null && _d !== void 0 ? _d : "", category: (_e = serializable["category"]) !== null && _e !== void 0 ? _e : "", baseUnit: (_f = serializable["baseUnit"]) !== null && _f !== void 0 ? _f : "", qtyOnHand: (_g = serializable["qtyOnHand"]) !== null && _g !== void 0 ? _g : 0, minQty: (_h = serializable["minQty"]) !== null && _h !== void 0 ? _h : 0, archived: (_j = serializable["archived"]) !== null && _j !== void 0 ? _j : false, lots: (_k = serializable["lots"]) !== null && _k !== void 0 ? _k : [] });
        await index.saveObject(record);
        // update status
        await db.collection("status").doc("algolia").set({
            lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
            lastSuccessItem: itemId,
            lastError: null,
        }, { merge: true });
    }
    catch (e) {
        console.error("syncItemToAlgolia error", e);
        // write status with error
        await db.collection("status").doc("algolia").set({
            lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
            lastError: String(e),
            lastSuccessItem: null,
        }, { merge: true });
        throw e;
    }
}
// Callable admin function to trigger a full reindex (restricted by IAM/roles in deployment)
exports.triggerFullReindex = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    // minimal auth check: require auth and a claim `admin` = true
    if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
        throw new Error("unauthenticated or unauthorized");
    }
    const client = getAlgoliaClient();
    const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && ((_b = (_a = functions.config) === null || _a === void 0 ? void 0 : _a.algolia) === null || _b === void 0 ? void 0 : _b.index_name));
    if (!indexName)
        throw new Error("ALGOLIA_INDEX_NAME not configured");
    const index = client.initIndex(indexName);
    // Paginate through all items and push in batches
    const BATCH = 1000;
    let last;
    let total = 0;
    while (true) {
        let q = db.collection("items").orderBy("__name__").limit(BATCH);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        const objects = snap.docs.map((d) => {
            var _a, _b, _c, _d, _e, _f, _g, _h;
            const data = d.data();
            const serializable = {};
            for (const [k, v] of Object.entries(data)) {
                if ((v === null || v === void 0 ? void 0 : v.toDate) && typeof v.toDate === "function") {
                    serializable[k] = v.toDate().toISOString();
                }
                else {
                    serializable[k] = v;
                }
            }
            return Object.assign(Object.assign({ objectID: d.id }, serializable), { name: (_a = serializable["name"]) !== null && _a !== void 0 ? _a : "", barcode: (_b = serializable["barcode"]) !== null && _b !== void 0 ? _b : "", category: (_c = serializable["category"]) !== null && _c !== void 0 ? _c : "", baseUnit: (_d = serializable["baseUnit"]) !== null && _d !== void 0 ? _d : "", qtyOnHand: (_e = serializable["qtyOnHand"]) !== null && _e !== void 0 ? _e : 0, minQty: (_f = serializable["minQty"]) !== null && _f !== void 0 ? _f : 0, archived: (_g = serializable["archived"]) !== null && _g !== void 0 ? _g : false, lots: (_h = serializable["lots"]) !== null && _h !== void 0 ? _h : [] });
        });
        // Push to Algolia in batches
        await index.saveObjects(objects);
        total += objects.length;
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < BATCH)
            break;
    }
    // write status
    await db.collection("status").doc("algolia").set({
        lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
        lastIndexedCount: total,
        lastError: null,
    }, { merge: true });
    return { success: true, totalIndexed: total };
});
// Callable function to recalculate all item aggregates/flags
exports.recalculateAllItemAggregates = (0, https_1.onCall)(async (req) => {
    // minimal auth check: require auth
    if (!req.auth) {
        throw new Error("unauthenticated");
    }
    const PAGE = 100;
    let last;
    let processed = 0;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = db.collection("items").orderBy("updatedAt", "desc").limit(PAGE);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
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
exports.configureAlgoliaIndex = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
        throw new Error("unauthenticated or unauthorized");
    }
    const client = getAlgoliaClient();
    const indexName = process.env.ALGOLIA_INDEX_NAME || (functions && ((_b = (_a = functions.config) === null || _a === void 0 ? void 0 : _a.algolia) === null || _b === void 0 ? void 0 : _b.index_name));
    if (!indexName)
        throw new Error("ALGOLIA_INDEX_NAME not configured");
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
    return { success: true };
});
exports.syncItemToAlgoliaCallable = (0, https_1.onCall)(async (req) => {
    var _a;
    if (!req.auth || !(req.auth.token && req.auth.token.admin)) {
        throw new Error("unauthenticated or unauthorized");
    }
    const itemId = (_a = req.data) === null || _a === void 0 ? void 0 : _a.itemId;
    if (!itemId)
        throw new Error("itemId is required");
    await syncItemToAlgolia(itemId);
    return { success: true };
});
// 3) Daily job: refresh flagExpiringSoon (and sanity recompute aggregates).
exports.nightlyExpirySweep = (0, scheduler_1.onSchedule)("every day 02:15", async () => {
    const PAGE = 300;
    let last;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = db.collection("items").orderBy("updatedAt", "desc").limit(PAGE);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            await recomputeItemAggregates(doc.id);
        }
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < PAGE)
            break;
    }
});
// --- Dashboard counts aggregation ---
/**
 * Incrementally maintain meta/dashboard_stats counts when an item changes.
 * Counts tracked (archived = false only): low, expiring, stale, expired.
 */
exports.onItemWriteUpdateDashboard = (0, firestore_1.onDocumentWritten)("items/{itemId}", async (event) => {
    var _a, _b, _c, _d;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    // Helper to check eligibility (flag true and not archived)
    const eligible = (d, flag) => {
        if (!d)
            return false;
        const f = Boolean(d[flag]);
        const archived = Boolean(d["archived"]);
        return f && !archived;
    };
    const flags = [
        { key: "flagLow", field: "low" },
        { key: "flagExpiringSoon", field: "expiring" },
        { key: "flagStale", field: "stale" },
        { key: "flagExpired", field: "expired" },
    ];
    // Compute deltas per flag
    const deltas = {};
    for (const f of flags) {
        const was = eligible(before, f.key);
        const now = eligible(after, f.key);
        if (was === now)
            continue;
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
        const update = {};
        for (const [k, v] of Object.entries(deltas)) {
            // use increment to avoid races
            update[k] = admin.firestore.FieldValue.increment(v);
        }
        update["updatedAt"] = admin.firestore.FieldValue.serverTimestamp();
        if (!snap.exists) {
            // seed missing fields to zero
            const seed = Object.assign({ low: 0, expiring: 0, stale: 0, expired: 0 }, base);
            tx.set(statsRef, Object.assign(Object.assign({}, seed), update), { merge: true });
        }
        else {
            tx.set(statsRef, update, { merge: true });
        }
    });
});
/**
 * Nightly reconciliation job to fully recompute dashboard counts from items.
 * Ensures counters remain accurate if any incremental updates were missed.
 */
async function recomputeDashboardStats() {
    const PAGE = 1000;
    let last;
    const totals = { low: 0, expiring: 0, stale: 0, expired: 0 };
    let processedCount = 0;
    console.log("Starting dashboard stats recomputation...");
    // eslint-disable-next-line no-constant-condition
    while (true) {
        // Get all items without archived filter, then filter in code
        // This avoids issues with missing/null archived fields
        let q = db.collection("items").limit(PAGE);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        console.log(`Fetched ${snap.size} items`);
        if (snap.empty)
            break;
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
        if (snap.size < PAGE)
            break;
    }
    console.log(`Processed ${processedCount} items. Totals:`, totals);
    await db.collection("meta").doc("dashboard_stats").set(Object.assign(Object.assign({}, totals), { updatedAt: admin.firestore.FieldValue.serverTimestamp(), lastRecalculatedAt: admin.firestore.FieldValue.serverTimestamp() }), { merge: true });
    console.log("Dashboard stats updated successfully");
}
exports.nightlyRecalcDashboardStats = (0, scheduler_1.onSchedule)("every day 02:45", async () => {
    await recomputeDashboardStats();
});
const https_2 = require("firebase-functions/v2/https");
// Callable to force a full dashboard stats recompute (guard with basic auth)
exports.recalcDashboardStatsManual = (0, https_2.onCall)(async (req) => {
    if (!req.auth) {
        throw new Error("unauthenticated");
    }
    await recomputeDashboardStats();
    return { success: true };
});
// Budget proxy handler for same-origin embedding of Actual Budget
const https_3 = require("firebase-functions/v2/https");
const https = __importStar(require("https"));
const http = __importStar(require("http"));
const url_1 = require("url");
const BUDGET_API_URL = "https://scout-budget.littleempathy.com";
exports.budgetProxy = (0, https_3.onRequest)((req, res) => {
    try {
        // Remove /budget prefix from path
        let path = req.path.replace(/^\/budget\/?/, "");
        // Ensure path starts with / for URL construction
        if (!path.startsWith("/")) {
            path = "/" + path;
        }
        const targetUrl = new url_1.URL(path, BUDGET_API_URL).toString();
        console.log(`Proxying ${req.method} ${path} -> ${targetUrl}`);
        // Forward request with preserved headers
        const forwardedHeaders = {};
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
        const targetUrlObj = new url_1.URL(targetUrl);
        const protocol = targetUrlObj.protocol === "https:" ? https : http;
        // Make request to budget API
        const proxyReq = protocol.request({
            hostname: targetUrlObj.hostname,
            port: targetUrlObj.port,
            path: targetUrlObj.pathname + targetUrlObj.search,
            method: req.method,
            headers: forwardedHeaders,
            rejectUnauthorized: false,
        }, (proxyRes) => {
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
            const contentType = proxyRes.headers["content-type"] || "";
            if (contentType.includes("text/html") && req.method === "GET") {
                let body = "";
                proxyRes.setEncoding("utf8");
                proxyRes.on("data", (chunk) => {
                    body += chunk;
                });
                proxyRes.on("end", () => {
                    try {
                        // Inject <base href="/budget/"> right after <head> tag
                        const modifiedBody = body.replace(/(<head[^>]*>)/i, "$1\n    <base href=\"/budget/\">");
                        res.removeHeader("Content-Length");
                        res.write(modifiedBody);
                        res.end();
                    }
                    catch (err) {
                        console.error("Error modifying HTML:", err);
                        res.write(body);
                        res.end();
                    }
                });
                proxyRes.on("error", (error) => {
                    console.error("Proxy response error:", error);
                    res.status(502).end("Bad Gateway");
                });
            }
            else {
                // Pipe response body directly for non-HTML
                proxyRes.pipe(res);
            }
        });
        proxyReq.on("error", (error) => {
            console.error("Proxy request error:", error);
            res.status(502).end("Bad Gateway");
        });
        // Handle request body for POST/PUT/PATCH
        if (req.method !== "GET" && req.method !== "HEAD") {
            if (req.body) {
                if (typeof req.body === "string") {
                    proxyReq.write(req.body);
                }
                else {
                    proxyReq.write(JSON.stringify(req.body));
                }
            }
        }
        proxyReq.end();
    }
    catch (error) {
        console.error("Budget proxy error:", error);
        res.status(502).end("Bad Gateway");
    }
});
//# sourceMappingURL=index.js.map