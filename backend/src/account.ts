import type { ConnectedAppsService } from "./service.js";
import type { Store } from "./store.js";
import type { CloudToolsService } from "./tools/service.js";

/** What `DELETE /v1/account` answers: what was deleted, and how each grant at the provider went. */
export interface AccountDeletion {
  deleted: Record<string, number>;
  remoteConnections: { removed: number; queued: number };
}

/**
 * Deletes everything the backend holds for one user. The rows go in one transaction that reads
 * them back (Store.deleteAccount); the user's connections were queued for removal in that same
 * transaction, so a grant whose removal fails here is retried by the hourly sweep. Only after the
 * rows are verified gone does the caller get a 200.
 */
export class AccountService {
  constructor(
    private readonly deps: { store: Store; service: ConnectedAppsService; tools: CloudToolsService; now?: () => number; log?: (line: Record<string, unknown>) => void },
  ) {}

  async deleteAll(userId: string): Promise<AccountDeletion> {
    const { deleted, queued } = await this.deps.store.deleteAccount(userId, this.deps.now?.() ?? Date.now());
    const calendar = await this.deps.service.removeQueued(queued.filter((q) => q.provider === "google_calendar"));
    const tools = await this.deps.tools.removeQueued(queued.filter((q) => q.provider !== "google_calendar"));
    const remoteConnections = { removed: calendar.removed + tools.removed, queued: calendar.queued + tools.queued };
    this.deps.log?.({ level: "info", event: "account_deleted", ...remoteConnections });
    return { deleted, remoteConnections };
  }
}
