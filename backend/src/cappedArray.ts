import { z } from "zod";

/**
 * A list of `min` to `max` items that is refused for its LENGTH before any item is looked at (ADR-711).
 *
 * zod 3 (advisory GHSA-mrhx-c7xc-m3w5, fixed only in zod 4) checks every item of an over-long array and
 * keeps an issue for each one that fails, so refusing a list costs memory in proportion to its size, not
 * to the limit: measured here, a body of 400,000 empty objects (1.2 MB) grew the heap by about 190 MB, and
 * the largest request cap (8 MiB of kept notes) would take over a gigabyte. Here the length is judged on
 * an unchecked list, a wrong length is a fatal issue (so nothing after it, such as a cross-check that
 * reads the items, runs on unvalidated data), and `pipe` hands only a list of the right length to the
 * real item schema. The refusal, its path and its code (`too_big`, `too_small`, `invalid_type`) are the
 * ones zod's own array gives.
 *
 * Used for the routes whose body cap is large (kept notes, a conversation, the Messages copy); every other
 * list arrives in a body capped at 128 KB or less (`readJson`, `ASSIST_MAX_BODY_BYTES`, Logbook).
 */
export function cappedArray<T extends z.ZodTypeAny>(item: T, max: number, min = 0) {
  const length = z.unknown().superRefine((value, ctx) => {
    if (!Array.isArray(value)) {
      ctx.addIssue({ code: z.ZodIssueCode.invalid_type, expected: "array", received: z.getParsedType(value), fatal: true });
    } else if (value.length > max) {
      ctx.addIssue({ code: z.ZodIssueCode.too_big, type: "array", maximum: max, inclusive: true, exact: false, fatal: true });
    } else if (value.length < min) {
      ctx.addIssue({ code: z.ZodIssueCode.too_small, type: "array", minimum: min, inclusive: true, exact: false, fatal: true });
    }
  });
  return length.pipe(z.array(item));
}
