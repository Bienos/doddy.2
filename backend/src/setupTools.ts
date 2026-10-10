import { Composio } from "@composio/core";
import { CLOUD_TOOLS, TOOLKIT_IDS, TOOLKITS, type ToolkitId } from "./tools/catalog.js";

/**
 * Owner-only, one-time development setup for the online accounts (Gmail, Drive, Notion, Todoist).
 * Reads COMPOSIO_API_KEY from the environment (never prints it).
 *   npm run setup:tools                       list existing auth configs and the tool versions to pin
 *   npm run setup:tools -- --create           also create a Composio-managed auth config per toolkit
 *   npm run setup:tools -- --create gmail     only for the named toolkit(s)
 * Auth configs for Gmail and Drive are limited to the scopes Doddy needs (see tools/catalog.ts).
 * Prints the non-secret lines to copy into backend/.env.local. Creating an auth config is free and
 * is undone by deleting it in the Composio dashboard. NOT RUN in CI: it needs a real project key.
 */
const apiKey = process.env.COMPOSIO_API_KEY;
if (!apiKey) {
  process.stderr.write("NOT RUN: COMPOSIO_API_KEY is not set in this environment.\n");
  process.exit(2);
}
const create = process.argv.includes("--create");
const named = process.argv.slice(2).filter((a) => (TOOLKIT_IDS as readonly string[]).includes(a)) as ToolkitId[];
const chosen = named.length > 0 ? named : [...TOOLKIT_IDS];
const composio = new Composio({ apiKey, baseURL: "https://backend.composio.dev", allowTracking: false, disableVersionCheck: true });

let failed = false;
const lines: string[] = [];
for (const id of chosen) {
  const toolkit = TOOLKITS[id];
  try {
    const existing = await composio.authConfigs.list({ toolkit: toolkit.composioToolkit });
    process.stdout.write(`${toolkit.title}: ${existing.items.length} existing auth config(s)\n`);
    for (const config of existing.items) {
      process.stdout.write(`  ${config.id}  ${config.name}  managed=${config.isComposioManaged}  status=${config.status}\n`);
    }
    let authConfigId: string | null = null;
    if (create) {
      const created = await composio.authConfigs.create(toolkit.composioToolkit, {
        type: "use_composio_managed_auth",
        name: `Doddy dev - ${toolkit.title}`,
        ...(toolkit.requestedScopes.length > 0 ? { credentials: { scopes: [...toolkit.requestedScopes] } } : {}),
      });
      authConfigId = created.id;
      process.stdout.write(`  created ${created.id} (managed=${created.isComposioManaged}, scheme=${created.authScheme})\n`);
    }
    const slug = CLOUD_TOOLS.find((t) => t.toolkit === id)!.composioSlug;
    const tool = await composio.tools.getRawComposioToolBySlug(slug);
    process.stdout.write(`  ${slug}: current version ${tool.version ?? "unknown"}\n`);
    const prefix = `COMPOSIO_${id.toUpperCase()}`;
    lines.push(`${prefix}_AUTH_CONFIG_ID=${authConfigId ?? "<pick one of the ids above>"}`, `${prefix}_TOOLKIT_VERSION=${tool.version ?? "<set manually>"}`);
  } catch (error) {
    failed = true;
    const status = (error as { status?: unknown }).status;
    process.stderr.write(`${toolkit.title}: Composio call failed: ${error instanceof Error ? error.name : "error"}${typeof status === "number" ? ` (HTTP ${status})` : ""}\n`);
  }
}
process.stdout.write("\nNon-secret lines for backend/.env.local:\n");
process.stdout.write(`${lines.join("\n")}\n`);
process.stdout.write("\nAfter connecting, check in the app (Settings > Online accounts) that each account shows Connected, not Needs attention.\nIf it says Doddy couldn't confirm the granted access, Composio is not reporting scopes for that toolkit: do not relax the check.\n");
process.exit(failed ? 1 : 0);
