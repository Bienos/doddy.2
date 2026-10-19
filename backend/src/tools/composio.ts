import { Composio } from "@composio/core";
import type { ToolkitSettings } from "../config.js";
import { ProviderError } from "../errors.js";
import { extractScopes, guard, mapStatus, removeComposioConnection } from "../providers/composioShared.js";
import type { ProviderConnection } from "../providers/types.js";
import { type ToolkitId, TOOLKIT_IDS, TOOLKITS } from "./catalog.js";
import type { ExecuteCall, ExecuteResult, ToolsProvider } from "./provider.js";

/**
 * Composio adapter for online-account tools, written against @composio/core 0.22.0 like the
 * calendar adapter. Only this file and tools/catalog.ts name Composio tool slugs. The slugs in the
 * catalog were read from Composio's tool schemas; none has been run against a real account.
 */
const COMPOSIO_API_BASE_URL = "https://backend.composio.dev";

export type ComposioToolsLike = Pick<Composio, "connectedAccounts" | "tools">;

export class ComposioToolsProvider implements ToolsProvider {
  readonly mode = "live" as const;
  private readonly client: ComposioToolsLike;

  constructor(
    apiKey: string,
    private readonly settings: Partial<Record<ToolkitId, ToolkitSettings>>,
    client?: ComposioToolsLike,
  ) {
    this.client =
      client ??
      new Composio({
        apiKey,
        // Pinned so neither COMPOSIO_BASE_URL nor a ~/.composio user file can redirect the project key.
        baseURL: COMPOSIO_API_BASE_URL,
        allowTracking: false,
        disableVersionCheck: true,
        toolkitVersions: Object.fromEntries(
          TOOLKIT_IDS.flatMap((id) => {
            const s = settings[id];
            return s ? [[TOOLKITS[id].composioToolkit, s.toolkitVersion]] : [];
          }),
        ),
      });
  }

  isConfigured(toolkit: ToolkitId): boolean {
    return this.settings[toolkit] !== undefined;
  }

  authConfigId(toolkit: ToolkitId): string {
    const s = this.settings[toolkit];
    if (!s) throw new ProviderError("provider_unavailable");
    return s.authConfigId;
  }

  narrowAuthConfigId(toolkit: ToolkitId): string | null {
    return this.settings[toolkit]?.narrowAuthConfigId ?? null;
  }

  /** Only an auth config this server has set up for the toolkit; anything else is refused. */
  private knownAuthConfig(toolkit: ToolkitId, authConfigId: string): string {
    if (authConfigId !== this.authConfigId(toolkit) && authConfigId !== this.narrowAuthConfigId(toolkit)) {
      throw new ProviderError("provider_unavailable");
    }
    return authConfigId;
  }

  async createConnectionLink(input: { toolkit: ToolkitId; authConfigId: string; composioUserId: string; callbackUrl: string; signal: AbortSignal }) {
    const request = await guard(() =>
      this.client.connectedAccounts.link(
        input.composioUserId,
        this.knownAuthConfig(input.toolkit, input.authConfigId),
        { callbackUrl: input.callbackUrl, allowMultiple: false },
        { signal: input.signal },
      ),
    );
    if (!request.redirectUrl) throw new ProviderError("provider_unavailable");
    return { pendingConnectionId: request.id, redirectUrl: request.redirectUrl };
  }

  async completeVerifiedAuth(input: { composioUserId: string; sessionUri: string; signal: AbortSignal }) {
    const result = await guard(() =>
      this.client.connectedAccounts.completeAuth({ userId: input.composioUserId, sessionUri: input.sessionUri }, { signal: input.signal }),
    );
    return { connectionId: result.connectedAccountId, toolkitSlug: result.toolkitSlug };
  }

  async completeMock(): Promise<{ connectionId: string } | null> {
    throw new ProviderError("provider_unavailable");
  }

  async getConnection(input: { connectionId: string; signal: AbortSignal }): Promise<ProviderConnection> {
    const account = await guard(() => this.client.connectedAccounts.get(input.connectionId, { signal: input.signal }));
    return {
      id: account.id,
      status: mapStatus(account.status, account.isDisabled),
      toolkitSlug: account.toolkit.slug,
      authConfigId: account.authConfig.id,
      grantedScopes: extractScopes(account.state),
    };
  }

  async isOwnedBy(input: { toolkit: ToolkitId; authConfigId: string; connectionId: string; composioUserId: string; signal: AbortSignal }): Promise<boolean> {
    const page = await guard(() =>
      this.client.connectedAccounts.list(
        {
          userIds: [input.composioUserId],
          authConfigIds: [this.knownAuthConfig(input.toolkit, input.authConfigId)],
          toolkitSlugs: [TOOLKITS[input.toolkit].composioToolkit],
          limit: 20,
        },
        { signal: input.signal },
      ),
    );
    return page.items.some((item) => item.id === input.connectionId);
  }

  async execute(call: ExecuteCall): Promise<ExecuteResult> {
    const response = await guard(() =>
      this.client.tools.execute(
        call.slug,
        {
          userId: call.composioUserId,
          connectedAccountId: call.connectionId,
          version: this.settings[call.toolkit]?.toolkitVersion ?? "",
          arguments: call.arguments,
        },
        { signal: call.signal },
      ),
      { execute: true },
    );
    return { raw: { successful: response.successful, error: response.error, data: response.data }, providerReference: response.logId ?? null };
  }

  async removeConnection(input: { connectionId: string; signal: AbortSignal }) {
    return removeComposioConnection(this.client, input.connectionId, input.signal);
  }

}
