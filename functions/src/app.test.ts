import request from "supertest";
import {describe, expect, it} from "vitest";
import {app} from "./app.js";

describe("EcoTrace API", () => {
  it("reports service health", async () => {
    const response = await request(app).get("/health");
    expect(response.status).toBe(200);
    expect(response.body).toEqual({status: "ok", service: "ecotrace-api", version: "1.0.0"});
  });

  it("publishes an OpenAPI document", async () => {
    const response = await request(app).get("/openapi.json");
    expect(response.status).toBe(200);
    expect(response.body.openapi).toBe("3.1.0");
    expect(response.body.paths["/pickup-requests"]).toBeDefined();
    expect(response.body.paths["/dispatch/schedules"]).toBeDefined();
    expect(response.body.paths["/routes/optimize"]).toBeDefined();
    expect(response.body.paths["/collection-centres/{id}/check-ins"]).toBeDefined();
    expect(response.body.paths["/admin/demo-data"]).toBeDefined();
    expect(response.body.paths["/inventory/items"]).toBeDefined();
    expect(response.body.paths["/inventory/items/{id}/assessments"]).toBeDefined();
    expect(response.body.paths["/inventory/items/{id}/traceability"]).toBeDefined();
  });

  it("protects dispatch data with Firebase authentication", async () => {
    const response = await request(app)
      .get("/api/v1/dispatch/schedules")
      .query({from: "2026-07-28T00:00:00Z", to: "2026-07-29T00:00:00Z"});
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects route and GPS data with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/routes");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects collection-centre operations with Firebase authentication", async () => {
    const response = await request(app)
      .get("/api/v1/collection-centres/centre-1/storageSections");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("protects inventory and traceability data with Firebase authentication", async () => {
    const response = await request(app).get("/api/v1/inventory/items");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("rejects protected endpoints without a Firebase token", async () => {
    const response = await request(app).get("/api/v1/me");
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("returns a structured error for unknown routes", async () => {
    const response = await request(app).get("/api/v1/not-real");
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe("not_found");
  });
});
