import { z } from "zod";
import { AppError } from "../errors.js";
import { argumentDigest, type UsageLimiter } from "../policy.js";
import type { Store, WriteOutcome } from "../store.js";
import type { ReceiptStatus } from "../contracts.js";
import type { AskGate } from "../tools/askFirst.js";
import type { PrepareResult, RunResult, ToolReceipt } from "../tools/contracts.js";
import {
  BOOK_FLIGHT_TOOL,
  BookFlightInput,
  bookingCard,
  buildBooking,
  DUFFEL_ORDER_TIMEOUT_MS,
  DUFFEL_SEARCH_TIMEOUT_MS,
  type DuffelClient,
  FIND_BOOKABLE_FLIGHTS_TOOL,
  FindBookableFlightsInput,
  normalizeOffers,
  type OrderOutcome,
  type BookingPayload,
} from "./duffel.js";
import { FIND_FLIGHTS_TOOL, findFlightsCard, FindFlightsInput, KIWI_TIMEOUT_MS, type KiwiClient, normalizeKiwi } from "./kiwi.js";

/**
 * Flights on Doddy's server (decision 2026-11-11-flights-kiwi-search-duffel-booking), on the same
 * ASK-01 gate as every other server tool (`askFirst.ts`):
 *  - `find_flights` (Kiwi.com), `find_bookable_flights` (Duffel) and `check_flight_booking` are reads:
 *    the app asks for the approval and uses it at once, because the user asked.
 *  - `book_flight` is a write. `prepare` reads the offer from Duffel, builds the exact booking and binds a
 *    single-use approval to its digest; the card shows that booking. `run` reads the offer again and
 *    books only if the booking it builds now has the same digest, so a changed price, flight or
 *    passenger voids the tap. The approval's account is `duffel:<offer id>`, so every try at one offer
 *    can be found, and one that did or may have gone through blocks another.
 *  - "booked" only on Duffel's 201 with an order id and a booking reference. Duffel's answers that prove
 *    nothing was booked are "failed"; everything else is "unknown" and is never retried.
 *  - Booking runs only with `FLIGHT_BOOKING_ENABLED=1` and a Duffel test key.
 */

export const CHECK_FLIGHT_BOOKING_TOOL = "check_flight_booking";
export const FLIGHT_TOOLS = [FIND_FLIGHTS_TOOL, FIND_BOOKABLE_FLIGHTS_TOOL, CHECK_FLIGHT_BOOKING_TOOL, BOOK_FLIGHT_TOOL] as const;
export type FlightTool = (typeof FLIGHT_TOOLS)[number];
export const isFlightTool = (name: string): name is FlightTool => (FLIGHT_TOOLS as readonly string[]).includes(name);

export const CheckFlightBookingInput = z.object({ offer_id: z.string().regex(/^off_[A-Za-z0-9]{10,40}$/) }).strict();

const KIWI_ACCOUNT = "kiwi";
const DUFFEL_ACCOUNT = "duffel";
const offerAccount = (offerId: string) => `duffel:${offerId}`;
/** How far back a try at the same offer blocks another. Duffel offers live minutes, so a week is plenty. */
const ATTEMPT_WINDOW_MS = 7 * 86_400_000;
/** How long the app's request waits in all (offer check, then Duffel). Under the app's 20 s timeout; the booking goes on after it. */
export const BOOKING_WAIT_MS = 16_000;

type Receipt = (operation: "read" | "write", tool: FlightTool, status: ReceiptStatus, summary: string, errorCode: string | null, providerReference: string | null) => Promise<ToolReceipt>;

export interface FlightsDeps {
  store: Store;
  ask: AskGate;
  limiter: UsageLimiter;
  mode: "mock" | "live";
  now: () => number;
  kiwi: KiwiClient | null;
  duffel: DuffelClient | null;
  /** FLIGHT_BOOKING_ENABLED. Off by default. */
  bookingEnabled: boolean;
  /** Bookings still waiting for Duffel after the app's request returned. Shared with the tools service so tests and shutdown wait for them. */
  background: Set<Promise<void>>;
  bookingWaitMs?: number;
  log?: (line: Record<string, unknown>) => void;
}

interface RunRequest {
  arguments: Record<string, unknown>;
  timeZone: string;
  approvalId?: string | undefined;
}

const parse = <T>(schema: z.ZodType<T, z.ZodTypeDef, unknown>, raw: unknown): T => {
  const result = schema.safeParse(raw);
  if (!result.success) {
    const issue = result.error.issues[0];
    throw new AppError("invalid_request", { message: issue ? `${issue.path.join(".") || "arguments"}: ${issue.message}` : "The request was not valid." });
  }
  return result.data;
};

