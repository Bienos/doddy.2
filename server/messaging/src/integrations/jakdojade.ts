import { XMLParser, XMLValidator } from "fast-xml-parser";

/**
 * Official Jakdojade REST/XML partner integration, intentionally NOT routed to an app or user yet.
 * Requires licensed credentials supplied server-side. A missing key is a hard failure, never a
 * silent test=true fallback. No arbitrary URLs, user account, posting or ticket purchases.
 *
 * https://docs.jakdojade.pl/restxml/rest/
 * https://docs.jakdojade.pl/restxml/connections/
 * https://docs.jakdojade.pl/restxml/locations/
 */
const ORIGIN = "https://jakdojade.pl";
const ROUTES = "/api/rest/v2/routes";
const LOCATIONS = "/api/rest/v1/locationmatcher";
const MAX_BODY = 256 * 1024;
const TIMEOUT_MS = 8_000;
export const JAKDOJADE_MAX_ROUTES = 3;

export type PartnerCredentials = Readonly<{ licenseKey: string; secret: string }>;
export type CredentialSource = () => Promise<PartnerCredentials | null>;
export type PartnerFetch = (url: URL, init: RequestInit) => Promise<Response>;

export class JakdojadePartnerError extends Error {
  constructor(readonly code:
    "not_configured" | "invalid_request" | "unauthorized" | "forbidden" |
    "rate_limited" | "unavailable" | "invalid_response") {
    super(code);
    this.name = "JakdojadePartnerError";
  }
}

export interface Coordinates {
  latitude: number;
  longitude: number;
}
export interface PartnerLocation {
  name: string;
  type: "stop" | "street" | "poi";
  coordinate: Coordinates;
  stopCode: string | null;
}
export interface PartnerSegment {
  line: string;
  vehicleType: string;
  direction: string | null;
  stops: { name: string; departure: string | null; arrival: string | null }[];
}
export interface PartnerRoute {
  source: "Jakdojade";
  startLocal: string;
  finishLocal: string;
  segments: PartnerSegment[];
}
export interface PartnerRouteSearch {
  from: Coordinates;
  to: Coordinates;
  /// Date and time in Poland local clock, as documented by Jakdojade.
  day?: string; // DD.MM.YY
  hour?: string; // HH:mm
  arriving?: boolean;
  mode?: "optimal" | "convenient" | "hurry";
  avoidBuses?: boolean;
  avoidTransfers?: boolean;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
function asItems(value: unknown): unknown[] {
  return value === undefined || value === null ? [] : Array.isArray(value) ? value : [value];
}
function literal(value: unknown, max = 160): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim().slice(0, max) : null;
}
function finite(point: Coordinates): boolean {
  return Number.isFinite(point.latitude) && Number.isFinite(point.longitude)
    && point.latitude >= -90 && point.latitude <= 90
    && point.longitude >= -180 && point.longitude <= 180;
}
function coords(value: string): Coordinates | null {
  const match = /^(-?\d{1,2}(?:\.\d+)?):(-?\d{1,3}(?:\.\d+)?)$/.exec(value);
  if (!match) return null;
  const c = { latitude: Number(match[1]), longitude: Number(match[2]) };
  return finite(c) ? c : null;
}
function formatCoords(point: Coordinates): string {
  if (!finite(point)) throw new JakdojadePartnerError("invalid_request");
  return `${point.latitude.toFixed(6)}:${point.longitude.toFixed(6)}`;
}
function clock(value: unknown): string | null {
  const text = literal(value, 16);
  return text && /^\d{2}:\d{2}$/.test(text) ? text : null;
}
function placeRows(xml: unknown): PartnerLocation[] {
  const root = asRecord(asRecord(xml)?.LOCATIONS_MATCH_RESULT);
  if (!root) throw new JakdojadePartnerError("invalid_response");
  const items = asItems(asRecord(root.locations)?.location);
  return items.slice(0, 10).flatMap((value): PartnerLocation[] => {
    const entry = asRecord(value);
    const label = literal(entry?.name, 120);
    const location = literal(entry?.coordinate, 60);
    const type = entry?.type;
    const coord = location ? coords(location) : null;
    if (!entry || !label || !coord || (type !== "stop" && type !== "street" && type !== "poi")) return [];
    return [{ name: label, type, coordinate: coord, stopCode: literal(entry.stopCode, 60) }];
  });
}
function routeRows(xml: unknown): PartnerRoute[] {
  const root = asRecord(asRecord(xml)?.ROUTE_SEARCH_RESULT);
  if (!root) throw new JakdojadePartnerError("invalid_response");
  return asItems(asRecord(root.routes)?.route).slice(0, JAKDOJADE_MAX_ROUTES)
    .flatMap((value): PartnerRoute[] => {
      const route = asRecord(value);
      const start = literal(route?.startDate, 16);
      const finish = literal(route?.finishDate, 16);
      const timeFormat = /^\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}$/;
      if (!route || !start || !finish || !timeFormat.test(start) || !timeFormat.test(finish)) return [];
      const segments = asItems(asRecord(route.lines)?.line).slice(0, 20)
        .flatMap((value): PartnerSegment[] => {
          const row = asRecord(value);
          const line = literal(row?.name, 40);
          const vehicleType = literal(row?.vehicleType, 32);
          if (!row || !line || !vehicleType) return [];
          const stops = asItems(asRecord(row.stops)?.stop).slice(0, 50)
            .flatMap((stop): PartnerSegment["stops"] => {
              const s = asRecord(stop);
              const name = literal(s?.name, 90);
              return name ? [{ name, departure: clock(s?.departureTime), arrival: clock(s?.arrivalTime) }] : [];
            });
          return [{ line, vehicleType, direction: literal(row.direction, 80), stops }];
        });
      if (segments.length === 0) return [];
      return [{ source: "Jakdojade", startLocal: start, finishLocal: finish, segments }];
    });
}

