import {ApiError} from "./errors.js";

// Provider IDs are Monime's own identifiers, confirmed live against the sandbox
// API (docs enumerate only these two for mobile money as of this integration).
export const MONIME_MOMO_PROVIDERS = {orangeMoney: "m17", afrimoney: "m18"} as const;
export type MonimeMomoProviderKey = keyof typeof MONIME_MOMO_PROVIDERS;

interface MonimeAmount { currency: string; value: number; }

export interface MonimePaymentCode {
  id: string;
  status: "pending" | "processing" | "completed" | "expired" | "cancelled";
  amount: MonimeAmount;
  ussdCode: string;
  authorizedProviders?: string[];
  authorizedPhoneNumber?: string | null;
  expireTime: string;
  processedPaymentData?: {
    channelData?: {providerId?: string; accountId?: string; reference?: string};
    financialTransactionReference?: string;
    paymentId?: string;
    orderNumber?: string;
  } | null;
  metadata?: Record<string, string> | null;
}

function baseUrl(): string {
  return (process.env.MONIME_API_BASE_URL?.trim() || "https://api.monime.io").replace(/\/$/, "");
}

function requestHeaders(idempotencyKey?: string): Record<string, string> {
  const token = process.env.MONIME_ACCESS_TOKEN?.trim();
  const spaceId = process.env.MONIME_SPACE_ID?.trim();
  if (!token || !spaceId) throw new ApiError(503, "The Monime payment gateway is not configured on this server.", "monime_not_configured");
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    "Monime-Space-Id": spaceId,
    "Content-Type": "application/json",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  return headers;
}

async function call<T>(path: string, init: RequestInit, idempotencyKey?: string): Promise<T> {
  const response = await fetch(`${baseUrl()}${path}`, {
    ...init,
    headers: {...requestHeaders(idempotencyKey), ...(init.headers as Record<string, string> | undefined)},
    signal: AbortSignal.timeout(20_000),
  });
  const body = (await response.json().catch(() => null)) as {success?: boolean; result?: T; error?: {message?: string}} | null;
  if (!response.ok || !body?.success) {
    throw new ApiError(502, `Monime payment gateway error: ${body?.error?.message || `HTTP ${response.status}`}`, "monime_gateway_error");
  }
  return body.result as T;
}

export function createPaymentCode(input: {
  name: string;
  amountMinorUnits: number;
  currency: string;
  providerId: string;
  durationMinutes: number;
  reference: string;
  metadata: Record<string, string>;
}, idempotencyKey: string): Promise<MonimePaymentCode> {
  // Monime rejects a request that sets both `authorizedProviders` and
  // `authorizedPhoneNumber` ("A payment provider must not be set when a
  // paying phone number is specified.") — confirmed live against the
  // sandbox, not documented anywhere in Monime's published schema. We
  // restrict by provider (network) only, not by a specific phone number:
  // besides the fields being mutually exclusive, Monime's own USSD
  // Simulator has no way to specify an arbitrary paying number (only a
  // network selector), so a phone-locked code can never be completed
  // through it. The phone number the user enters is still collected and
  // stored on our side for the payment record; it just isn't sent to
  // Monime as a restriction.
  return call<MonimePaymentCode>("/v1/payment-codes", {
    method: "POST",
    body: JSON.stringify({
      name: input.name,
      amount: {currency: input.currency, value: input.amountMinorUnits},
      duration: `${input.durationMinutes}m`,
      authorizedProviders: [input.providerId],
      reference: input.reference,
      metadata: input.metadata,
    }),
  }, idempotencyKey);
}

export function getPaymentCode(paymentCodeId: string): Promise<MonimePaymentCode> {
  return call<MonimePaymentCode>(`/v1/payment-codes/${encodeURIComponent(paymentCodeId)}`, {method: "GET"});
}
