import {app} from "./app.js";

const port = Number.parseInt(process.env.PORT ?? "10000", 10);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port number.");
}

const server = app.listen(port, "0.0.0.0", () => {
  console.log(`EcoTrace API listening on 0.0.0.0:${port}`);
});

function shutdown(signal: string) {
  console.log(`${signal} received; closing the EcoTrace API.`);
  server.close((error) => {
    if (error) {
      console.error("Failed to close the HTTP server cleanly.", error);
      process.exit(1);
    }
    process.exit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
