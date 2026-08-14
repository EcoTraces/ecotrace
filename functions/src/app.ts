import cors from "cors";
import express from "express";
import swaggerUi from "swagger-ui-express";
import {errorHandler, notFound} from "./errors.js";
import {openApiDocument} from "./openapi.js";
import routes from "./routes.js";
import "./types.js";

export const app = express();
const configuredOrigins = (process.env.API_ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);
const localDevelopmentOrigin = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function allowedOrigin(origin: string | undefined, callback: (error: Error | null, allowed?: boolean) => void) {
  if (!origin || localDevelopmentOrigin.test(origin) || configuredOrigins.includes(origin)) {
    callback(null, true);
    return;
  }
  if (configuredOrigins.length === 0) {
    callback(null, true);
    return;
  }
  callback(null, false);
}

app.disable("x-powered-by");
app.use(cors({origin: allowedOrigin, methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"], allowedHeaders: ["Authorization", "Content-Type", "X-EcoTrace-Event-Key"]}));
// Captures the exact raw bytes alongside the parsed body so a webhook signature check
// (e.g. Monime's) can be added later without needing a second, route-specific body parser.
app.use(express.json({limit: "1mb", verify: (request, _response, buffer) => { (request as express.Request & {rawBody?: Buffer}).rawBody = buffer; }}));

app.get("/", (_request, response) => response.json({status: "ok", service: "ecotrace-api", version: "1.0.0", message: "Welcome to EcoTrace API"}));
app.get("/health", (_request, response) => response.json({status: "ok", service: "ecotrace-api", version: "1.0.0"}));
app.get("/openapi.json", (_request, response) => response.json(openApiDocument));
app.use("/docs", swaggerUi.serve, swaggerUi.setup(openApiDocument));
app.use("/api/v1", routes);
app.use(notFound);
app.use(errorHandler);
