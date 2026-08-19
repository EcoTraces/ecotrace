import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "./firebase.js";

// Monime payment codes self-expire and their webhook (called by Monime
// itself) reports that. Stripe Checkout Sessions similarly emit
// checkout.session.expired. PayPal orders are not guaranteed to reliably
// self-report abandonment the same way -- if a payer approves on PayPal but
// closes the tab, loses network, or simply never returns before completing
// checkout, nothing else in this app would ever move that transaction out of
// "pending". This is a uniform, gateway-agnostic safety net rather than
// relying on exact webhook-event guarantees per provider.
const STALE_AFTER_MS = 3 * 60 * 60 * 1000; // PayPal's own order-expiry window.

async function expireStalePayments(): Promise<void> {
  const cutoff = Timestamp.fromMillis(Date.now() - STALE_AFTER_MS);
  const stale = await db.collection("paymentTransactions")
    .where("status", "==", "pending")
    .where("gateway", "in", ["stripe", "paypal"])
    .where("createdAt", "<=", cutoff)
    .limit(200)
    .get();
  for (const doc of stale.docs) {
    await doc.ref.update({
      status: "failed",
      providerStatus: "expired",
      failureReason: "Payment session expired without completion.",
      failedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

export const expireStalePaymentTransactions = onSchedule(
  {schedule: "every 60 minutes", region: "europe-west1"},
  async () => {
    await expireStalePayments();
  },
);
