import request from "supertest";
import { describe, expect, it } from "vitest";
import { app } from "./app.js";

describe("EcoTrace API", () => {
  it("reports service health", async () => {
    const response = await request(app).get("/health");
    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: "ok",
      service: "ecotrace-api",
      version: "1.0.0",
    });
  });

  it("allows Flutter web development origins on changing localhost ports", async () => {
    const response = await request(app)
      .options("/api/v1/pickup-requests")
      .set("Origin", "http://localhost:49172")
      .set("Access-Control-Request-Method", "GET")
      .set("Access-Control-Request-Headers", "authorization,content-type");
    expect(response.status).toBe(204);
    expect(response.headers["access-control-allow-origin"]).toBe(
      "http://localhost:49172",
    );
    expect(response.headers["access-control-allow-headers"]).toContain(
      "Authorization",
    );
  });

  it("publishes an OpenAPI document", async () => {
    const response = await request(app).get("/openapi.json");
    expect(response.status).toBe(200);
    expect(response.body.openapi).toBe("3.1.0");
    expect(response.body.paths["/pickup-requests"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/estimate-fee"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/{id}"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/{id}/confirm"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/{id}/history"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/{id}/approve"]).toBeDefined();
    expect(response.body.paths["/pickup-requests/{id}/status"]).toBeDefined();
    expect(response.body.paths["/dispatch/schedules"]).toBeDefined();
    expect(response.body.paths["/dispatch/dashboard"]).toBeDefined();
    expect(response.body.paths["/dispatch/availability"]).toBeDefined();
    expect(response.body.paths["/dispatch/nearby-groups"]).toBeDefined();
    expect(response.body.paths["/dispatch/schedules/{id}"]).toBeDefined();
    expect(response.body.paths["/dispatch/schedules/{id}/cancel"]).toBeDefined();
    expect(response.body.paths["/routes/optimize"]).toBeDefined();
    expect(response.body.paths["/routes/{id}/location-history"]).toBeDefined();
    expect(response.body.paths["/routes/{id}/performance"]).toBeDefined();
    expect(response.body.paths["/routing/reports/performance"]).toBeDefined();
    expect(response.body.paths["/routing/service-coverage"]).toBeDefined();
    expect(response.body.paths["/reports/definitions/{id}"]).toBeDefined();
    expect(response.body.paths["/communication/notifications/read-all"]).toBeDefined();
    expect(response.body.paths["/communication/outbox/{id}/retry"]).toBeDefined();
    expect(response.body.paths["/support/tickets/{id}/reopen"]).toBeDefined();
    expect(response.body.paths["/support/agents"]).toBeDefined();
    expect(response.body.paths["/vehicles/{id}/inspections"]).toBeDefined();
    expect(response.body.paths["/vehicles/{id}/fuel-records"]).toBeDefined();
    expect(response.body.paths["/vehicles/{id}/maintenance"]).toBeDefined();
    expect(response.body.paths["/vehicles/{id}/breakdowns"]).toBeDefined();
    expect(response.body.paths["/fleet/alerts"]).toBeDefined();
    expect(response.body.paths["/fleet/utilization"]).toBeDefined();
    expect(
      response.body.paths["/collection-centres/{id}/check-ins"],
    ).toBeDefined();
    expect(response.body.paths["/collection-centres/{id}/dashboard"]).toBeDefined();
    expect(response.body.paths["/collection-centres/{id}/capacityAlerts"]).toBeDefined();
    expect(response.body.paths["/collection-centres/{id}/staff/{userId}"]).toBeDefined();
    expect(response.body.paths["/admin/demo-data"]).toBeDefined();
    expect(response.body.paths["/inventory/items"]).toBeDefined();
    expect(response.body.paths["/inventory/summary"]).toBeDefined();
    expect(response.body.paths["/inventory/export"]).toBeDefined();
    expect(response.body.paths["/inventory/items/{id}"]).toBeDefined();
    expect(response.body.paths["/inventory/items/{id}/images"]).toBeDefined();
    expect(response.body.paths["/inventory/items/{id}/code"]).toBeDefined();
    expect(response.body.paths["/inventory/batches/{id}"]).toBeDefined();
    expect(response.body.paths["/inventory/batches/{id}/items"]).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/assessments"],
    ).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/classification-assist"],
    ).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/assessments/{assessmentId}"],
    ).toBeDefined();
    expect(response.body.paths["/classification/review-queue"]).toBeDefined();
    expect(response.body.paths["/classification/summary"]).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/traceability"],
    ).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/traceability/assign"],
    ).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/traceability/audit"],
    ).toBeDefined();
    expect(
      response.body.paths["/inventory/items/{id}/traceability/certificate"],
    ).toBeDefined();
    expect(response.body.paths["/media/upload-signature"]).toBeDefined();
    expect(response.body.paths["/repairs/{id}/quality-control"]).toBeDefined();
    expect(response.body.paths["/repairs/summary"]).toBeDefined();
    expect(response.body.paths["/repairs/refurbished-inventory"]).toBeDefined();
    expect(response.body.paths["/recycling/batches/{id}/verify"]).toBeDefined();
    expect(response.body.paths["/recovery/lots/{id}/sale"]).toBeDefined();
    expect(response.body.paths["/recovery/lots/{id}/lifecycle"]).toBeDefined();
    expect(response.body.paths["/recovery/reports/revenue"]).toBeDefined();
    expect(
      response.body.paths["/hazardous/records/{id}/disposal"],
    ).toBeDefined();
    expect(
      response.body.paths["/hazardous/records/{id}/compliance-documents"],
    ).toBeDefined();
    expect(
      response.body.paths["/hazardous/records/{id}/certificate"].post,
    ).toBeDefined();
    expect(
      response.body.paths["/logistics/transfers/{id}/receive"],
    ).toBeDefined();
    expect(response.body.paths["/logistics/transfers/drafts"]).toBeDefined();
    expect(response.body.paths["/logistics/transfers/{id}/deliver"]).toBeDefined();
    expect(
      response.body.paths[
        "/logistics/transfers/{id}/exceptions/{exceptionId}/resolve"
      ],
    ).toBeDefined();
    expect(
      response.body.paths["/partners/{id}/documents/{documentId}/verify"],
    ).toBeDefined();
    expect(response.body.paths["/partners/{id}/licence"]).toBeDefined();
    expect(response.body.paths["/partners/{id}/service-records"]).toBeDefined();
    expect(response.body.paths["/partners/{id}/compliance-records"].get).toBeDefined();
    expect(
      response.body.paths["/marketplace/orders/{id}/confirm-receipt"],
    ).toBeDefined();
    expect(response.body.paths["/marketplace/profile"]).toBeDefined();
    expect(response.body.paths["/marketplace/quotations"].get).toBeDefined();
    expect(response.body.paths["/marketplace/orders/{id}/payment-submission"]).toBeDefined();
    expect(response.body.paths["/marketplace/orders/{id}/delivery-events"]).toBeDefined();
    expect(response.body.paths["/marketplace/eligible-devices"]).toBeDefined();
    expect(
      response.body.paths["/donations/requests/{id}/certificate"],
    ).toBeDefined();
    expect(response.body.paths["/donations/eligible-devices"]).toBeDefined();
    expect(response.body.paths["/donations/requests/{id}/follow-ups"].get).toBeDefined();
    expect(response.body.paths["/rewards/redemptions"]).toBeDefined();
    expect(response.body.paths["/rewards/adjustments"]).toBeDefined();
    expect(response.body.paths["/rewards/expiry"]).toBeDefined();
    expect(response.body.paths["/rewards/fraud-flags/{id}"]).toBeDefined();
    expect(response.body.paths["/payments/reconciliation"]).toBeDefined();
    expect(response.body.paths["/impact/comparison"]).toBeDefined();
    expect(response.body.paths["/analytics/operations"]).toBeDefined();
    expect(response.body.paths["/reports/definitions"]).toBeDefined();
    expect(response.body.paths["/communication/preferences"]).toBeDefined();
    expect(response.body.paths["/support/tickets"]).toBeDefined();
    expect(response.body.paths["/compliance/regulatory-bodies"]).toBeDefined();
    expect(response.body.paths["/incidents"]).toBeDefined();
    expect(response.body.paths["/incidents/{id}/investigate"]).toBeDefined();
    expect(response.body.paths["/incidents/{id}/root-cause"]).toBeDefined();
    expect(response.body.paths["/incidents/{id}/follow-ups"]).toBeDefined();
    expect(response.body.paths["/documents"]).toBeDefined();
    expect(response.body.paths["/documents/{id}/archive"]).toBeDefined();
    expect(response.body.paths["/documents/{id}/versions"]).toBeDefined();
    expect(response.body.paths["/documents/{id}/audit"]).toBeDefined();
    expect(response.body.paths["/audit/events"]).toBeDefined();
    expect(response.body.paths["/audit/integrity"]).toBeDefined();
    expect(response.body.paths["/administration/dashboard"]).toBeDefined();
    expect(response.body.paths["/administration/users/{uid}/role"]).toBeDefined();
    expect(response.body.paths["/administration/health"]).toBeDefined();
    expect(response.body.paths["/identity/bootstrap"]).toBeDefined();
    expect(response.body.paths["/identity/sessions"]).toBeDefined();
    expect(response.body.paths["/identity/deletion-request"]).toBeDefined();
    expect(response.body.paths["/organizations"]).toBeDefined();
    expect(response.body.paths["/organizations/{id}/review"]).toBeDefined();
    expect(response.body.paths["/organizations/{id}/members/{uid}"]).toBeDefined();
    expect(response.body.paths["/organizations/{id}/documents/{documentId}/verify"]).toBeDefined();
  });

  it("protects audit records with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/audit/events");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects administration with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/administration/dashboard");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects identity profiles with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/identity/profile");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects identity sessions with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/identity/sessions");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects organization profiles with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/organizations");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects organization staff management with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/organizations/org-1/members");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects pickup fee estimates with Firebase authentication", async () => {
    const response = await request(app)
      .post("/api/v1/pickup-requests/estimate-fee")
      .send({quantity: 1, estimatedWeight: 5, urgent: false});
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects pickup tracking history with Firebase authentication", async () => {
    const response = await request(app).get(
      "/api/v1/pickup-requests/pickup-1/history",
    );
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects compliance workflows with Firebase authentication", async () => {
    const response = await request(app).get(
      "/api/v1/compliance/regulatory-bodies",
    );
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects dispatch data with Firebase authentication", async () => {
    const response = await request(app)
      .get("/api/v1/dispatch/schedules")
      .query({ from: "2026-07-28T00:00:00Z", to: "2026-07-29T00:00:00Z" });
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects dispatch availability with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/dispatch/availability");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects route and GPS data with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/routes");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects collection-centre operations with Firebase authentication", async () => {
    const response = await request(app).get(
      "/api/v1/collection-centres/centre-1/storageSections",
    );
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects inventory and traceability data with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/inventory/items");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects traceability certificates with Firebase authentication", async () => {
    const response = await request(app).get(
      "/api/v1/inventory/items/item-1/traceability/certificate",
    );
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects inventory exports with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/inventory/export");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects inventory QR metadata with Firebase authentication", async () => {
    const response = await request(app).get(
      "/api/v1/inventory/items/item-1/code",
    );
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects assisted classification with Firebase authentication", async () => {
    const response = await request(app)
      .post("/api/v1/inventory/items/item-1/classification-assist")
      .send({});
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects the classification review queue with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/classification/review-queue");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("rejects protected endpoints without a Firebase token", async () => {
    const response = await request(app).get("/api/v1/me");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects Cloudinary upload signatures with Firebase authentication", async () => {
    const response = await request(app)
      .post("/api/v1/media/upload-signature")
      .send({ scope: "pickups" });
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects repair workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/repairs");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects recycling workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/recycling/batches");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects resource recovery workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/recovery/lots");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects hazardous waste workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/hazardous/records");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects reverse logistics workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/logistics/transfers");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects partner management workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/partners");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects marketplace order workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/marketplace/orders");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects donation workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/donations/requests");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects reward workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/rewards/wallet");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects payment workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/payments/transactions");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects environmental impact workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/impact/summary");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects analytics workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/analytics/overview");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects incident workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/incidents");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects document workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/documents");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects compliance workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/compliance/documents");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects emergency contacts with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/safety/emergency-contacts");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects fleet management workflows with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/fleet/alerts");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("returns a structured error for unknown routes", async () => {
    const response = await request(app).get("/api/v1/not-real");
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe("not_found");
  });
});
