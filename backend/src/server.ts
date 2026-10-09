import { buildApp } from "./app.js";
import { ConfigError, loadConfig } from "./config.js";

try {
  const config = loadConfig();
  const { server, store } = buildApp(config);
  server.listen(config.port, config.host, () => {
    // Names and modes only; no secrets or IDs.
    process.stdout.write(
      `${JSON.stringify({ level: "info", event: "listening", host: config.host, port: config.port, mode: config.mode, auth: config.authMode, env: config.env })}\n`,
    );
    if (config.mode === "mock") {
      process.stdout.write(
        "MOCK MODE: demo data only, no Google or Composio calls. Loopback test tokens: dev-user-a, dev-user-b\n",
      );
    }
  });
  const stop = () => server.close(() => store.close());
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
} catch (error) {
  if (error instanceof ConfigError) {
    process.stderr.write(`Not starting. ${error.message}\n`);
    process.exit(78);
  }
  throw error;
}
