import Stripe from "stripe";
import {ApiError} from "./errors.js";

let client: Stripe | undefined;

function requestClient(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY?.trim();
  if (!key) throw new ApiError(503, "The Stripe payment gateway is not configured on this server.", "stripe_not_configured");
  client ??= new Stripe(key);
  return client;
}

export interface StripeCheckoutSession {
  id: string;
  url: string;
}

export function createCheckoutSession(input: {
  amountUsdCents: number;
  reference: string;
  successUrl: string;
  cancelUrl: string;
  metadata: Record<string, string>;
}): Promise<StripeCheckoutSession> {
  return requestClient().checkout.sessions.create({
    mode: "payment",
    client_reference_id: input.reference,
    success_url: input.successUrl,
    cancel_url: input.cancelUrl,
    metadata: input.metadata,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "usd",
        unit_amount: input.amountUsdCents,
        product_data: {name: "EcoTrace payment"},
      },
    }],
  }, {idempotencyKey: input.reference}).then((session) => {
    if (!session.url) throw new ApiError(502, "Stripe did not return a checkout URL.", "stripe_gateway_error");
    return {id: session.id, url: session.url};
  });
}

/**
 * Verifies the webhook signature against the raw request body (captured by
 * app.ts specifically for this purpose) and returns the parsed event, or
 * throws if the signature doesn't match — unlike Monime, Stripe signature
 * verification is well-documented and fully supported, so it's enforced
 * rather than treated as an untrusted trigger to re-fetch status.
 */
export function constructWebhookEvent(rawBody: Buffer, signature: string): Stripe.Event {
  const secret = process.env.STRIPE_WEBHOOK_SECRET?.trim();
  if (!secret) throw new ApiError(503, "The Stripe webhook secret is not configured on this server.", "stripe_not_configured");
  try {
    return requestClient().webhooks.constructEvent(rawBody, signature, secret);
  } catch (error) {
    throw new ApiError(400, `Stripe webhook signature verification failed: ${error instanceof Error ? error.message : error}`, "stripe_invalid_signature");
  }
}
