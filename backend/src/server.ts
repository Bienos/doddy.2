import { buildApp } from "./app.js";
import { ConfigError, loadConfig } from "./config.js";
import { listeningLine } from "./startLine.js";

try {
  const config = loadConfig();
  const { server, store } = await buildApp(config);
  server.listen(config.port, config.host, () => {
    process.stdout.write(`${listeningLine(config, store.db.kind)}\n`);
    if (config.mode === "mock") {
      process.stdout.write(
        "MOCK MODE: demo data only, no Google or Composio calls. Loopback test tokens: dev-user-a, dev-user-b\n",
      );
    }
  });
  process.on("unhandledRejection", (reason) => {
    process.stderr.write(`${JSON.stringify({ level: "error", event: "unhandledRejection", kind: reason instanceof Error ? reason.name : typeof reason })}\n`);
  });
  const stop = () => server.close(() => void store.close().catch(() => {}));
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
} catch (error) {
  if (error instanceof ConfigError) {
    process.stderr.write(`Not starting. ${error.message}\n`);
    process.exit(78);
  }
  throw error;
}