export class JakdojadePartnerClient {
  constructor(private readonly credentials: CredentialSource,
    private readonly fetcher: PartnerFetch = (url, options) => fetch(url, options)) {}

  async locations(city: string, search: string): Promise<PartnerLocation[]> {
    const agg = city.trim().toUpperCase();
    const q = search.trim();
    if (!/^[A-Z_]{2,40}$/.test(agg) || q.length < 2 || q.length > 100 ||
        /[\x00-\x1f\x7f]/.test(q)) throw new JakdojadePartnerError("invalid_request");
    const url = new URL(LOCATIONS, ORIGIN);
    url.searchParams.set("agg", agg);
    url.searchParams.set("text", q);
    return placeRows(await this.request(url));
  }

  async routes(input: PartnerRouteSearch): Promise<PartnerRoute[]> {
    const url = new URL(ROUTES, ORIGIN);
    url.searchParams.set("fc", formatCoords(input.from));
    url.searchParams.set("tc", formatCoords(input.to));
    url.searchParams.set("rc", String(JAKDOJADE_MAX_ROUTES));
    url.searchParams.set("rcoor", "false");
    if (input.day && !/^\d{2}\.\d{2}\.\d{2}$/.test(input.day)) throw new JakdojadePartnerError("invalid_request");
    if (input.hour && !/^\d{2}:\d{2}$/.test(input.hour)) throw new JakdojadePartnerError("invalid_request");
    if (input.day) url.searchParams.set("d", input.day);
    if (input.hour) url.searchParams.set("h", input.hour);
    if (input.arriving !== undefined) url.searchParams.set("ia", String(input.arriving));
    if (input.mode) url.searchParams.set("t", input.mode);
    if (input.avoidTransfers) url.searchParams.set("aac", "true");
    if (input.avoidBuses) url.searchParams.set("aab", "true");
    return routeRows(await this.request(url));
  }

  private async request(url: URL): Promise<unknown> {
    if (url.origin !== ORIGIN || (url.pathname !== ROUTES && url.pathname !== LOCATIONS))
      throw new JakdojadePartnerError("invalid_request");
    // Partner API without auth returns sample test data. Not configured MUST NOT appear successful.
    const auth = await this.credentials();
    if (!auth || !auth.licenseKey || !auth.secret ||
        auth.licenseKey.length > 200 || auth.secret.length > 300 ||
        /[\r\n]/.test(auth.licenseKey + auth.secret))
      throw new JakdojadePartnerError("not_configured");
    url.searchParams.set("output", "xml");
    const timeout = new AbortController();
    const handle = setTimeout(() => timeout.abort(), TIMEOUT_MS);
    try {
      const response = await this.fetcher(url, {
        method: "GET",
        headers: {
          authorization: `Basic ${Buffer.from(`${auth.licenseKey}:${auth.secret}`).toString("base64")}`,
          accept: "application/xml",
        },
        signal: timeout.signal,
        redirect: "error",
      });
      if (response.status === 401) throw new JakdojadePartnerError("unauthorized");
      if (response.status === 403) throw new JakdojadePartnerError("forbidden");
      if (response.status === 429) throw new JakdojadePartnerError("rate_limited");
      if (!response.ok) throw new JakdojadePartnerError("unavailable");
      if (Number(response.headers.get("content-length") ?? 0) > MAX_BODY)
        throw new JakdojadePartnerError("invalid_response");
      if (!response.body) throw new JakdojadePartnerError("invalid_response");
      const stream = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let total = 0;
      try {
        while (true) {
          const part = await stream.read();
          if (part.done) break;
          total += part.value.length;
          if (total > MAX_BODY) throw new JakdojadePartnerError("invalid_response");
          chunks.push(part.value);
        }
      } finally {
        stream.releaseLock();
      }
      const bytes = Buffer.concat(chunks.map((c) => Buffer.from(c)), total);
      const raw = bytes.toString("utf8");
      if (!raw.startsWith("<") && !raw.startsWith("<?xml")) throw new JakdojadePartnerError("invalid_response");
      if (/<!DOCTYPE|<!ENTITY/i.test(raw) || XMLValidator.validate(raw) !== true)
        throw new JakdojadePartnerError("invalid_response");
      return new XMLParser({
        ignoreAttributes: false,
        attributeNamePrefix: "",
        parseAttributeValue: false,
        parseTagValue: false,
        processEntities: false,
        trimValues: true,
      }).parse(raw) as unknown;
    } catch (error) {
      if (error instanceof JakdojadePartnerError) throw error;
      throw new JakdojadePartnerError("unavailable");
    } finally {
      clearTimeout(handle);
    }
  }
}
