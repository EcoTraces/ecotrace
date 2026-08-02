import request from "supertest";
import {describe, expect, it} from "vitest";
import {app} from "./app.js";

describe("EcoTrace API", () => {
  it("reports service health", async () => {
    const response = await request(app).get("/health");
    expect(response.status).toBe(200);
    expect(response.body).toEqual({status: "ok", service: "ecotrace-api", version: "1.0.0"});
  });

  it("allows Flutter web development origins on changing localhost ports", async () => {
    const response = await request(app)
      .options("/api/v1/pickup-requests")
      .set("Origin", "http://localhost:49172")
      .set("Access-Control-Request-Method", "GET")
      .set("Access-Control-Request-Headers", "authorization,content-type");
    expect(response.status).toBe(204);
    expect(response.headers["access-control-allow-origin"]).toBe("http://localhost:49172");
    expect(response.headers["access-control-allow-headers"]).toContain("Authorization");
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
    expect(response.body.paths["/media/upload-signature"]).toBeDefined();
    expect(response.body.paths["/repairs/{id}/quality-control"]).toBeDefined();
    expect(response.body.paths["/recycling/batches/{id}/verify"]).toBeDefined();
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

  it("protects Cloudinary upload signatures with Firebase authentication", async () => {
    const response = await request(app).post("/api/v1/media/upload-signature").send({scope: "pickups"});
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

  it("returns a structured error for unknown routes", async () => {
    const response = await request(app).get("/api/v1/not-real");
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe("not_found");
  });
});
