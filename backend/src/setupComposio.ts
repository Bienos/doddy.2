import { Composio } from "@composio/core";
import { GOOGLE_CALENDAR_REQUESTED_SCOPE } from "./capabilities.js";
import { EVENTS_LIST_TOOL, GOOGLE_CALENDAR_TOOLKIT } from "./providers/composio.js";

/**
 * Owner-only, one-time development setup. Reads COMPOSIO_API_KEY from the environment (never prints it).
 *   npm run setup:composio            list existing Google Calendar auth configs + the tool version to pin
 *   npm run setup:composio -- --create   also create a Composio-managed auth config limited to
 *                                         calendar.events.readonly (free; delete it in the dashboard to undo)
 * Prints the non-secret lines to copy into backend/.env.local.
 */
const apiKey = process.env.COMPOSIO_API_KEY;
if (!apiKey) {
  process.stderr.write("NOT RUN: COMPOSIO_API_KEY is not set in this environment.\n");
  process.exit(2);
}
const create = process.argv.includes("--create");
const composio = new Composio({ apiKey, baseURL: "https://backend.composio.dev", allowTracking: false, disableVersionCheck: true });

try {
  const existing = await composio.authConfigs.list({ toolkit: GOOGLE_CALENDAR_TOOLKIT });
  process.stdout.write(`Existing ${GOOGLE_CALENDAR_TOOLKIT} auth configs: ${existing.items.length}\n`);
  for (const config of existing.items) {
    process.stdout.write(`  ${config.id}  ${config.name}  managed=${config.isComposioManaged}  status=${config.status}\n`);
  }

  let authConfigId: string | null = null;
  if (create) {
    const created = await composio.authConfigs.create(GOOGLE_CALENDAR_TOOLKIT, {
      type: "use_composio_managed_auth",
      name: "Doddy dev - Calendar read-only",
      credentials: { scopes: [GOOGLE_CALENDAR_REQUESTED_SCOPE] },
    });
    authConfigId = created.id;
    process.stdout.write(`Created auth config ${created.id} (managed=${created.isComposioManaged}, scheme=${created.authScheme})\n`);
  }

  const tool = await composio.tools.getRawComposioToolBySlug(EVENTS_LIST_TOOL);
  process.stdout.write(`${EVENTS_LIST_TOOL}: current version ${tool.version ?? "unknown"}; available: ${(tool.availableVersions ?? []).slice(0, 5).join(", ") || "not reported"}\n`);

  process.stdout.write("\nNon-secret lines for backend/.env.local:\n");
  process.stdout.write(`COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID=${authConfigId ?? "<pick one of the ids above>"}\n`);
  process.stdout.write(`COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION=${tool.version ?? "<set manually>"}\n`);
} catch (error) {
  const status = (error as { status?: unknown }).status;
  process.stderr.write(`Composio call failed: ${error instanceof Error ? error.name : "error"}${typeof status === "number" ? ` (HTTP ${status})` : ""}\n`);
  process.exit(1);
}
