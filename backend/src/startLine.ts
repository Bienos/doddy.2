import type { Config } from "./config.js";

/**
 * The line the server writes when it starts listening. Names and modes only; no secrets or IDs. `ownerClaim`
 * (ADR-707) says whether the first iPhone to sign in may claim a server that has no owner yet: `closed` is the
 * live default. `commit` is the running commit (Render sets RENDER_GIT_COMMIT): what is live is read from the
 * logs, which only the people who run the server see, and no longer from `GET /v1/health`.
 */
export function listeningLine(
  config: Pick<Config, "host" | "port" | "mode" | "authMode" | "env" | "ownerClaim"> & { web: unknown },
  storeKind: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return JSON.stringify({
    level: "info",
    event: "listening",
    host: config.host,
    port: config.port,
    mode: config.mode,
    auth: config.authMode,
    env: config.env,
    store: storeKind,
    web: config.web ? "on" : "off",
    ownerClaim: config.ownerClaim,
    commit: env.RENDER_GIT_COMMIT?.slice(0, 12) || null,
  });
}
