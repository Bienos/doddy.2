import { z } from "zod";
import type { CalendarEvent } from "./contracts.js";
import { ProviderError } from "./errors.js";
import type { DayWindow } from "./time.js";

/**
 * Normalizes one page of a GOOGLECALENDAR_EVENTS_LIST result (Composio tool output schema,
 * recorded in docs/integrations/COMPOSIO_INTEGRATION_PLAN.md). Only title, times and recurrence
 * survive; descriptions, attendees, locations and conference links are dropped here and are
 * also excluded from the request's `fields` selector.
 */

const EventDateTime = z.object({ date: z.string().optional(), dateTime: z.string().optional() }).passthrough();

const RawEvent = z
  .object({
    status: z.string().optional(),
    summary: z.string().optional(),
    start: EventDateTime.optional(),
    end: EventDateTime.optional(),
    recurringEventId: z.string().optional(),
    eventType: z.string().optional(),
  })
  .passthrough();

export const RawExecution = z
  .object({
    successful: z.boolean(),
    error: z.string().nullable().optional(),
    data: z
      .object({
        items: z.array(RawEvent).optional(),
        nextPageToken: z.string().optional(),
        summary: z.string().optional(),
      })
      .passthrough(),
  })
  .passthrough();

/** `fields` selector sent to the provider so unneeded event content is never fetched. */
export const EVENT_FIELDS = "items(status,summary,start,end,recurringEventId,eventType),nextPageToken,summary";

export interface NormalizedPage {
  events: CalendarEvent[];
  cancelled: number;
  nextPageToken: string | null;
  calendarSummary: string | null;
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export function normalizePage(raw: unknown, window: DayWindow, maxTitleLength: number): NormalizedPage {
  const parsed = RawExecution.safeParse(raw);
  if (!parsed.success) throw new ProviderError("malformed_provider_result");
  if (!parsed.data.successful) throw new ProviderError("provider_unavailable");

  const events: CalendarEvent[] = [];
  let cancelled = 0;
  for (const item of parsed.data.data.items ?? []) {
    if (item.status === "cancelled") {
      cancelled += 1;
      continue;
    }
    const event = normalizeEvent(item, window, maxTitleLength);
    if (event) events.push(event);
  }
  return {
    events,
    cancelled,
    nextPageToken: parsed.data.data.nextPageToken ?? null,
    calendarSummary: parsed.data.data.summary ?? null,
  };
}

function normalizeEvent(item: z.infer<typeof RawEvent>, window: DayWindow, maxTitleLength: number): CalendarEvent | null {
  const title = boundedTitle(item.summary, maxTitleLength);
  const isRecurring = typeof item.recurringEventId === "string";
  const s = item.start;
  const e = item.end;
  if (!s || !e) throw new ProviderError("malformed_provider_result");

  if (s.date !== undefined || e.date !== undefined) {
    // All-day: dates are calendar dates with an exclusive end. Keep it only if it covers the asked date,
    // so an adjacent all-day event pulled in by a calendar in another time zone is not shown.
    if (!s.date || !e.date || !DATE.test(s.date) || !DATE.test(e.date) || e.date <= s.date) {
      throw new ProviderError("malformed_provider_result");
    }
    if (!(s.date <= window.date && window.date < e.date)) return null;
    return { title, allDay: true, start: s.date, end: e.date, isRecurring };
  }

  const startMs = s.dateTime ? Date.parse(s.dateTime) : NaN;
  const endMs = e.dateTime ? Date.parse(e.dateTime) : NaN;
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs < startMs) {
    throw new ProviderError("malformed_provider_result");
  }
  // Overlap with [start of local day, start of next local day).
  const overlaps = startMs < window.endMs && (endMs > window.startMs || (endMs === startMs && startMs >= window.startMs));
  if (!overlaps) return null;
  return {
    title,
    allDay: false,
    start: new Date(startMs).toISOString(),
    end: new Date(endMs).toISOString(),
    isRecurring,
  };
}

function boundedTitle(summary: string | undefined, max: number): string {
  // Strip control characters; event text is untrusted and only ever displayed.
  const clean = (summary ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  if (clean === "") return "(No title)";
  const chars = [...clean];
  return chars.length > max ? `${chars.slice(0, max - 1).join("")}…` : clean;
}

/** Sort: all-day first, then by start time, then title. Stable and deterministic. */
export function sortEvents(events: CalendarEvent[]): CalendarEvent[] {
  return [...events].sort((a, b) => {
    if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
    if (a.start !== b.start) return a.start < b.start ? -1 : 1;
    return a.title < b.title ? -1 : a.title > b.title ? 1 : 0;
  });
}

/** Masks a calendar name such as an email: "alex@example.com" → "a•••@e•••.com". */
export function maskLabel(label: string | null): string | null {
  if (!label) return null;
  const at = label.indexOf("@");
  if (at > 0) {
    const local = label.slice(0, at);
    const domain = label.slice(at + 1);
    const dot = domain.lastIndexOf(".");
    const host = dot > 0 ? domain.slice(0, dot) : domain;
    const tld = dot > 0 ? domain.slice(dot) : "";
    return `${local[0]}•••@${host[0] ?? ""}•••${tld}`;
  }
  const chars = [...label];
  return chars.length <= 2 ? "••" : `${chars[0]}•••${chars[chars.length - 1]}`;
}

