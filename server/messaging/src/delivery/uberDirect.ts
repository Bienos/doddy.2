// Uber Direct, the person-to-person delivery API (decision 2026-11-12-uber-direct-deliveries).
// Endpoints: https://developer.uber.com/docs/deliveries/getting-started (classic "DaaS" paths under
// /v1/customers/{customer_id}/…). Sign-in is OAuth client credentials with the eats.deliveries scope;
// the secret stays on this server and is never sent to the iPhone or written to a log.

/** A street address as Uber reads it: a JSON string with these keys. */
export interface UberAddress {
  street: string;
  apartment?: string;
  city: string;
  postcode: string;
  /** ISO 3166-1 alpha-2, upper case ("PL"). */
  country: string;
}

export interface UberItem { name: string; quantity: number; size: "small" | "medium" | "large" }

export interface QuoteRequest {
  pickupAddress: UberAddress;
  pickupPhone: string;
  dropoffAddress: UberAddress;
  dropoffPhone: string;
}

export interface Quote {
  quoteId: string;
  /** In the currency's minor units (grosze for PLN). */
  fee: number;
  /** Upper case ISO 4217 ("PLN"). */
  currency: string;
  expiresAt: Date;
  dropoffEta: Date | null;
}

export interface CreateRequest {
  quoteId: string;
  pickupName: string;
  pickupAddress: UberAddress;
  pickupPhone: string;
  dropoffName: string;
  dropoffAddress: UberAddress;
  dropoffPhone: string;
  dropoffNotes: string;
  items: UberItem[];
  /** Doddy's own id for the delivery: Uber's idempotency_key and external_id, so a repeat can't book twice. */
  doddyId: string;
}

export interface UberDelivery {
  id: string;
  status: string;
  trackingUrl: string | null;
  fee: number | null;
  currency: string | null;
  liveMode: boolean | null;
  externalId: string | null;
}

/**
 * - ok:        Uber answered with what was asked for.
 * - rejected:  Uber refused for good (bad address, outside the area, not allowed…). Nothing was created.
 * - transient: Uber refused before accepting (429, 503 with no body). Nothing was created; safe to try later.
 * - unknown:   the request may or may not have gone through (timeout, dropped connection, 500, 502, 504).
 *              A create that ends here is never sent again on its own (DOD-08, DOD-09).
 */
export type UberOutcome<T> =
  | { kind: "ok"; value: T }
  | { kind: "rejected"; code: string }
  | { kind: "transient"; code: string }
  | { kind: "unknown"; code: string };

export interface DeliveryProvider {
  quote(req: QuoteRequest): Promise<UberOutcome<Quote>>;
  create(req: CreateRequest): Promise<UberOutcome<UberDelivery>>;
  get(uberId: string): Promise<UberOutcome<UberDelivery>>;
  cancel(uberId: string): Promise<UberOutcome<UberDelivery>>;
  /** Uber's most recent deliveries for this account, to settle a create whose answer was lost. */
  findByExternalId(doddyId: string): Promise<UberOutcome<UberDelivery | null>>;
}

export interface UberDirectConfig {
  clientId: string;
  clientSecret: string;
  customerId: string;
  /**
   * "test": the credentials are Uber's sandbox ones; every delivery asks for Uber's simulated courier
   * (robo_courier_specification auto), and a delivery Uber marks live_mode is cancelled at once.
   * "live": real couriers, real charges to the Uber account.
   */
  mode: "test" | "live";
  apiBase?: string;
  authUrl?: string;
}

type Fetch = typeof fetch;
const TIMEOUT_MS = 15_000;

/** Uber's structured address, as the JSON string its API takes. Poland has no state; Uber's examples send one, so it is empty. */
export function uberAddressJson(a: UberAddress): string {
  return JSON.stringify({
    street_address: a.apartment ? [a.street, a.apartment] : [a.street],
    city: a.city,
    state: "",
    zip_code: a.postcode,
    country: a.country,
  });
}

