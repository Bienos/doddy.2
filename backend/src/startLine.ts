import { appliesProductionRules, type Config } from "./config.js";
import type { SigningKeys } from "./signingKeys.js";

/**
 * The line the server writes when it starts listening. Names and modes only; no secrets or IDs. `ownerClaim`
 * (ADR-707) says whether the first iPhone to sign in may claim a server that has no owner yet: `closed` is the
 * live default. `commit` is the running commit (Render sets RENDER_GIT_COMMIT): what is live is read from the
 * logs, which only the people who run the server see, and no longer from `GET /v1/health`. `signingKeyPrevious`
 * is whether DODDY_SESSION_SIGNING_KEY_PREVIOUS is in use, so the person rotating keys can see in the log that the
 * previous key is still held and should be removed once the longest token has run out; never a key or a key id.
 * `productionRules` is whether the production rules of `config.ts` applied to this start (live, host not loopback): a server
 * that started with it true passed the check.
 */
export function listeningLine(
  config: Pick<Config, "host" | "port" | "mode" | "authMode" | "env" | "ownerClaim"> & {
    web: unknown;
    signingKeys?: Pick<SigningKeys, "hasPrevious"> | null;
    accountKeys?: Pick<SigningKeys, "hasPrevious"> | null;
  },
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
    signingKeyPrevious: (config.signingKeys ?? config.accountKeys)?.hasPrevious === true,
    productionRules: appliesProductionRules(config.mode, config.host),
    commit: env.RENDER_GIT_COMMIT?.slice(0, 12) || null,
  });
}

/**
 * What the server writes to stderr when its settings are refused: one line for each problem, so every setting that has to change
 * is on a line of its own. The problems name settings, never values (`config.ts`).
 */
export function notStartingLines(problems: readonly string[]): string {
  return problems.map((problem) => `Not starting. ${problem}`).join("\n");
}
