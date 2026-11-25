import { z } from "zod";

/**
 * Doddy Web contract, v1 (ADR-600). The iPhone app and the web app read the same shapes; the
 * fixtures in contracts/web/ are written from real server output (`npm run fixtures`).
 */

/** What the browser posts to sign in: the code the iPhone shows. */
export const RedeemRequestSchema = z.object({ code: z.string().min(1).max(32) }).strict();

/** A code the iPhone shows; the browser types it within its lifetime, once. */
export const LinkCodeSchema = z
  .object({
    /** Eight letters and digits, shown as two groups of four ("K7QM-4XPA"). */
    code: z.string().regex(/^[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}$/),
    expiresAt: z.string(),
    /** Where to type it. The phone shows this address, so a look-alike site stands out. */
    webOrigin: z.string(),
  })
  .strict();
export type LinkCode = z.infer<typeof LinkCodeSchema>;

export const Browser = z.enum(["chrome", "edge", "firefox", "safari", "opera", "other"]);
export const Os = z.enum(["macos", "windows", "ios", "ipados", "android", "linux", "chromeos", "other"]);

export const WebSessionViewSchema = z
  .object({
    id: z.string().uuid(),
    browser: Browser,
    os: Os,
    createdAt: z.string(),
    lastSeenAt: z.string(),
    expiresAt: z.string(),
    /** True for the browser that asked. Always false when the iPhone asks. */
    current: z.boolean(),
  })
  .strict();
export type WebSessionView = z.infer<typeof WebSessionViewSchema>;

export const CurrentSessionSchema = z.object({ session: WebSessionViewSchema }).strict();
export const SessionListSchema = z.object({ sessions: z.array(WebSessionViewSchema) }).strict();

/**
 * An iPhone of the account (decision 2026-11-12-account-and-device-tokens, part c). `id` is the stored row's own random
 * id, the one a revoke names: never the device id the iPhone keeps. Times are ISO strings.
 */
export const DeviceViewSchema = z
  .object({
    id: z.string().uuid(),
    /** A short name, when the iPhone has told the server one. The app sends none yet, so it is null. */
    label: z.string().nullable(),
    firstSeenAt: z.string(),
    /** Written at most about once an hour. */
    lastSeenAt: z.string(),
    /** True for the iPhone that asked. Always false when a browser asks. */
    current: z.boolean(),
    /** How it uses this account: null for the iPhone's own account, else the Apple or Google sign-in it joined with and when that join ends unless it signs in again. */
    joined: z.object({ provider: z.enum(["google", "apple"]), since: z.string(), expiresAt: z.string() }).strict().nullable(),
    /** When it was revoked, or null. A revoked iPhone's tokens no longer work. */
    revokedAt: z.string().nullable(),
  })
  .strict();
export type DeviceView = z.infer<typeof DeviceViewSchema>;
export const DeviceListSchema = z.object({ devices: z.array(DeviceViewSchema) }).strict();
export const DeviceRevocationSchema = z.object({ revoked: z.literal(true), revokedAt: z.string() }).strict();

export const DocumentKind = z.enum(["deck", "doc", "spreadsheet", "pdf", "text", "file"]);
/**
 * `working`: Claude is still making it. `interrupted`: it was being made when the server stopped,
 * so nothing is making it any more (the job ran in that server's memory). Never shown as working.
 */
export const DocumentStatus = z.enum(["working", "ready", "failed", "interrupted"]);

export const DocumentViewSchema = z
  .object({
    id: z.string().regex(/^[A-Za-z0-9_-]{24}$/),
    name: z.string(),
    kind: DocumentKind,
    status: DocumentStatus,
    createdAt: z.string(),
    /** When the server deletes it (documents are kept 30 days since 25 Nov 2026; a week before, ADR-564). */
    deleteAfter: z.string(),
    sizeBytes: z.number().int().nonnegative().nullable(),
  })
  .strict();
export type DocumentView = z.infer<typeof DocumentViewSchema>;

export const DocumentListSchema = z.object({ documents: z.array(DocumentViewSchema), keptDays: z.number().int().positive() }).strict();