/** What a 4xx/5xx body says, as a short code safe to store and log (never the body itself). */
function codeFrom(body: unknown, status: number): string {
  const raw = body && typeof body === "object" ? (body as { code?: unknown }).code : undefined;
  return typeof raw === "string" && /^[a-z0-9_.-]{1,64}$/i.test(raw) ? raw.toLowerCase() : `http_${status}`;
}

function parseDelivery(body: unknown): UberDelivery | undefined {
  if (!body || typeof body !== "object") return undefined;
  const b = body as Record<string, unknown>;
  if (typeof b.id !== "string" || typeof b.status !== "string") return undefined;
  return {
    id: b.id,
    status: b.status,
    trackingUrl: typeof b.tracking_url === "string" && b.tracking_url.startsWith("https://") ? b.tracking_url : null,
    fee: Number.isInteger(b.fee) ? b.fee as number : null,
    currency: typeof b.currency === "string" ? b.currency.toUpperCase() : null,
    liveMode: typeof b.live_mode === "boolean" ? b.live_mode : null,
    externalId: typeof b.external_id === "string" ? b.external_id : null,
  };
}

export class UberDirectClient implements DeliveryProvider {
  private token: { value: string; until: number } | undefined;
  private readonly api: string;
  private readonly auth: string;

  constructor(private readonly config: UberDirectConfig, private readonly fetchImpl: Fetch = fetch,
    private readonly now: () => number = Date.now) {
    this.api = (config.apiBase ?? "https://api.uber.com").replace(/\/$/, "");
    this.auth = config.authUrl ?? "https://auth.uber.com/oauth/v2/token";
  }

  get mode(): "test" | "live" { return this.config.mode; }

  private base(): string {
    return `${this.api}/v1/customers/${encodeURIComponent(this.config.customerId)}`;
  }