export class FlightsService {
  constructor(private readonly deps: FlightsDeps) {}

  // ---------------------------------------------------------------- prepare

  async prepare(userId: string, tool: FlightTool, raw: Record<string, unknown>, receipt: Receipt): Promise<PrepareResult> {
    const { ask, limiter, now, mode } = this.deps;
    await limiter.reserveRequest(userId, now());
    const issue = async (accountId: string, argsDigest: string, preview: PrepareResult["preview"]): Promise<PrepareResult> => {
      const { approvalId, expiresAt } = await ask.issue({ userId, tool, accountId, argsDigest });
      return { mode, tool, preview, approvalId, expiresAt: new Date(expiresAt).toISOString() };
    };
    if (tool === FIND_FLIGHTS_TOOL) {
      const args = parse(FindFlightsInput, raw);
      await this.requireKiwi(tool, receipt);
      return issue(KIWI_ACCOUNT, argumentDigest(args), findFlightsCard(args));
    }
    if (tool === FIND_BOOKABLE_FLIGHTS_TOOL) {
      const args = parse(FindBookableFlightsInput, raw);
      await this.requireDuffel(tool, receipt);
      return issue(DUFFEL_ACCOUNT, argumentDigest(args), {
        title: "Search flights Doddy can book?",
        lines: [`${args.from} → ${args.to}, ${args.departure_date}${args.return_date ? `, back ${args.return_date}` : ""}`, "The route, dates and ages go to Doddy's server and Duffel. Nothing is booked."],
        confirmLabel: "Yes, search",
      });
    }
    if (tool === CHECK_FLIGHT_BOOKING_TOOL) {
      const args = parse(CheckFlightBookingInput, raw);
      return issue(DUFFEL_ACCOUNT, argumentDigest(args), { title: "Check the booking?", lines: ["Doddy looks at what Duffel answered for this offer."], confirmLabel: "Yes, check" });
    }

    // book_flight
    const args = parse(BookFlightInput, raw);
    const duffel = await this.requireBooking(receipt);
    await this.refuseIfTriedBefore(userId, args.offer_id, receipt);
    const payload = await limiter.withSlot(userId, () => this.currentBooking(duffel, args, receipt));
    return issue(offerAccount(args.offer_id), argumentDigest(payload), bookingCard(payload));
  }

  // ---------------------------------------------------------------- run

