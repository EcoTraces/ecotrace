import {ApiError} from "./errors.js";

function baseUrl(): string {
  return (process.env.PAYPAL_API_BASE_URL?.trim() || "https://api-m.sandbox.paypal.com").replace(/\/$/, "");
}

function credentials(): {clientId: string; clientSecret: string} {
  const clientId = process.env.PAYPAL_CLIENT_ID?.trim();
  const clientSecret = process.env.PAYPAL_CLIENT_SECRET?.trim();
  if (!clientId || !clientSecret) throw new ApiError(503, "The PayPal payment gateway is not configured on this server.", "paypal_not_configured");
  return {clientId, clientSecret};
}

let cachedToken: {value: string; expiresAt: number} | undefined;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) return cachedToken.value;
  const {clientId, clientSecret} = credentials();
  const response = await fetch(`${baseUrl()}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
    signal: AbortSignal.timeout(20_000),
  });
  const body = (await response.json().catch(() => null)) as {access_token?: string; expires_in?: number; error_description?: string} | null;
  if (!response.ok || !body?.access_token) {
    throw new ApiError(502, `PayPal authorization failed: ${body?.error_description || `HTTP ${response.status}`}`, "paypal_gateway_error");
  }
  cachedToken = {value: body.access_token, expiresAt: Date.now() + (body.expires_in ?? 300) * 1000};
  return cachedToken.value;
}

async function call<T>(path: string, init: RequestInit): Promise<T> {
  const token = await accessToken();
  const response = await fetch(`${baseUrl()}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init.headers as Record<string, string> | undefined),
    },
    signal: AbortSignal.timeout(20_000),
  });
  const body = (await response.json().catch(() => null)) as (T & {details?: {issue?: string}[]; message?: string}) | null;
  if (!response.ok) {
    if (response.status === 422 && body?.details?.some((detail) => detail.issue === "ORDER_ALREADY_CAPTURED")) {
      throw new PayPalAlreadyCapturedError();
    }
    throw new ApiError(502, `PayPal gateway error: ${body?.message || `HTTP ${response.status}`}`, "paypal_gateway_error");
  }
  return body as T;
}

/** Thrown when capturing an order PayPal has already captured — the caller
 * should treat this as an idempotent success rather than a failure, since it
 * only happens on a duplicate capture attempt (page reload, retry). */
export class PayPalAlreadyCapturedError extends Error {
  constructor() {
    super("This order has already been captured.");
  }
}

export interface PayPalOrder {
  id: string;
  approveUrl: string;
}

export async function createOrder(input: {
  amountUsdCents: number;
  reference: string;
  returnUrl: string;
  cancelUrl: string;
}): Promise<PayPalOrder> {
  const order = await call<{id: string; links?: {rel: string; href: string}[]}>("/v2/checkout/orders", {
    method: "POST",
    body: JSON.stringify({
      intent: "CAPTURE",
      purchase_units: [{
        reference_id: input.reference,
        amount: {currency_code: "USD", value: (input.amountUsdCents / 100).toFixed(2)},
      }],
      application_context: {
        return_url: input.returnUrl,
        cancel_url: input.cancelUrl,
        user_action: "PAY_NOW",
      },
    }),
  });
  const approveUrl = order.links?.find((link) => link.rel === "approve")?.href;
  if (!approveUrl) throw new ApiError(502, "PayPal did not return an approval URL.", "paypal_gateway_error");
  return {id: order.id, approveUrl};
}

export interface PayPalCaptureResult {
  status: string;
  captureId: string;
}

export async function captureOrder(orderId: string): Promise<PayPalCaptureResult> {
  const result = await call<{
    status: string;
    purchase_units?: {payments?: {captures?: {id: string}[]}}[];
  }>(`/v2/checkout/orders/${encodeURIComponent(orderId)}/capture`, {method: "POST", body: "{}"});
  const captureId = result.purchase_units?.[0]?.payments?.captures?.[0]?.id ?? "";
  return {status: result.status, captureId};
}

export async function getOrder(orderId: string): Promise<{status: string}> {
  return call<{status: string}>(`/v2/checkout/orders/${encodeURIComponent(orderId)}`, {method: "GET"});
}