  /** A cached access token (Uber's last 30 days); undefined when Uber wouldn't give one. */
  private async accessToken(force = false): Promise<string | undefined> {
    if (!force && this.token && this.token.until > this.now()) return this.token.value;
    try {
      const res = await this.fetchImpl(this.auth, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: this.config.clientId, client_secret: this.config.clientSecret,
          grant_type: "client_credentials", scope: "eats.deliveries",
        }).toString(),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (!res.ok) return undefined;
      const body = await res.json() as { access_token?: unknown; expires_in?: unknown };
      if (typeof body.access_token !== "string") return undefined;
      const seconds = typeof body.expires_in === "number" ? body.expires_in : 3600;
      // Renewed five minutes early, so a call never starts with a token about to lapse.
      this.token = { value: body.access_token, until: this.now() + Math.max(60, seconds - 300) * 1000 };
      return this.token.value;
    } catch {
      return undefined;
    }
  }

  /**
   * One request. A 401 means Uber didn't accept it, so the token is renewed and the request sent once
   * more; anything after Uber may have acted on it is never sent again here.
   */
  private async request(method: "GET" | "POST", path: string, body?: object): Promise<UberOutcome<unknown>> {
    for (const force of [false, true]) {
      const token = await this.accessToken(force);
      if (!token) return { kind: "transient", code: "auth_unavailable" };
      let res: Response;
      try {
        res = await this.fetchImpl(this.base() + path, {
          method,
          headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
          body: body ? JSON.stringify(body) : undefined,
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch (err) {
        // Sent but no answer: Uber may have acted on it.
        return { kind: "unknown", code: (err as Error).name === "TimeoutError" ? "timeout" : "network" };
      }
      let parsed: unknown;
      try { parsed = await res.json(); } catch { parsed = undefined; }
      if (res.ok) return { kind: "ok", value: parsed };
      if (res.status === 401 && !force) { this.token = undefined; continue; }
      if (res.status === 429) return { kind: "transient", code: "rate_limited" };
      if (res.status === 503 && parsed === undefined) return { kind: "transient", code: "http_503" };
      if (res.status >= 500) return { kind: "unknown", code: `http_${res.status}` };
      return { kind: "rejected", code: codeFrom(parsed, res.status) };
    }
    return { kind: "rejected", code: "unauthorized" };
  }

  async quote(req: QuoteRequest): Promise<UberOutcome<Quote>> {
    const r = await this.request("POST", "/delivery_quotes", {
      pickup_address: uberAddressJson(req.pickupAddress),
      dropoff_address: uberAddressJson(req.dropoffAddress),
      pickup_phone_number: req.pickupPhone,
      dropoff_phone_number: req.dropoffPhone,
    });
    // A quote books nothing, so an unclear answer is only "couldn't get a price".
    if (r.kind !== "ok") return r.kind === "unknown" ? { kind: "transient", code: r.code } : r;
    const b = r.value as Record<string, unknown> | undefined;
    const expires = typeof b?.expires === "string" ? new Date(b.expires) : undefined;
    if (!b || typeof b.id !== "string" || !Number.isInteger(b.fee) || typeof b.currency !== "string"
      || !expires || Number.isNaN(expires.getTime())) {
      return { kind: "transient", code: "unexpected_quote" };
    }
    const eta = typeof b.dropoff_eta === "string" ? new Date(b.dropoff_eta) : null;
    return {
      kind: "ok",
      value: {
        quoteId: b.id, fee: b.fee as number, currency: b.currency.toUpperCase(), expiresAt: expires,
        dropoffEta: eta && !Number.isNaN(eta.getTime()) ? eta : null,
      },
    };
  }

  async create(req: CreateRequest): Promise<UberOutcome<UberDelivery>> {
    const r = await this.request("POST", "/deliveries", {
      quote_id: req.quoteId,
      pickup_name: req.pickupName,
      pickup_address: uberAddressJson(req.pickupAddress),
      pickup_phone_number: req.pickupPhone,
      dropoff_name: req.dropoffName,
      dropoff_address: uberAddressJson(req.dropoffAddress),
      dropoff_phone_number: req.dropoffPhone,
      ...(req.dropoffNotes ? { dropoff_notes: req.dropoffNotes } : {}),
      manifest_items: req.items.map((i) => ({ name: i.name, quantity: i.quantity, size: i.size })),
      idempotency_key: req.doddyId,
      external_id: req.doddyId,
      ...(this.config.mode === "test" ? { test_specifications: { robo_courier_specification: { mode: "auto" } } } : {}),
    });
    if (r.kind !== "ok") return r;
    const d = parseDelivery(r.value);
    // A 2xx Uber may have acted on, without a delivery we can read: not success.
    return d ? { kind: "ok", value: d } : { kind: "unknown", code: "unexpected_delivery" };
  }

  async get(uberId: string): Promise<UberOutcome<UberDelivery>> {
    const r = await this.request("GET", `/deliveries/${encodeURIComponent(uberId)}`);
    if (r.kind !== "ok") return r;
    const d = parseDelivery(r.value);
    return d ? { kind: "ok", value: d } : { kind: "transient", code: "unexpected_delivery" };
  }

  async cancel(uberId: string): Promise<UberOutcome<UberDelivery>> {
    const r = await this.request("POST", `/deliveries/${encodeURIComponent(uberId)}/cancel`);
    if (r.kind !== "ok") return r;
    const d = parseDelivery(r.value);
    return d ? { kind: "ok", value: d } : { kind: "unknown", code: "unexpected_delivery" };
  }

  async findByExternalId(doddyId: string): Promise<UberOutcome<UberDelivery | null>> {
    const r = await this.request("GET", "/deliveries?limit=50");
    if (r.kind !== "ok") return r;
    const data = (r.value as { data?: unknown } | undefined)?.data;
    if (!Array.isArray(data)) return { kind: "transient", code: "unexpected_list" };
    for (const item of data) {
      const d = parseDelivery(item);
      if (d?.externalId === doddyId) return { kind: "ok", value: d };
    }
    return { kind: "ok", value: null };
  }
}