  async run(userId: string, tool: FlightTool, request: RunRequest, receipt: Receipt): Promise<RunResult> {
    const { ask, limiter, now, mode } = this.deps;
    await limiter.reserveRequest(userId, now());
    if (tool === BOOK_FLIGHT_TOOL) return this.book(userId, request, receipt);

    const args: Record<string, unknown> =
      tool === FIND_FLIGHTS_TOOL ? parse(FindFlightsInput, request.arguments) : tool === FIND_BOOKABLE_FLIGHTS_TOOL ? parse(FindBookableFlightsInput, request.arguments) : parse(CheckFlightBookingInput, request.arguments);
    const accountId = tool === FIND_FLIGHTS_TOOL ? KIWI_ACCOUNT : DUFFEL_ACCOUNT;
    const binding = { userId, tool, accountId, argsDigest: argumentDigest(args) };
    const unasked = async () => askFirstRefusal(await receipt("read", tool, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (tool === FIND_FLIGHTS_TOOL) await this.requireKiwi(tool, receipt);
    if (tool === FIND_BOOKABLE_FLIGHTS_TOOL) await this.requireDuffel(tool, receipt);
    if (!(await ask.allows(binding, request.approvalId, "check"))) throw await unasked();

    if (tool === CHECK_FLIGHT_BOOKING_TOOL) {
      if (!(await ask.allows(binding, request.approvalId, "use"))) throw await unasked();
      const outcome = await this.checkBooking(userId, args.offer_id as string);
      const r = await receipt("read", tool, "succeeded", "Checked a flight booking.", null, null);
      return { mode, tool, text: outcome, count: 1, truncated: false, receipt: r };
    }

    try {
      await limiter.reserveToolRun(userId, now());
    } catch (error) {
      if (error instanceof AppError) throw new AppError("quota_exceeded", { message: "Today's flight search limit was reached.", receipt: await receipt("read", tool, "blocked", "Not done: today's limit was reached.", error.code, null) });
      throw error;
    }
    try {
      return await limiter.withSlot(userId, async () => {
        if (!(await ask.allows(binding, request.approvalId, "use"))) throw await unasked();
        if (tool === FIND_FLIGHTS_TOOL) {
          const output = await this.deps.kiwi!.search({ args: args as z.infer<typeof FindFlightsInput>, signal: AbortSignal.timeout(KIWI_TIMEOUT_MS) });
          const outcome = normalizeKiwi(output, args as z.infer<typeof FindFlightsInput>);
          const r = await receipt("read", tool, "succeeded", outcome.summary, null, null);
          const links = outcome.flights.flatMap((f) => (f.bookingUrl ? [{ title: `${f.price} ${f.currency}, ${f.from} → ${f.to}, ${f.departs.replace("T", " ").slice(0, 16)}`, url: f.bookingUrl }] : []));
          return { mode, tool, text: outcome.text, count: outcome.count, truncated: outcome.truncated, ...(links.length > 0 ? { links } : {}), receipt: r };
        }
        const output = await this.deps.duffel!.search({ args: args as z.infer<typeof FindBookableFlightsInput>, signal: AbortSignal.timeout(DUFFEL_SEARCH_TIMEOUT_MS) });
        const outcome = normalizeOffers(output, args as z.infer<typeof FindBookableFlightsInput>);
        const r = await receipt("read", tool, "succeeded", outcome.summary, null, null);
        return { mode, tool, text: outcome.text, count: outcome.count, truncated: outcome.truncated, receipt: r };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      const code = typeof (error as { code?: unknown })?.code === "string" ? ((error as { code: string }).code as "rate_limited" | "provider_timeout" | "provider_unavailable" | "malformed_provider_result") : "provider_unavailable";
      const who = tool === FIND_FLIGHTS_TOOL ? "Kiwi.com" : "Duffel";
      const message = code === "rate_limited" ? `${who} is busy right now. Try again shortly.` : code === "malformed_provider_result" ? `${who} sent an answer Doddy couldn't read, so nothing is shown.` : `${who} couldn't be reached. Nothing is shown instead.`;
      const known = ["rate_limited", "provider_timeout", "provider_unavailable", "malformed_provider_result"].includes(code) ? code : "provider_unavailable";
      throw new AppError(known as "provider_unavailable", { message, receipt: await receipt("read", tool, "failed", message, known, null) });
    }
  }

  /** What Doddy knows about tries to book this offer. Reads only Doddy's own record of Duffel's answers. */
  private async checkBooking(userId: string, offerId: string): Promise<string> {
    const tries = await this.deps.store.usedApprovals({ userId, capability: BOOK_FLIGHT_TOOL, accountId: offerAccount(offerId), since: this.deps.now() - ATTEMPT_WINDOW_MS });
    const latest = tries.find((t) => t.outcome === "succeeded") ?? tries[0];
    if (!latest) return "Doddy hasn't tried to book this offer. Nothing was booked.";
    return outcomeText(latest.outcome, latest.externalId);
  }

  private async book(userId: string, request: RunRequest, receipt: Receipt): Promise<RunResult> {
    const { ask, store, limiter, now, mode } = this.deps;
    const tool = BOOK_FLIGHT_TOOL;
    const args = parse(BookFlightInput, request.arguments);
    const duffel = await this.requireBooking(receipt);
    const accountId = offerAccount(args.offer_id);
    const blocked = async (message: string, errorCode: string) =>
      new AppError("capability_disabled", { message, receipt: await receipt("write", tool, "blocked", `Not booked: ${message}`.slice(0, 200), errorCode, null) });

    // The phone lost the answer and sent the same approval again: what happened the first time answers it.
    if (request.approvalId !== undefined) {
      const earlier = await store.approvalOutcome({ approvalId: request.approvalId, userId, capability: tool, accountId, argsDigest: null });
      if (earlier) {
        const text = outcomeText(earlier.outcome, earlier.externalId);
        const status: ReceiptStatus = earlier.outcome === "succeeded" ? "succeeded" : earlier.outcome === "failed" ? "failed" : "outcome_unknown";
        const r = await receipt("write", tool, status, "Answer from the first try; nothing was booked again.", null, null);
        return { mode, tool, text, count: 1, truncated: false, replayed: true, receipt: r };
      }
    }
    if (!(await ask.issuedFor({ userId, tool, accountId }, request.approvalId))) {
      throw await blocked("The confirmation is missing or expired. Show the booking card again.", "confirmation_required");
    }
    await this.refuseIfTriedBefore(userId, args.offer_id, receipt);
    try {
      await limiter.reserveToolRun(userId, now());
    } catch (error) {
      if (error instanceof AppError) throw await blocked("Today's limit was reached.", error.code);
      throw error;
    }

    return limiter.withSlot(userId, async () => {
      // The app waits 20 s in all: the offer check below comes out of the time left to wait for Duffel.
      const startedAt = Date.now();
      // The offer as Duffel has it now: the booking is rebuilt and must be exactly the one on the card.
      const payload = await this.currentBooking(duffel, args, receipt);
      const binding = { userId, tool, accountId, argsDigest: argumentDigest(payload) };
      if (!(await ask.allows(binding, request.approvalId, "use"))) {
        throw await blocked("The price, the flights or the passengers changed since the card was shown. Search again.", "booking_changed");
      }
      const approvalId = request.approvalId!;
      const order = duffel
        .createOrder({ payload, signal: AbortSignal.timeout(DUFFEL_ORDER_TIMEOUT_MS) })
        .catch((): OrderOutcome => ({ kind: "unknown", code: "client_error" }))
        .then(async (outcome) => {
          const recorded: WriteOutcome = outcome.kind === "booked" ? "succeeded" : outcome.kind === "not_booked" ? "failed" : "outcome_unknown";
          await store.finishApproval(approvalId, recorded, outcome.kind === "booked" ? `${outcome.orderId} ${outcome.reference}` : null, now());
          this.deps.log?.({ level: "info", event: "flight_order", outcome: outcome.kind, code: outcome.kind === "booked" ? null : outcome.code });
          return outcome;
        });
      const waitMs = Math.max(1_000, (this.deps.bookingWaitMs ?? BOOKING_WAIT_MS) - (Date.now() - startedAt));
      const waited = await Promise.race([order, sleep(waitMs).then(() => null)]);
      if (waited === null) {
        // Duffel is still working: the booking goes on and its answer is recorded (check_flight_booking).
        const job = order.then(() => undefined, () => undefined);
        this.deps.background.add(job);
        void job.finally(() => this.deps.background.delete(job));
        const r = await receipt("write", tool, "outcome_unknown", "Duffel hasn't confirmed the booking yet.", "pending", null);
        return {
          mode, tool,
          text: "unknown: Duffel hasn't confirmed this booking yet; it may go through in the next two minutes. Tell the user, and offer to check with check_flight_booking for this offer in a minute. Never call book_flight again for it.",
          count: 1, truncated: false, receipt: r,
        };
      }
      return this.orderResult(waited, payload, receipt);
    });
  }

  private async orderResult(outcome: OrderOutcome, payload: BookingPayload, receipt: Receipt): Promise<RunResult> {
    const tool = BOOK_FLIGHT_TOOL;
    if (outcome.kind === "booked") {
      const r = await receipt("write", tool, "succeeded", `Booked a flight, reference ${outcome.reference}.`, null, outcome.orderId);
      const text = [
        `booked: Duffel confirmed the booking (test mode: no real ticket, nothing charged). Airline booking reference ${outcome.reference}, Duffel order ${outcome.orderId}, total ${outcome.amount ?? payload.amount} ${outcome.currency ?? payload.currency}.`,
        ...payload.itinerary,
        "Say the booking reference and that it is a test booking. Don't add details that aren't here.",
      ].join("\n");
      return { mode: this.deps.mode, tool, text, count: 1, truncated: false, externalId: outcome.orderId, receipt: r };
    }
    if (outcome.kind === "not_booked") {
      const r = await receipt("write", tool, "failed", `Not booked: ${outcome.message}`.slice(0, 200), outcome.code, null);
      return { mode: this.deps.mode, tool, text: `failed: ${outcome.message} Duffel said nothing was booked.`, count: 0, truncated: false, receipt: r };
    }
    const r = await receipt("write", tool, "outcome_unknown", "Duffel didn't confirm whether the flight was booked.", outcome.code, null);
    return {
      mode: this.deps.mode, tool,
      text: "unknown: Duffel didn't confirm whether this flight was booked. It may have been. Tell the user Doddy won't book this offer again, and that the owner can check it in Duffel. Never call book_flight again for it.",
      count: 1, truncated: false, receipt: r,
    };
  }

  // ---------------------------------------------------------------- checks

  private async requireKiwi(tool: FlightTool, receipt: Receipt): Promise<void> {
    if (this.deps.kiwi?.isConfigured()) return;
    const message = "Flight search isn't switched on on this server.";
    throw new AppError("live_not_configured", { message, receipt: await receipt("read", tool, "blocked", `Not done: ${message}`, "live_not_configured", null) });
  }

  private async requireDuffel(tool: FlightTool, receipt: Receipt): Promise<DuffelClient> {
    if (this.deps.duffel?.isConfigured()) return this.deps.duffel;
    const message = "Duffel isn't set up on this server.";
    throw new AppError("live_not_configured", { message, receipt: await receipt(tool === BOOK_FLIGHT_TOOL ? "write" : "read", tool, "blocked", `Not done: ${message}`, "live_not_configured", null) });
  }

  /** Booking needs the switch and a Duffel test key; a live key is refused (no real tickets yet). */
  private async requireBooking(receipt: Receipt): Promise<DuffelClient> {
    const duffel = await this.requireDuffel(BOOK_FLIGHT_TOOL, receipt);
    const message = !this.deps.bookingEnabled
      ? "Booking flights isn't switched on on this server."
      : !duffel.isTestMode()
        ? "Booking runs only with a Duffel test key until live booking is approved."
        : null;
    if (message === null) return duffel;
    throw new AppError("live_not_configured", { message, receipt: await receipt("write", BOOK_FLIGHT_TOOL, "blocked", `Not booked: ${message}`, "live_not_configured", null) });
  }

  /** A try at this offer that did, may have, or is still trying to go through blocks another. */
  private async refuseIfTriedBefore(userId: string, offerId: string, receipt: Receipt): Promise<void> {
    const tries = await this.deps.store.usedApprovals({ userId, capability: BOOK_FLIGHT_TOOL, accountId: offerAccount(offerId), since: this.deps.now() - ATTEMPT_WINDOW_MS });
    const open = tries.find((t) => t.outcome !== "failed");
    if (!open) return;
    if (open.outcome === "succeeded") {
      const message = `This offer is already booked (${outcomeText(open.outcome, open.externalId).replace(/^booked: /, "")}), so Doddy won't book it again.`;
      throw new AppError("capability_disabled", { message, receipt: await receipt("write", BOOK_FLIGHT_TOOL, "blocked", "Not booked again: already booked.", "already_booked", null) });
    }
    throw new AppError("capability_disabled", {
      message: "An earlier try at booking this offer may have gone through, so Doddy won't book it again.",
      receipt: await receipt("write", BOOK_FLIGHT_TOOL, "outcome_unknown", "An earlier try may have booked it; not tried again.", "earlier_outcome_unknown", null),
    });
  }

  /** Reads the offer from Duffel now and builds the exact booking, or refuses with the reason. */
  private async currentBooking(duffel: DuffelClient, args: z.output<typeof BookFlightInput>, receipt: Receipt): Promise<BookingPayload> {
    const refuse = async (message: string, code: string) =>
      new AppError("not_found", { message, receipt: await receipt("write", BOOK_FLIGHT_TOOL, "blocked", `Not booked: ${message}`.slice(0, 200), code, null) });
    let offer;
    try {
      offer = await duffel.getOffer({ offerId: args.offer_id, signal: AbortSignal.timeout(DUFFEL_SEARCH_TIMEOUT_MS) });
    } catch {
      throw await refuse("Duffel couldn't be reached to check the offer.", "provider_unavailable");
    }
    if (!offer) throw await refuse("That offer is gone or expired. Search again.", "offer_gone");
    if (offer.liveMode && !duffel.isTestMode()) throw await refuse("Live offers can't be booked yet.", "live_offer");
    if (offer.expiresAt !== null && Date.parse(offer.expiresAt) <= this.deps.now()) throw await refuse("That offer has expired. Search again.", "offer_expired");
    const today = new Date(this.deps.now()).toISOString().slice(0, 10);
    const built = buildBooking(offer, args, today);
    if ("problem" in built) throw await refuse(built.problem, "passengers_mismatch");
    return built.payload;
  }
}

/** One record of a booking try, in the words the agent hears. */
export function outcomeText(outcome: WriteOutcome | null, externalId: string | null): string {
  if (outcome === "succeeded") {
    const [orderId, reference] = (externalId ?? "").split(" ");
    return `booked: Duffel confirmed this booking (test mode). Airline booking reference ${reference ?? "not recorded"}, Duffel order ${orderId ?? "not recorded"}.`;
  }
  if (outcome === "failed") return "failed: Duffel said this booking didn't go through. Nothing was booked.";
  if (outcome === null) return "unknown: Doddy is still waiting for Duffel's answer about this booking. Check again in a minute; never book this offer again.";
  return "unknown: Duffel never confirmed whether this booking went through. It may have. The owner can check in Duffel; Doddy won't book this offer again.";
}

/** ASK-01: a run that came without the user's yes for exactly this (same words as the tools service). */
function askFirstRefusal(receipt: ToolReceipt): AppError {
  return new AppError("capability_disabled", { message: "Doddy has to ask first: this needs the user's yes on the card.", receipt });
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms).unref?.());
