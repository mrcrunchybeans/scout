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

function isExpiringSoon(d: Date | null, now = new Date()) {
  if (!d) return false;
  const days = Math.floor((d.getTime() - now.getTime()) / (24 * 3600 * 1000));
  return days >= 0 && days <= EXPIRING_SOON_DAYS;
}

function daysSince(d?: admin.firestore.Timestamp | null, now = new Date()) {
  if (!d) return Infinity;
  const dd = d.toDate();
  return Math.floor((now.getTime() - dd.getTime()) / (24 * 3600 * 1000));
}

async function recomputeItemAggregates(itemId: string) {
  const itemRef = db.collection("items").doc(itemId);
  const [itemSnap, lotsSnap] = await Promise.all([
    itemRef.get(),
    itemRef.collection("lots").get(),
  ]);

  if (!itemSnap.exists) return;

  const item = itemSnap.data() || {};
  const minQty = Number(item.minQty || 0);
  const lastUsedAt = item.lastUsedAt as admin.firestore.Timestamp | null | undefined;

  // Sum remaining from lots & compute earliest effective expiration
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
    earliestExpiresAt: earliest ? admin.firestore.Timestamp.fromDate(earliest) : null,
  };

  await itemRef.set(patch, {merge: true});
}

// ---------- Triggers (v2) ----------

// 1) usage_logs onCreate: update item's lastUsedAt (max) and recompute aggregates/flags.
// NOTE: We do NOT change lot quantities here; client adjusts lots, server recomputes totals.
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

      const current = itemSnap.get("lastUsedAt") as admin.firestore.Timestamp | null | undefined;
      if (usedAt && (!current || usedAt.toMillis() > current.toMillis())) {
        tx.set(itemRef, {lastUsedAt: usedAt}, {merge: true});
      }
    });

    await recomputeItemAggregates(itemId);
  }
);

// 2) lots onWrite: whenever lots change, recompute aggregates for the parent item.
export const onLotWrite = onDocumentWritten(
  "items/{itemId}/lots/{lotId}",
  async (event) => {
    const itemId = event.params.itemId as string;
    // event.data is Change<DocumentSnapshot> | undefined — not needed here, we recompute from scratch
    await recomputeItemAggregates(itemId);
  }
);

// 3) Daily job: refresh flagExpiringSoon (and sanity recompute aggregates).
export const nightlyExpirySweep = onSchedule("every day 02:15", async () => {
  const PAGE = 300;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;

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
