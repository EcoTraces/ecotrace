import cors from "cors";
import express from "express";
import {errorHandler, notFound} from "./errors.js";
import {openApiDocument} from "./openapi.js";
import routes from "./routes.js";
import "./types.js";

export const app = express();
const configuredOrigins = (process.env.API_ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

app.disable("x-powered-by");
app.use(cors({origin: configuredOrigins.length === 0 ? true : configuredOrigins}));
app.use(express.json({limit: "1mb"}));

app.get("/health", (_request, response) => response.json({status: "ok", service: "ecotrace-api", version: "1.0.0"}));
app.get("/openapi.json", (_request, response) => response.json(openApiDocument));
app.use("/api/v1", routes);
app.use(notFound);
app.use(errorHandler);
